# Codebase Patterns: estate_remediation

**Phase 2A of /generate-prp.** Produced by `prp-gen-codebase-researcher`, autonomously.
**Repo root**: `/Users/jon/source/repos/Personal/agent-supervisor/.worktrees/plan/audit-remediation`
**Input**: `prps/estate_remediation/planning/feature-analysis.md`
**Archon**: NOT AVAILABLE. No Archon call was attempted. Every pattern below is repo-local or
machine-local, with `file:line`. Where I could not verify something, it says so.

## Overview

The estate already has a strong, self-consistent house style for every category this remediation
touches: bash actuators with a documented header, an env-override block, `set -uo pipefail`, a
`log()` that stamps UTC, an atomic `mkdir` lock with a reclaim path, and a refusal that names its
reason. Tests are stub-driven bash suites with a hand-rolled `ok`/`bad`/`check` harness, wired into
`unittest` by one globbing wrapper. The two things the remediation needs that have **no local
precedent at all** are (a) a `Stop`/`SessionStart` hook, and (b) a `.sql` migration — and for both,
this file names the nearest real thing to copy instead.

Two live defects were found while sweeping, both relevant to acceptance criteria. They are in
"Anti-Patterns" and "Instrument traps".

---

## Architectural Patterns

### Pattern 1: The bash actuator — header, env block, `set -uo pipefail`, `log()`
**Source**: `scripts/supervisor/poller-recover.sh:1-148` (the best single exemplar)
**Relevance**: 10/10 — every new script in this PRP (session reaper, `run-from-main.sh`, launchd
exit sweep, `reap.sh`, daily auditor) is this shape.

**Measured convention**, counted across `scripts/supervisor/*.sh`:

- `set -uo pipefail` — **38 files**. `set -euo pipefail` — **1 file** (`bootstrap-session.sh:63`).
  **The house default is `-uo`, not `-euo`.** Deliberate: these scripts want to keep going and
  *report*, not abort on the first non-zero. A new actuator should use `set -uo pipefail` unless it
  has a stated reason to abort.
- Header comment block, 20-70 lines, before any code, structured as: what it does → **WHY / THE GAP
  THIS CLOSES** (naming the issue number) → the failure mode it prevents → `Usage:` → `Env
  overrides:` → an explicit exit-code contract. `state.sh:1-65` is the fullest example; its exit
  contract is `Exit 0 / Exit 1 / Exit 2` with the meaning of each spelled out (`state.sh:61-65`).
- Path/env resolution, always in this order:
  ```bash
  HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"        # poller-recover.sh:122
  STATE="${SUPERVISOR_STATE:-$HOME/.local/state/agent-dotfiles-supervisor}"  # :129
  LIVE="${SUPERVISOR_LIVE:-$STATE/live}"                       # :130
  LOG="${POLLER_RECOVER_LOG:-$STATE/poller-recover.log}"       # :138
  ```
  `SUPERVISOR_STATE` with that exact default appears in **13 scripts** (`digest.sh:40`,
  `heartbeat.sh:33`, `director-loop.sh:40`, `notify.sh:51`, `inbox.sh:64`, `advance-live.sh:142`,
  `inbox-poll.sh:207`, `closed-report.sh:47`, `poller-leak-cleanup.sh:53`, `director-inbox.sh:96`,
  and others). **Never hardcode the state dir; never invent a second variable name for it.**
- Sourcing a sibling uses a shellcheck directive:
  ```bash
  # shellcheck source=./session-defaults.sh
  . "$HERE/session-defaults.sh"          # poller-recover.sh:123-126
  ```

**How to adapt**: the session reaper is `poller-recover.sh` with the target changed from a *window*
to a *session*. Copy its header discipline verbatim — including the "THE ONE PLACE A RACE COULD
STILL HAPPEN" paragraph, because the reaper has the identical `tmux new-session` non-CAS race that
`poller-recover.sh:38-48` documents for `new-window`.

---

### Pattern 2: `log()` — UTC ISO-8601, prefixed by script name
**Source**: 12 definitions; two shapes.

Shape A — stdout only, name-prefixed (for scripts whose stdout a launchd `StandardOutPath`
captures):
```bash
log() { printf '%s heartbeat: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }
```
`heartbeat.sh:56`; identical at `director-loop.sh:50`, `quota-watch.sh:111`,
`weekly-watch.sh:55`, `closed-report.sh:74`, `acceptance.sh:85`.

Shape B — file + stdout via `tee`, so a *caller* capturing output folds the same line into its own
log without a second differently-worded message:
```bash
log() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG" 2>/dev/null
}
```
`poller-recover.sh:144-147`. `advance-live.sh:160` is the file-only variant, paired with
`fail() { log "FAIL: $*"; echo "advance-live: $*" >&2; exit 1; }` at `:161`.

**Timestamp format is `%Y-%m-%dT%H:%M:%SZ` under `date -u`, everywhere, with no exceptions found.**
`director-inbox.sh:101` factors it as `now()`. `watchdog.sh:487` uses a precomputed `$iso`.

**When to use**: Shape B for anything watchdog.sh will invoke (the reaper, the launchd sweep);
Shape A for anything launchd invokes directly.

---

### Pattern 3: The atomic `mkdir` lock with a reclaim path
**Source**: `scripts/supervisor/poller-recover.sh:171-200`; second instance `inbox-poll.sh:247-255`.
**Relevance**: 10/10 for the session reaper (A1) — two ticks racing to create one session is exactly
the failure this idiom exists to prevent.

```bash
acquire_lock() {
  if mkdir "$LOCK" 2>/dev/null; then
    printf '%s' "$$" >"$LOCK/pid" 2>/dev/null
    date +%s >"$LOCK/started" 2>/dev/null
    return 0
  fi
  holder_pid=$(cat "$LOCK/pid" 2>/dev/null); started=$(cat "$LOCK/started" 2>/dev/null)
  [ -n "$holder_pid" ] && kill -0 "$holder_pid" 2>/dev/null && return 1   # live holder
  [ -z "$started" ] && return 1                                           # mid-acquisition
  age=$(( $(date +%s) - started ))
  [ "$age" -lt "$LOCK_MAX_AGE" ] && return 1
  log "RECLAIMING stale lock $LOCK (holder pid ${holder_pid:-unknown}, age ${age}s) -- its EXIT trap never ran"
  rm -rf "$LOCK" 2>/dev/null
  ...
}
```

