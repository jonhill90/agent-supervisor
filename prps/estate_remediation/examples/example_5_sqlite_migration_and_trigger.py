# Source: scripts/supervisor/core.py
# Lines: 271-274 (invocation), 702-790 (_migrate_lanes_table),
#        1011 + 1040-1170 (_migrate_source_tasks_pull_uniqueness / the trigger)
# Pattern: how this estate evolves its SQLite schema — a `_migrate_*` METHOD,
#          never a .sql file — and how it installs a BEFORE INSERT trigger
#          with RAISE(ABORT), which is exactly S6's mechanism.
# Extracted: 2026-08-19 from commit 6b7c4435
# Relevance: 10/10 — S6's interrogative guard, the `provenance` column, the
#            `possibility_count` view and the `sessions` registration (A2) all
#            land through this pattern.
#
# THERE IS NO MIGRATIONS DIRECTORY. Verified. Schema evolution lives in Python
# methods on `core.py`, called from `Ledger.__init__`:
#
#     self._migrate_lanes_table(failpoint=_migration_failpoint)          # core.py:271
#     self._migrate_tasks_table(failpoint=_migration_failpoint)          # core.py:272
#     self._migrate_source_tasks_table(...)                              # core.py:273
#     self._migrate_source_tasks_pull_uniqueness(...)                    # core.py:274
#
# A new migration is a new `_migrate_*` method plus one more line there.
# The `failpoint=` parameter is not decoration: it is how the rollback path
# gets TESTED. Every new migration must accept and honour it.

import contextlib


class LedgerMigrationPatterns:

    # ========================================================================
    # PATTERN A — REBUILD-IN-PLACE. Use when adding a column with a non-constant
    # backfill, or widening a CHECK constraint. SQLite has no ALTER COLUMN and
    # no DROP CONSTRAINT, so the table must be rebuilt.
    #
    # This is the pattern for the `prompts.provenance` column
    # (`NOT NULL CHECK (provenance IN ('human','agent'))`, backfilled from the
    # transcript's promptSource) — a CHECK plus a computed backfill, which is
    # exactly the two things that force a rebuild.
    # ========================================================================
    def _migrate_lanes_table(self, *, failpoint=None):
        """Widen an existing `lanes` table to the current schema in place.

        `CREATE TABLE IF NOT EXISTS` in `_initialize` never touches a table
        that already exists, so a ledger created before ... the `transport`
        column existed keeps rejecting/lacking them forever unless this runs.
        SQLite has no `ALTER TABLE ... ALTER COLUMN` / `DROP CONSTRAINT`, so
        the only way to widen a CHECK constraint -- or add a NOT NULL column
        with a backfill that is not a flat constant -- is to rebuild the table.

        Every row is preserved. The rebuild is one transaction: any failure
        mid-migration rolls back to the original table, unmodified. Foreign
        key enforcement is turned off only around this rebuild (it cannot be
        toggled mid-transaction) because `tasks.lane REFERENCES lanes(lane)`
        would otherwise block dropping the original table while rows still
        reference it.
        """
        with self._locked():
            with contextlib.closing(self._connect()) as probe:
                existing = probe.execute(
                    "SELECT sql FROM sqlite_master WHERE type='table' AND name='lanes'"
                ).fetchone()
                if existing is None:
                    return                                    # nothing to migrate
                if all(marker in existing["sql"] for marker in self._LANES_SCHEMA_MARKERS):
                    return                                    # IDEMPOTENT: already current

                # agent-dotfiles#237: which columns the OLD table actually has,
                # ASKED rather than assumed. This rebuild now runs for FOUR
                # different reasons and a ledger can need any subset of them.
                # A hardcoded copy list would read a column that does not exist
                # yet on one path, and silently DROP recorded session ids on another.
                old_columns = {row["name"] for row in probe.execute("PRAGMA table_info(lanes)").fetchall()}

            # PER-COLUMN BACKFILL EXPRESSIONS, each argued. Note the third one:
            # the backfill records WHAT ACTUALLY HAPPENED rather than a uniform
            # guess, and a ledger that already has the column keeps its own value.
            harness_session_expr = "harness_session_id" if "harness_session_id" in old_columns else "''"
            # agent-supervisor#172: a pre-existing row has no recorded originating
            # project directory -- and it must NOT be guessed as `repo`. Empty is
            # the correct backfill; `restore.sh` fails closed on either.
            harness_project_dir_expr = "harness_project_dir" if "harness_project_dir" in old_columns else "''"
            transport_expr = (
                "transport" if "transport" in old_columns
                else "CASE WHEN harness = 'copilot-acp' THEN 'acp' ELSE 'send-keys' END"
            )

            connection = self._connect(foreign_keys=False)
            try:
                connection.execute("BEGIN IMMEDIATE")          # <-- IMMEDIATE, not deferred
                try:
                    connection.execute(
                        """
                        CREATE TABLE lanes_migrated (
                            lane TEXT PRIMARY KEY,
                            harness TEXT NOT NULL CHECK (harness IN ('codex','claude','copilot','copilot-acp','pi')),
                            harness_session_id TEXT DEFAULT '',
                            harness_project_dir TEXT DEFAULT '',
                            transport TEXT NOT NULL DEFAULT 'send-keys'
                                CHECK (transport IN ('send-keys','acp','pi-rpc','claude-print')),
                            updated_at INTEGER NOT NULL
                        )
                        """
                    )
                    self._fail(failpoint, "after_create")      # <-- INJECTED FAILURE POINT
                    # ... INSERT INTO lanes_migrated SELECT <exprs> FROM lanes ...
                    # ... DROP TABLE lanes; ALTER TABLE lanes_migrated RENAME TO lanes ...
                except BaseException:
                    connection.rollback()
                    raise
                else:
                    connection.commit()
            finally:
                connection.close()

    # ========================================================================
    # PATTERN B — THE BEFORE INSERT TRIGGER. This is S6's mechanism verbatim:
    # a `RAISE(ABORT, ...)` that makes an illegal row impossible to write, at
    # write time, from any caller in any language.
    #
    # S6: "SQLite BEFORE INSERT trigger on `items` raising on
    #      interrogative-source + weight='hard'".
    # ========================================================================
    ONE_OPEN_PULL_PER_SOURCE_REF = "one_open_pull_per_source_ref"

    def _migrate_source_tasks_pull_uniqueness(self, *, failpoint=None):
        """... SQLite evaluates a trigger's `RAISE(ABORT, ...)` inside the
        INSERT itself, so a second writer's transaction still fails exactly
        as a unique-index violation would, and `sqlite3.IntegrityError` is
        exactly what Python's `sqlite3` module raises for it (verified
        directly) -- callers do not need to know or care which mechanism
        caught it.

        [THE PRE-EXISTING-VIOLATION PROBLEM, and it applies squarely to S6:]
        an existing ledger can carry real pre-#169 duplicates ... Creating the
        trigger over such a ledger would SUCCEED (a trigger only fires on
        FUTURE inserts, it does not scan existing rows the way
        `CREATE UNIQUE INDEX` does) -- which would silently leave the
        pre-existing duplicate in place forever while looking, to a fresh
        caller, exactly like a clean ledger the guarantee already covers. So
        this checks for that duplicate BY HAND, joined the same way the
        trigger itself will, BEFORE ever creating the trigger.

        Decision, argued once here: on finding such a duplicate, this DOES NOT
        pick a winner and silently cancel the loser -- that is exactly the
        silent data loss the brief forbids ("failing to migrate is better than
        silently dropping a row"). Instead this raises loudly, naming every
        conflicting id, and creates no trigger -- `Ledger.__init__` propagates
        the failure, so EVERY ledger operation refuses until a human
        reconciles by hand and reopens the ledger. Blunt, but an unusable
        ledger until fixed beats a ledger that quietly drops the guarantee.
        """
        with self._locked():
            with contextlib.closing(self._connect()) as probe:
                existing = probe.execute(
                    "SELECT 1 FROM sqlite_master WHERE type='trigger' AND name=?",
                    (self.ONE_OPEN_PULL_PER_SOURCE_REF,),
                ).fetchone()
                if existing is not None:
                    return                                     # IDEMPOTENT

                # --- THE PRE-FLIGHT SCAN. S6's equivalent: count the existing
                # hard-from-interrogative `items` rows with the PINNED regex
                # before creating the trigger, and PUBLISH that count. The
                # three seats got 209 / 305 / 581 precisely because the
                # classifier differed; a trigger whose regex is unpinned
                # re-creates the defect it exists to close.
                dupes = probe.execute(
                    """
                    SELECT source_tasks.source_ref AS source_ref,
                           GROUP_CONCAT(source_tasks.id) AS ids,
                           COUNT(*) AS n
                    FROM source_tasks
                    JOIN tasks ON tasks.id = source_tasks.id
                    WHERE source_tasks.source_kind = 'pull'
                      AND tasks.status NOT IN ('complete','failed','cancelled')
                    GROUP BY source_tasks.source_ref
                    HAVING COUNT(*) > 1
                    """
                ).fetchall()
            if dupes:
                detail = "; ".join(f"PR #{row['source_ref']}: {row['ids']}" for row in dupes)
                raise RuntimeError(
                    f"cannot create {self.ONE_OPEN_PULL_PER_SOURCE_REF}: pre-existing duplicate open "
                    f"pull-kind source_tasks rows for the same PR ({detail}) -- resolve by hand "
                    "(cli.py record-completion, or cli.py cancel-open-task --lane <lane>, on whichever "
                    "lane is not actually still working the PR) and reopen the ledger; refusing to "
                    "silently pick a winner or drop a row"
                )
                # ^^ A REFUSAL THAT NAMES ITS ACTUATOR — two exact commands.

            connection = self._connect(foreign_keys=False)
            try:
                connection.execute("BEGIN IMMEDIATE")
                try:
                    self._fail(failpoint, "before_pull_trigger")
                    connection.execute(
                        f"""
                        CREATE TRIGGER IF NOT EXISTS {self.ONE_OPEN_PULL_PER_SOURCE_REF}
                        BEFORE INSERT ON source_tasks
                        WHEN NEW.source_kind = 'pull' AND EXISTS (
                            SELECT 1 FROM source_tasks
                            JOIN tasks ON tasks.id = source_tasks.id
                            WHERE source_tasks.source_kind = 'pull'
                              AND source_tasks.source_ref = NEW.source_ref
                              AND source_tasks.id != NEW.id
                              AND tasks.status NOT IN ('complete','failed','cancelled')
                        )
                        BEGIN
                            SELECT RAISE(ABORT, 'UNIQUE constraint failed: source_tasks.source_ref');
                        END
                        """
                    )
                    self._fail(failpoint, "after_pull_trigger")
                except BaseException:
                    connection.rollback()
                    raise
                else:
                    connection.commit()
            finally:
                connection.close()

    # ------------------------------------------------------------------------
    # `id != NEW.id` in the trigger's own EXISTS clause is load-bearing:
    # `_reconstruct_task_tx`'s INSERT is an `ON CONFLICT(id) DO UPDATE` upsert,
    # and re-registering the SAME id (a legitimate retry) is NOT a second
    # dispatcher -- verified directly that without the exclusion, SQLite's
    # BEFORE INSERT trigger fires on the initial insert attempt even when the
    # row will end up UPDATEd in place.
    #
    # S6's analogue: an UPDATE that re-weights an existing item must not trip
    # a trigger written for INSERT, and a legitimate `kind='question'` hard row
    # is HONESTLY LABELLED and must pass. All three seats agree the defect is
    # the `directive` + `parameter` subset only.
    # ------------------------------------------------------------------------