**Why `mkdir` and not `flock`**: `poller-recover.sh:43-48` states it — macOS ships no `flock(1)`.
Where a *file-range* lock is genuinely needed the estate drops into Python's `fcntl.flock`
(`director-inbox.sh:115-133`, `:295-302`). **Do not introduce a third mechanism.**

**The load-bearing half is the reclaim, not the acquire.** `poller-recover.sh:50-61` argues it at
length: an `EXIT` trap does not run on SIGKILL or a launchd hard-kill, so without reclaim a
crashed holder silences the recovery path *forever* while every tick logs a benign-looking line.
That is precisely the estate-wide defect this PRP exists to remove; a reaper without a reclaim
path re-creates it one layer down. Conventions: `LOCK="${X_LOCK:-$STATE/.x.lock}"`,
`LOCK_MAX_AGE="${X_LOCK_MAX_AGE:-60}"`.

---

### Pattern 4: Argument parsing, validation-before-action, and `usage()` from the header
**Source**: `scripts/supervisor/bootstrap-session.sh:96-155`
**Relevance**: 10/10 — A6 (splitting `restore.sh --session` into `--only-session`) is literally an
edit to this pattern.

```bash
usage() { sed -n '/^# Usage:/,/^$/p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//' >&2; }

while [ $# -gt 0 ]; do
  case "$1" in
    --session)   SESSION="${2:?--session needs a value}"; shift 2 ;;
    --lanes)     LANES="${2:?--lanes needs a value}"; shift 2 ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)   usage; exit 0 ;;
    *) echo "bootstrap-session: unknown argument: $1" >&2; usage; exit 1 ;;
  esac
done
```

Three properties to carry forward:
1. **`usage()` re-reads the file's own header** — there is no second copy of the flag list to drift.
2. **`${2:?...}`** makes a valueless flag fail with a message, not consume the next flag.
3. **Every validation happens before any mutation.** `bootstrap-session.sh:114-155` rejects a
   non-numeric `--lanes`, a `--lanes` below 2, a missing `tmux`, an unresolvable agent command, and
   a session name containing `:` or `.` — all before the first `tmux` call. The `:`/`.` rejection
   (`:149-155`) documents a measured half-built-session bug from #137. **A6's `--only-session` must
   validate the same way, and its dry-run must exit before any `new-session`.**

`--dry-run` is a first-class flag, not a debug aid: `restore.sh:55,59,194` and
`bootstrap-session.sh:58`. `test_bootstrap_session.sh:82-86` asserts dry-run *created no session*,
which is the assertion shape A6 needs.

---

### Pattern 5: `refuse()` — a named, per-item, non-fatal refusal
**Source**: `scripts/supervisor/restore.sh:109` and its 11 call sites (`:123,135,139,143,151,174,178,187,202,232,241`)
**Relevance**: 10/10 — this is the shape seat 4's proposed 11th invariant ("a refusal must name what
acts instead") extends, and A6/A7 edit this exact function's neighbourhood.

Every refusal names the lane, the missing fact, and why guessing was rejected:
```
refuse "$lane" "no originating project directory recorded for task '$task' -- refusing to guess
                between '$repo' and elsewhere (pre-agent-supervisor#172 lane)"     # restore.sh:174
```
Note `restore.sh:166-174`: *"A missing value here is refused, never guessed as `$repo`."* That is
the house voice. New refusals should match it — and, per the proposed 11th invariant, add the clause
the existing 43 sites lack: **what does act instead.**

---

### Pattern 6: `report()` — atomic status file, one notify per episode
**Source**: `scripts/supervisor/watchdog.sh:491-540`
**Relevance**: 10/10 — A3, A4, A5, D7 are all edits inside this function or its callers.

- Writes to `$STATUS.$$` then `mv -f`, so no reader sees a half file (`:492`, `:524`).
- `mkdir -p "$(dirname "$STATUS")"` first — `:501-505` records that a missing state dir once made
  every write fail silently while the script still exited 0.
- Fixed key set: `checked: / state: / detail: / pane: / restarts: / code: / notify:`.
- **`:537-538` is the line A4 must change**: *"escalate is the only state a human needs told about;
  every other state stays silent"*. `no_session` is not `escalate`, which is why 106 ticks paged
  nobody.
- `:522-526` carries a bash trap worth reusing: an `if`, not `[ ... ] && printf`, as the **last**
  command of a group — a false test would make the group exit non-zero and skip the `&& mv`. Same
  family as the `!`-negated-pipeline trap; check any new group-redirect for it.

---

## Testing Patterns

### Discovery — `test_shell_suites.py`
**Source**: `tests/supervisor/test_shell_suites.py:22-23, 64-118`

```python
HERE = Path(__file__).resolve().parent
SUITES = sorted(HERE.glob("test_*.sh"))
```
`unittest discover -s tests` (`.github/workflows/validate.yml:30`) picks up this module; it runs
every `test_*.sh` as a subprocess and asserts `returncode == 0`. **A new `tests/supervisor/test_*.sh`
is enforced the moment it lands — no registration step.** 109 suites exist today.

Two details to preserve:
- `test_suites_are_discovered` (`:65-68`) asserts the glob is non-empty — *"A glob that silently
  matches nothing would make every assertion below vacuous."* **This is the estate's own
  positive-control idiom, in Python.** Copy it for every new "zero violations" assertion.
- `TIMEOUT = 300`, `start_new_session=True`, SIGTERM-to-the-process-group then a
  `GRACE_AFTER_TERM = 30` wait before SIGKILL (`:26-48, 73-104`). A suite that spawns tmux or a
  LaunchAgent gets its own trap a real chance to reap. **A reaper test that starts a real session
  must finish inside 300s and must clean up on TERM.**