# ============================================================================
# READ-ACCESS CONSTRAINT — absolute, and NOT settled by assumption.
# ============================================================================
# Open the live ledger read-only: `file:PATH?mode=ro`.
# Two seats hit DIFFERENT journal modes on the SAME file:
#   * seat-raw-2 needed `&immutable=1` (verified journal_mode=delete, no WAL
#     sidecars, `integrity_check` ok first);
#   * seat-raw-3 found it in WAL mode with sidecars appearing and disappearing,
#     and worked from a `cp` of the main file instead.
# A read-only open cannot create the `-shm` it needs. DETERMINE THE MODE BEFORE
# CHOOSING THE ACCESS METHOD; never assume, and never carry one seat's recipe
# forward as though it were a property of the file.
#
# ============================================================================
# MUTATION VERIFICATION for a trigger — the acceptance, stated as a procedure
# ============================================================================
# 1. Attempt the synthetic illegal INSERT. Assert `sqlite3.IntegrityError`.
#    (POSITIVE CONTROL: this proves the trigger can fire at all. Without it,
#    "zero bad rows" is indistinguishable from "trigger never installed".)
# 2. Attempt the legitimate neighbouring INSERT — an honestly-labelled
#    `kind='question'` hard row, and an idempotent re-registration. Assert both
#    SUCCEED. A guard that blocks everything is not a guard.
# 3. Drop the trigger, re-run step 1, assert it now SUCCEEDS. Commit that
#    transcript. This is the "revert -> goes red" evidence inferred
#    requirement #1 demands, and it is the step the sibling repo skipped for
#    five and a half months.