### Suite shape — the hand-rolled harness
**Source**: `tests/supervisor/test_bootstrap_session.sh:15-60`, `test_protect_shared_checkout.sh:14-21`

```bash
set -uo pipefail
pass=0; fail=0
ok()   { echo "  ok   $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL $1 — $2"; fail=$((fail+1)); }
check(){ if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want '$2', got '$3'"; fi }
```
Variant with exit codes: `want_exit()` at `test_protect_shared_checkout.sh:21`. **No bats, no
shunit2 — do not add a test framework.** The suite exits non-zero iff `fail > 0`.

### tmux isolation — `TMUX_TMPDIR` + `assert_isolated_tmux`
**Source**: `scripts/supervisor/tmux-isolation.sh:3-16`; used at `test_bootstrap_session.sh:18-23,55`

```bash
assert_isolated_tmux() {
  [ -n "${TMUX:-}" ] && { echo "...refusing to target an attached server" >&2; return 1; }
  [ -z "${TMUX_TMPDIR:-}" ] && { echo "...TMUX_TMPDIR is required" >&2; return 1; }
  [ ! -d "$TMUX_TMPDIR" ] && { echo "...does not exist" >&2; return 1; }
}
```
The caller's full preamble:
```bash
S="bootstrap-test-$$"                                    # PID-scoped session name
RT="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-tmux.XXXXXX")"
unset TMUX; export TMUX_TMPDIR="$RT"
assert_isolated_tmux || exit 1
LEDGER_DIR="$(mktemp -d ...)"; export AGENT_SUPERVISOR_STATE_DIR="$LEDGER_DIR"   # :30-31
trap cleanup_all EXIT INT TERM                                                   # :60
[ ... ] || { echo "  SKIP no tmux on PATH"; exit 0; }                            # :62-64
```
`cleanup()` re-asserts isolation *before* killing (`:55`) — the guard runs again inside the trap, so
a trap firing after an env change cannot address the real server. **A12 (test isolation must cover
session naming) extends this file**: today it guards the socket, not the name. The name guard is the
`S="bootstrap-test-$$"` convention, which is currently a convention and not enforced.

`AGENT_SUPERVISOR_STATE_DIR` redirection (`:24-31`) is mandatory for anything writing the ledger —
its comment names the rule: do not mutate the live ledger.

### Mutation verification — the existing template
**Source**: `tests/supervisor/test_lanes.sh:710-830`; simpler form `test_session_defaults.sh:55,89,109`

The estate's mutation checks **run the mutant and assert it produces the wrong answer**, in the same
suite:
```bash
mutate_assign "$MUTHDIR/codex.sh" HARNESS_READY_RE "'NEVER_MATCHES_ANYTHING_XYZZY'" || mutation_rc=$?
...
echo "  ok   mutation confirmed: the pre-#250 anchor cannot see a tilde-abbreviated cwd"
```
`test_lanes.sh:18-22` records why the helper exists: mutation checks used to grep for the literal
they were breaking, coupling each check to exact source text. **The mutant is a copy in a temp dir,
never an edit to the tracked file.** `test_session_defaults.sh:55` phrases the assertion as
`"mutation-check: breaking the shared default is detected"`.

**This is the artifact the PRP's meta-criterion ("every gate mutation-verified, evidence committed")
should require: a `mutation-check:` case inside the same suite, not a paragraph in a PR body.**

---

## Notification Pattern

**Source**: `scripts/supervisor/watchdog_notify.py` (stdlib only), `scripts/supervisor/notify.sh`

**Three subscribers**, each a triple of pure functions plus one impure driver:

| Subscriber | classify | build message | decide | driver |
|---|---|---|---|---|
| poller restarts | `parse_status:58` / `parse_restarts:75` | `build_message:83` | `decide_notify:94` | `check_and_notify:195` |
| inbox-poll heartbeat | `classify_heartbeat:260` | `build_heartbeat_message:299` | `decide_notify_heartbeat:310` | `check_and_notify_heartbeat:363` |
| director inbox | `classify_director_inbox:415` | `build_director_inbox_message:457` | `decide_notify_director_inbox:468` | `check_and_notify_director_inbox:515` |

**Adding a subscriber = adding that quadruple.** The split is deliberate and stated at
`watchdog_notify.py:310-320`: the classifier returns a fact (`kind`, `age_seconds`); the
**threshold is a decision-time parameter**, never baked into the fact read off disk.

`NotifyDecision(should_notify, reason, next_episode_notified)` is the return type. Episode state is
one file (`_load_episode:135` / `_save_episode:151`) giving **one page per episode, not one per
tick**; a benign kind returns `next_episode_notified=False` so a recurrence pages again.

**End to end**: `watchdog.sh` `report()` (`:536+`) resolves the notifier from `$HERE` — explicitly
so a worktree exercises its own copy, not the shared checkout's — → `watchdog_notify.py` decides →
`send_via_notify_skill:608` → `notify.sh` → `curl` to Telegram (`notify.sh:144-149`, exit 0 on
success), iMessage fallback (`:177`), exit 1 if neither. Credentials come from
`ENVFILE="${NOTIFY_ENV:-$STATE/notify.env}"` (`notify.sh:73`), **never from the plist** — its
comment at `:72` says why, and `com.jonhill.supervisor-watchdog.plist` sets `NOTIFY_ENV` for exactly
this reason. `notify.sh:123-128` refuses rather than falling back to the production bot when QA
credentials are missing — the refusal shape D3 needs.

**D4's defect, confirmed at the line the analysis names**: `build_heartbeat_message:299-307`
hardcodes `"watchdog: inbox-poll heartbeat stale"` and `cat ~/.local/state/.../inbox-poll.status`
for **all** callers. The subsystem/file/threshold must become parameters of the builder, in the same
way `threshold_seconds` already is.

**D5's defect, confirmed**: `decide_notify_heartbeat:335-341`, `kind == "stopped"` →
`should_notify=False` with **no age term** anywhere in the branch.

---

## SQLite Migration Pattern

**There is no migrations directory and no `.sql` file. Verified** — `grep -n "_migrate"
scripts/supervisor/core.py` returns four methods, all called from `__init__`:

```python
self._migrate_lanes_table(failpoint=_migration_failpoint)                  # core.py:271
self._migrate_tasks_table(failpoint=_migration_failpoint)                  # :272
self._migrate_source_tasks_table(failpoint=_migration_failpoint)           # :273
self._migrate_source_tasks_pull_uniqueness(failpoint=_migration_failpoint) # :274
```
Bodies at `:702`, `:813`, `:915`, `:1013`. `_initialize` (the `CREATE TABLE IF NOT EXISTS` block) at
`:320`; the `sessions` table at `:536-540`. **There is no `PRAGMA user_version` and no version
table** — migrations are idempotent-by-construction (`PRAGMA table_info` probe first, e.g. `:741`,
`:841`), not sequenced. A new migration is a new `_migrate_*` method plus a line in `__init__`.

Three sub-patterns every new migration must carry:

1. **The `failpoint=` seam.** Every method takes it and calls `self._fail(failpoint, "<name>")` at
   each interesting point (`:1147`, `:1164`). That is how partial-migration crash safety is tested.
2. **Table rebuild for anything SQLite's `ALTER TABLE` cannot do**: `CREATE TABLE x_migrated (...)`
   → `INSERT INTO x_migrated SELECT ...` → `ALTER TABLE x_migrated RENAME TO x`
   (`:767, 791, 803`; same at `:858-896`, `:969-1001`). **The `prompts.provenance` column with a
   `CHECK` constraint needs this dance** — a `CHECK` cannot be added by `ALTER TABLE ADD COLUMN`
   retroactively in the way the feature analysis implies.
3. **Refuse rather than pick a winner when pre-existing data violates the new constraint.**
   `:1136-1144` probes for duplicates *before* creating the trigger and raises a `RuntimeError`
   naming the offending rows and the exact repair commands. **This is the template for S6**: if
   interrogative-sourced hard items already exist, the migration must refuse and name them, not
   silently create a trigger that only binds future inserts.

**The `BEFORE INSERT` trigger template — the one to copy for S6** (`core.py:1149-1163`):
```sql
CREATE TRIGGER IF NOT EXISTS one_open_pull_per_source_ref
BEFORE INSERT ON source_tasks
WHEN NEW.source_kind = 'pull' AND EXISTS (
    SELECT 1 FROM source_tasks JOIN tasks ON tasks.id = source_tasks.id
    WHERE source_tasks.source_kind = 'pull'
      AND source_tasks.source_ref = NEW.source_ref
      AND source_tasks.id != NEW.id
      AND tasks.status NOT IN ('complete','failed','cancelled')
)
BEGIN
    SELECT RAISE(ABORT, 'UNIQUE constraint failed: source_tasks.source_ref');
END
```
Wrapped in `connection = self._connect(foreign_keys=False)` → `BEGIN IMMEDIATE` → try/rollback/commit
→ `finally: close()` (`:1143-1171`). `core.py:1061-1065` records a subtlety the S6 trigger inherits:
the `RAISE(ABORT, ...)` **message text is load-bearing** — callers match on it, so it is phrased to
mimic the native constraint error. S6's message must be chosen deliberately and asserted in a test.

**Connection pragmas** (`core.py:279-281`): `foreign_keys` parameterised, `journal_mode = WAL`,
`synchronous = FULL`. That settles the feature analysis's open question in one direction — **the
writer sets WAL**; a reader opening `mode=ro` on a WAL database cannot create the `-shm` it needs.
Read access must account for that, and `immutable=1` is only safe if the writer is quiescent.

---

## CI Workflow Pattern

Three workflows; job names `test`, `gate`, `gate`.

| File | `name:` | job id | trigger |
|---|---|---|---|
| `.github/workflows/validate.yml` | `Validate` | `test:13` | `pull_request` + push to main |
| `.github/workflows/fixpass-evidence.yml` | `Fixpass evidence` | **`gate:34`** | `pull_request` + `issue_comment` |
| `.github/workflows/ui-evidence.yml` | `UI evidence` | **`gate:26`** | `pull_request` + `issue_comment` |

**E1's collision is confirmed at those two lines.** A new gate must NOT be named `gate`.

House shape for a gate workflow:
- A header comment naming the issue and the mechanism (`fixpass-evidence.yml:3-22`).
- `permissions: contents: read`, `pull-requests: read` — least privilege, explicit.
- Two triggers, with the `if:` guard `github.event_name == 'pull_request' || github.event.issue.pull_request != null`
  (`fixpass-evidence.yml:39`, `ui-evidence.yml:30`) so `issue_comment` on a plain issue is skipped.
- `actions/checkout@v5`, `actions/setup-python@v6` with `python-version: "3.12"`.
- **The assertion is delegated to a tracked, separately-tested script** — never inlined:
  `python3 scripts/supervisor/fixpass_evidence_gate.py ...` (`:51`),
  `bash scripts/supervisor/ui-evidence-gate.sh "$PR"` (`ui-evidence.yml:42`). Each has its own suite
  (`tests/supervisor/test_fixpass_evidence_gate.py`, `test_ui_evidence_gate.sh`) with `gh` stubbed
  and no network. **New gates (S7, S8, S9, D1, S10, E1's uniqueness lint) follow this: the workflow
  is four lines, the logic and its tests are in the repo.**
- Config is env, not hardcoded: `UI_EVIDENCE_PATH_RE` (`ui-evidence.yml:39`).
- `timeout-minutes: 30` on `validate.yml:22`, with the measurement that justified it in the comment
  (`:15-21`). **Set a timeout on every new job.**

### The `!`-negated-pipeline trap — checked here, and the result is a negative

I grepped `.github/workflows/*.yml` for a leading `!` and for `| !`. **No matches.** I also grepped
`scripts/supervisor/*.sh` for a line beginning `! `. **No matches.**

**Positive control**: the same grep run against the sibling repo's known-bad construct is not
available from this tree, so I confirmed the instrument differently — the grep pattern `^\s*!` does
match when tested against a synthetic line, and my workflow greps *did* return hits for other
patterns in the same files (`gate:`, `permissions:`), so the files were read.

**Conclusion**: this repo does not currently have the Hill90-shaped dead guard, **because it has no
inline shell assertions in CI at all** — every check is a delegated script whose exit code
propagates directly. That is the structural reason it is immune, and it is the reason to keep new
gates in delegated scripts rather than inline `run:` blocks. If a new gate is written inline, the
trap becomes reachable.

**A closely related shape does exist and is worth flagging**: `watchdog.sh:522-526` documents a group
whose *last command* being a false test would skip the following `&& mv`. Same family (a construct
whose failure does not propagate as expected); already fixed there, but it is the pattern to grep
for in review.

---

## launchd Pattern

**One plist is tracked**: `launchd/com.jonhill.director-loop.plist` (41 lines). **Six are live** in
`~/Library/LaunchAgents/`. Structure, from the tracked file:

```xml
<key>Label</key>            <string>com.jonhill.director-loop</string>
<!-- header comment: why this job exists, why this cadence, issue number -->
<key>ProgramArguments</key> <array><string>/bin/bash</string><string>/abs/path/script.sh</string></array>
<key>StartInterval</key>    <integer>900</integer>
<key>RunAtLoad</key>        <false/>
<key>ProcessType</key>      <string>Background</string>
<key>EnvironmentVariables</key> <dict>
  <key>PATH</key> <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/Users/jon/.local/bin</string>
  <key>HOME</key> <string>/Users/jon</string>
</dict>
<key>StandardOutPath</key>  <string>/Users/jon/.local/state/agent-dotfiles-supervisor/<job>.log</string>
<key>StandardErrorPath</key><string>… same file …</string>
```

**That `PATH` is the exact string `poller-recover.sh:157-161` names as the cause of the `lsof`
blindness** — `/usr/sbin` is absent. Any new job's script must resolve absolute paths itself.

**A8, measured live just now** (`grep -A3 ProgramArguments` over all six):

| plist | `ProgramArguments[0..1]` | StartInterval | RunAtLoad |
|---|---|---|---|
| `supervisor-watchdog` | `$SUPERVISOR_LIVE/scripts/supervisor/watchdog.sh` ✅ **the only one on live/** | 180 | true |
| `director-loop` | `/bin/bash` + `~/source/repos/Personal/agent-supervisor/scripts/supervisor/director-loop.sh` ❌ shared checkout | 900 | false |
| `quota-watch` | `/bin/bash` + shared checkout ❌ | 300 | true |
| `supervisor-heartbeat` | `/bin/bash` + shared checkout ❌ | 900 | true |
| `weekly-watch` | `/bin/bash` + shared checkout ❌ | 1800 | false |
| `jon-report` | `/bin/bash -c` + **`~/.local/state/.../bin/closed-report.sh; …/bin/phase-report.sh`** ❌ | 1800 | false |

**Four on the shared checkout, one on `live/`, one executing code out of `~/.local/state/.../bin/`.**
The last is A8 *and* S5 in the same plist: `phase-report.sh` is invoked from the state directory,
which is exactly the "deliverables live in git" violation. `run-from-main.sh` must handle the
`bash -c "a; b"` form, which is not a single program path.

**`$SUPERVISOR_LIVE` is not referenced symbolically in any plist** — `supervisor-watchdog` hardcodes
the expanded path `/Users/jon/.local/state/agent-dotfiles-supervisor/live/...`. launchd does not
expand variables in `ProgramArguments`. A checker asserting "resolves under `$SUPERVISOR_LIVE`" must
compare against the expanded default.

### Instrument trap found while measuring this — **new, not in the audit**

**`plistlib.load()` fails on 5 of the 6 live plists.** Example:
```
xml.parsers.expat.ExpatError: not well-formed (invalid token): line 14, column 53
```
Cause: XML forbids `--` inside a comment, and the house style uses em-dash-as-`--` inside plist
comments — `com.jonhill.director-loop.plist` live copy line 14: *"…means THIS failed **--** a signal
worth having."*; `quota-watch` line 7: *"quota-watch.sh **--**once does one poll…"*. `launchctl`
accepts these; a strict XML parser does not.

**Consequence for A8's checker**: a Python `plistlib`-based sweep over `com.jonhill.*.plist` would
raise on five files. Written naively (try/except → skip), it reports **one** compliant plist and
**zero** violations — a false clean, and precisely the "instrument that cannot see the thing" class
the estate warns about. The checker must either use `plutil -convert xml1 -o -` / `defaults read`,
or treat a parse failure as a **failure**, never a skip. Positive control: `plistlib` parsed
`supervisor-watchdog` successfully, so the parser works — the five failures are real.

---

## Claude Code Hooks — what exists to mimic

**`~/.claude/settings.json` has no `hooks` key. Re-verified**: keys are
`alwaysThinkingEnabled, effortLevel, enabledPlugins, skipDangerousModePermissionPrompt, theme, tui,
voiceEnabled`.

**But hook implementations DO exist on this machine — the feature analysis's "no working example in
this estate to copy from" is too strong.** Six `.claude/settings.json` files carry a `hooks` key:

| File | Events present |
|---|---|
| `~/source/repos/Personal/agent-supervisor/.claude/settings.json` | `PreToolUse`/`Bash` |
| `~/source/repos/Personal/agent-dotfiles/.claude/settings.json` | `PreCompact`, `PostToolUse`/`Edit\|Write` |
| `~/source/repos/skills-research/vibes-v3/.claude/settings.json` | `PreCompact`, `PostToolUse`/`Edit\|Write`, `PostToolUse`/`Bash` |
| `~/source/repos/skills-research/vibes-v2/.claude/settings.json` | (has `hooks`; not enumerated) |
| `~/source/repos/skills-research/microsoft-skills/.claude/settings.json` | includes `Stop` / `SessionStart` / `UserPromptSubmit` |
| `~/source/repos/skills-research/Hill90/.claude/settings.json` | `PreCompact`, `PostToolUse`/`Edit\|Write`, `PreToolUse`/`Bash`, **`Stop`** |

**A real `Stop` hook exists**: `~/source/repos/skills-research/Hill90/scripts/hooks/stop-gate.sh`,
99 lines. Its contract is exactly what S1 needs:
```bash
set -euo pipefail
# Input: JSON via stdin with transcript_path
# Output: exit 2 (blocking) if required checks are missing, exit 0 otherwise
INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')
[[ -z "$TRANSCRIPT_PATH" ]] && { jq -n '{systemMessage: "stop-gate: no transcript path provided — skipping"}'; exit 0; }
...
exit 2   # line 96 — the blocking path
exit 0   # line 99
```
Note it **fails open** on every unreadable input (four separate `exit 0` paths, lines 15/21/26/32),
emitting a `{systemMessage: ...}` JSON object so the skip is *visible*. **S1 must decide
deliberately whether to fail open or closed** — the rule is "the agent may not go quiet", so a
fail-open Stop hook satisfies nothing when the transcript is unreadable. That is a design decision
the PRP owns, and `stop-gate.sh` is the counterexample to argue against, not just a template.

### The in-repo hook — `.claude/protect-shared-checkout.sh`
**Source**: `.claude/settings.json` + `.claude/protect-shared-checkout.sh` (51 lines)

```json
{"hooks":{"PreToolUse":[{"matcher":"Bash","hooks":[{"type":"command","command":".claude/protect-shared-checkout.sh"}]}]}}
```
Script shape: `set -uo pipefail` → env-overridable target (`SUPERVISOR_SHARED_CHECKOUT`, `:19`) →
`payload=$(cat 2>/dev/null || true)` → **parse with `python3 -c` inline, not `jq`** (`:22-24`;
note the two hook families differ here — agent-supervisor uses python3, Hill90 uses jq; **python3 is
the estate's stdlib-only rule**, so prefer it) → `[ -z "$cmd" ] && exit 0` (fail open on unparseable)
→ narrow the match with `grep -qE`, exiting 0 early for near-misses (`:28-30`) → a multi-line
`cat >&2 <<MSG` explaining the block **and naming the alternative** (`:39-50`) → `exit 2`.

The command message ends with the actuator: *"Use a worktree instead: `git worktree add …`"*. **That
is the 11th-invariant shape already in the estate.** S4's and S5's hooks must do the same.

### The hook's own test — the mimic target for all four new hooks
**Source**: `tests/supervisor/test_protect_shared_checkout.sh`

It asserts **two separable things**, and the first is the one that matters most:
1. **The wiring resolves.** It reads the command out of `settings.json` with python3 (`:26-31`),
   strips a `$CLAUDE_PROJECT_DIR/` prefix (`:35`), and asserts the file exists and is executable
   (`:36-41`). Its header (`:8-13`) records why: settings.json once pointed at
   `.claude/hooks/protect-shared-checkout.sh` while the script shipped at
   `.claude/protect-shared-checkout.sh`, and **Claude Code fails OPEN on a missing hook script**, so
   the guard silently did nothing.
2. **The behaviour**, by feeding synthetic JSON on stdin and asserting the exit code:
```bash
run_hook() {
  printf '{"tool_input":{"command":%s}}' "$(python3 -c 'import json,sys; print(json.dumps(sys.argv[1]))' "$1")" \
    | (cd "$D/shared" && "$HOOK")
}
out=$(run_hook "git checkout other-branch" 2>&1); rc=$?
want_exit "blocks 'git checkout <branch>' in the shared checkout" "$rc" 2 "$out"
```

**Every one of the four new hooks needs both halves.** The wiring half is non-negotiable given
fail-open: an unwired hook is indistinguishable from a compliant estate. And because the four hooks
land in `~/.claude/settings.json` — outside every repo — the wiring test must read *that* file, not
a repo copy, which is a genuinely new problem this estate has never solved.

---

## Naming Conventions

**Shell scripts**: `kebab-case.sh` in `scripts/supervisor/` — `poller-recover.sh`,
`bootstrap-session.sh`, `advance-live.sh`, `quota-watch-recover.sh`. **Python**: `snake_case.py`
in the same directory — `watchdog_notify.py`, `ci_gate.py`, `itemize_prompts.py`,
`fixpass_evidence_gate.py`. The two live side by side; the language decides the separator.

**Tests**: `tests/supervisor/test_<script_name_with_underscores>.{sh,py}`. A shell script's suite
converts hyphens to underscores — `poller-recover.sh` → `test_poller_recover.sh`. Feature-scoped
suites append the aspect: `test_watchdog_staleness.sh`, `test_watchdog_launchd_relaunch.sh`,
`test_quota_watch_blind_alarm.sh`, `test_dispatch_session_per_repo.sh`. **A new script named
`reap.sh` therefore needs `tests/supervisor/test_reap.sh`.**

**Shell functions**: `snake_case`, verb-first — `acquire_lock`, `real_path`, `assert_isolated_tmux`,
`session_state`, `run_hook`, `harness_index_for_name`, `lanes_session_or_default`.

**Python**: private helpers `_leading_underscore` (`_load_episode`, `_save_episode`, `_deliver`,
`_notifier_is_usable`, `_latest_per_name`, `_pgid_alive`); the pure/impure split is
`classify_*` / `build_*_message` / `decide_notify_*` / `check_and_notify_*`.

**Env vars**: `SCREAMING_SNAKE`, prefixed by owning subsystem, always with a default —
`SUPERVISOR_STATE`, `SUPERVISOR_LIVE`, `LANES_SESSION`, `POLLER_RECOVER_LOCK`,
`POLLER_RECOVER_LOCK_MAX_AGE`, `HEARTBEAT_STALE_AFTER`, `UI_EVIDENCE_PATH_RE`,
`AGENT_SUPERVISOR_STATE_DIR`, `NOTIFY_ENV`. A shared concept keeps **one** name across scripts —
`poller-recover.sh:107-112` states the rule: `LANES_POLLER_WINDOW` is reused rather than a second
name invented, "deliberately the ONE name so the two cannot drift."

**Migrations**: `_migrate_<table>_<aspect>` — `_migrate_source_tasks_pull_uniqueness`.
**Triggers**: `snake_case` describing the invariant, held in a class constant —
`ONE_OPEN_PULL_PER_SOURCE_REF = "one_open_pull_per_source_ref"` (`core.py:1011`).

**Issue references**: `agent-supervisor#NNN` / `agent-dotfiles#NNN`, inline in the comment that
explains the fix. Nearly every non-obvious line carries one. **Match this.**

---

## File Organization

Flat, by design. There is **no** `scripts/supervisor/hooks/`, `lib/`, or `migrations/` subdirectory
(the only subdirectories are `harness/`, `laneview/`, and `laneview-plugin-tmux`).

```
scripts/supervisor/            reaper, run-from-main.sh, launchd-sweep.sh, reap.sh, links comparator
                               — all flat, alongside the 80 existing files
.claude/                       protect-shared-checkout.sh (flat, NOT .claude/hooks/)
                               + the four new hook scripts, if repo-hosted
launchd/                       com.jonhill.*.plist — 1 tracked today, 6 live; the gap is S5
tests/supervisor/              test_<name>.sh / test_<name>.py — auto-discovered
tests/supervisor/lib/          reap-verified.sh — the only shared test helper
.github/workflows/             one file per gate; job name MUST be unique across all files
```

**Justification**: `test_protect_shared_checkout.sh:8-13` records that inventing a `hooks/`
subdirectory is exactly what broke the last hook. Keep hook scripts where `.claude/settings.json`
already points, or change both together and let that test prove it.

**Open question the PRP must decide**: the four new hooks register in `~/.claude/settings.json`
(user-global) but their *scripts* should be tracked in this repo. That means an absolute path in a
user-global file pointing into a repo checkout — which collides head-on with S2 ("nothing executes
from a ref that is not an ancestor of `origin/main`") and with A8's `live/` rule. **No existing
pattern resolves this**; `$CLAUDE_PROJECT_DIR` (used by agent-dotfiles and Hill90) is project-scoped
and does not exist for a user-global hook.

---

## Common Utilities to Leverage

1. **`scripts/supervisor/tmux-isolation.sh` → `assert_isolated_tmux`** (`:3`). Source it in every
   test and every script issuing a destructive tmux verb.
2. **`scripts/supervisor/session-defaults.sh` → `lanes_session_or_default`** — used at
   `poller-recover.sh:128` and `bootstrap-session.sh:68`. **This is A11's existing seam**: the
   304/168 literals should collapse into this function, which already exists and is already tested
   (`test_session_defaults.sh`, including two mutation checks at `:55` and `:109`).
3. **`scripts/supervisor/notify.sh`** — the only send path. `watchdog_notify.py:568` resolves it as
   `Path(__file__).resolve().parent / "notify.sh"`, and `:579 resolve_notify_script` is where
   `NOTIFY-PATH-STALE` (D3) originates. **Fix that resolver; do not build a channel.**
4. **`scripts/supervisor/cli.py`** with `--state-dir` / `AGENT_SUPERVISOR_STATE_DIR` — the ledger
   entry point. `bootstrap-session.sh` already calls `cli.py adopt-session` on every session it
   creates (`test_bootstrap_session.sh:24-29`), so **A2's registration seam already exists**.
5. **`scripts/supervisor/poller-window.sh`** — shared window-name constant, sourced by
   `poller-recover.sh:123-124`. The pattern for any new shared literal.
6. **`tests/supervisor/lib/reap-verified.sh`** — the verified-reap helper suites call from their
   traps.
7. **`scripts/supervisor/tmux_verb_guard.py`** + `test_tmux_verb_guard.py` — the existing enforcement
   of AGENTS.md invariant 4. **A12 extends this file**, rather than adding a new guard.

---

## Anti-Patterns to Avoid

### 1. A tested module with no caller
**Found in**: `acp_transport.py` (zero non-test importers), `poller-leak-cleanup.sh` (183 lines, 9
tests, zero callers). **The repo names this defect in its own test harness**:
`test_shell_suites.py:10-12` — *"That is the `acp_transport.py` shape: a tested mechanism with no
caller."* S9's CI gate is the fix.

### 2. Inlining an assertion in a `run:` block
Not present today (all three workflows delegate). Adding one re-opens the `!`-negated-pipeline trap
and removes the gate from `unittest discover`. **Write the logic as a script with its own suite.**

### 3. A vacuous glob / a check that cannot see a violation
`test_shell_suites.py:65-68` is the estate's guard against it. **The word "positive control" appears
nowhere in `tests/supervisor/*.sh` or `scripts/supervisor/*.sh`** — I grepped; zero matches. The
*technique* exists (the non-empty-glob assertion, the `mutation-check:` cases); the *vocabulary* does
not. The PRP should standardise the name so future greps find them.

### 4. Verifying by grepping for the text you just emitted
`heartbeat.sh:149` builds `MSG` containing the literal `` `esc to interrupt` ``; `:197` greps the
whole pane for `esc to interrupt`; `:200` is unreachable. The same file does it correctly at `:93`.

### 5. A refusal whose terminal action is a string
43 sites. `poller-recover.sh:155` — `exit 0` on a missing session — is the canonical one.

### 6. Deduplicating on a name
`ci_gate.py:_latest_per_name` (~`:100-115`) keys `latest_by_name[name]`, and two workflows both
declare `gate`. **The same class exists in the plists**: six `com.jonhill.*` labels are unique today,
but a sweep keyed on a script's basename would collide across `live/` and the shared checkout.

### 7. XML comments containing `--` in a plist
Live in five of six plists. See the launchd section — it turns a strict-parser checker into a silent
skip.

---

## Recommendations for PRP

1. **Follow `poller-recover.sh` end to end for the session reaper (A1/A2)** — header, `set -uo
   pipefail`, env block, `log()` shape B, `acquire_lock` with reclaim, verify-then-report. It is the
   same problem one level up the tmux object hierarchy, and its header already argues the race.
2. **Reuse `lanes_session_or_default` (`session-defaults.sh`) for A11**, and extend
   `test_session_defaults.sh`'s existing two mutation checks rather than writing a new suite.
3. **Reuse `cli.py adopt-session` for A2** — `bootstrap-session.sh` already calls it, so registration
   needs a backfill, not a new writer.
4. **Mirror `core.py:_migrate_source_tasks_pull_uniqueness` for every schema change**: `failpoint=`
   seam, `PRAGMA table_info` probe, pre-existing-violation refusal that names the rows, table-rebuild
   for the `CHECK` column, `BEGIN IMMEDIATE` + rollback.
5. **Adopt `test_protect_shared_checkout.sh`'s two-part shape for all four hooks** — assert the
   wiring resolves to an executable file *and* assert exit 2 on a synthetic violation. Fail-open is
   the default behaviour of the harness, so unwired == silently absent.
6. **Copy `stop-gate.sh` (`skills-research/Hill90/scripts/hooks/`) as the `Stop` structural template,
   and explicitly reject its fail-open posture** for S1.
7. **Every new gate is a delegated script + its own suite + a four-line workflow with a unique job
   name and a `timeout-minutes`.** Never inline.
8. **Standardise `mutation-check:` and add a `positive-control:` label**, both as literal test-name
   prefixes, so `grep -rn 'mutation-check:\|positive-control:' tests/` becomes the committed evidence
   the meta-criteria demand.
9. **Write the A8 plist checker against `plutil`, or treat a parse error as a failure.** `plistlib`
   silently cannot read five of six.

---

## Source References

### From Archon
None — Archon was not available. No call attempted.

### From Local Codebase
- `scripts/supervisor/poller-recover.sh:1-200` — the actuator template: header, env block, `log()`, `acquire_lock` with reclaim; `:155` is A3's defect; `:157-161` documents the macOS `lsof`/PATH trap.
- `scripts/supervisor/bootstrap-session.sh:63-155` — arg parsing, `usage()` from header, validation-before-mutation; the only `set -euo pipefail` in the tree.
- `scripts/supervisor/state.sh:61-65` — the explicit exit-code contract style.
- `scripts/supervisor/restore.sh:109` + 11 call sites — `refuse()`; `:194` the `--dry-run` gate.
- `scripts/supervisor/watchdog.sh:487-540` — `log()`, atomic `report()`, the `escalate`-only notify rule (A4) and the trailing-`if` group trap.
- `scripts/supervisor/watchdog_notify.py:58-566` — the three-subscriber quadruple; `:299` D4's hardcoded message; `:335-341` D5's unbounded `stopped` exemption; `:568-608` the notify-path resolver behind D3.
- `scripts/supervisor/notify.sh:73,123-128,144-177` — credentials from `NOTIFY_ENV`, refusal over fallback, Telegram→iMessage.
- `scripts/supervisor/core.py:271-274,320,536-540,702,813,915,1011-1171` — migration methods, `sessions` schema, the `BEFORE INSERT`/`RAISE(ABORT)` trigger template, the refuse-on-pre-existing-violation pattern; `:279-281` WAL + `synchronous=FULL`.
- `tests/supervisor/test_shell_suites.py:22-23,64-118` — glob discovery, the non-empty-glob positive control, process-group timeout handling.
- `tests/supervisor/test_bootstrap_session.sh:15-64,82-86` — tmux isolation preamble, `ok/bad/check`, scratch ledger, dry-run assertion.
- `scripts/supervisor/tmux-isolation.sh:3-16` — `assert_isolated_tmux`.
- `tests/supervisor/test_lanes.sh:710-830`, `test_session_defaults.sh:55,109` — mutation-check template.
- `tests/supervisor/test_protect_shared_checkout.sh:8-13,26-60` — hook wiring test + stdin-JSON behaviour test; the fail-open finding.
- `.claude/settings.json` + `.claude/protect-shared-checkout.sh:18-51` — the estate's only in-repo hook.
- `.github/workflows/validate.yml:13,22,30`; `fixpass-evidence.yml:23-51`; `ui-evidence.yml:15-42` — job names (`test`, `gate`, `gate` — E1 confirmed), triggers, delegation, timeout.
- `launchd/com.jonhill.director-loop.plist:1-41` — the tracked plist; `~/Library/LaunchAgents/com.jonhill.*.plist` — the six live ones, measured in the table above.
- `~/source/repos/skills-research/Hill90/scripts/hooks/stop-gate.sh:1-99` — the only `Stop` hook found on this machine.
- `~/source/repos/Personal/agent-dotfiles/.claude/settings.json`, `.claude/hooks/{backup-transcript,check-frontmatter}.sh` — `$CLAUDE_PROJECT_DIR`, `timeout`, `statusMessage` fields.

### Could not check
- `docs/plans/prp/estate-remediation/execution/execution-plan.md` unit-by-unit against the real tree — out of scope for one pass; the feature analysis already found one dead reference (`ingest_prompts.py`) and warns there are more.
- `.claude/patterns/*.md` — confirmed absent from this repo and `~/.claude/`, consistent with the feature analysis.
- Whether the sibling Hill90 `!`-negated construct has an exact analogue outside `.github/workflows/` and `scripts/supervisor/*.sh` (e.g. in `~/.local/state/.../bin/`, which is untracked and unread here).

---

## Next Steps for Assembler

- **Current Codebase Tree**: use the flat `scripts/supervisor/` layout above; state explicitly that
  there is no `migrations/`, no `hooks/` subdirectory, and no `lib/` — inventing one has already
  broken a hook once.
- **Implementation Blueprint**: lift Patterns 1, 3, 4 verbatim for the new bash actuators; the
  trigger SQL and `_migrate_*` skeleton for S6/schema; the four-line workflow + delegated script for
  every CI gate; the two-part hook test for all four hooks.
- **Known Gotchas**: the seven anti-patterns, plus the two new instrument traps — `plistlib` on
  `--`-containing plist comments, and `jon-report`'s `bash -c "a; b"` `ProgramArguments` shape that a
  naive `run-from-main.sh` wrapper will not handle.
- **Desired Codebase Tree**: keep it flat; name every new test file by the
  `test_<script>_<aspect>.sh` convention so `test_shell_suites.py` picks it up with no registration.
