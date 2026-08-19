# Known Gotchas: estate_remediation

**Phase 3 of /generate-prp.** Produced by `prp-gen-gotcha-detective`, autonomously.
**Repo root**: `/Users/jon/source/repos/Personal/agent-supervisor/.worktrees/plan/audit-remediation`
**Archon**: NOT AVAILABLE. No Archon call attempted. Every finding below is either a measurement
taken on this machine on 2026-08-19, a `file:line` in this tree, or a quoted upstream doc already
fetched by Phase 2B. Where I could not verify, it says **Could not check**.

## Overview

The prior phases found real traps and got most of them right. This phase **corrects two of their
prescriptions with measurement**, and adds **nine gotchas nobody had found** — the largest of which
is that the PRP's own absolute ledger-access constraint (`file:PATH?mode=ro`) **cannot open the live
ledger at all**, and fails in a way that makes every "zero violations" gate pass green.

Three classes dominate:

1. **The instrument fails silently and the gate reads that as clean.** Measured four independent
   instances, two of them compounding into a single green-while-broken gate.
2. **The prescribed actuator does not work in the environment it will run in.** `tmux new-session
   -A` — the reaper body Phase 2B prescribes — **fails with exit 1 from any non-terminal context
   whenever the session already exists**, i.e. on every healthy tick of a launchd job.
3. **The remediation's own guards can take the estate down.** S2's branch guard, installed before
   A8, stops every scheduled job in the estate including the reaper that is the whole point.

---

## Corrections to the prior phases

| Prior claim | Status | Correction |
|---|---|---|
| Phase 2B: reaper body is `tmux new-session -A -d -s "$s"` | **WRONG, measured** | Fails `rc=1` (`open terminal failed: not a terminal`) whenever the session exists. `-D` does not help. Use `has-session -t "=$s" \|\| new-session -d -s "$s"`. See Critical 2. |
| Phase 2B: ledger read is `sqlite3 "file:$L?mode=ro"` | **WRONG, measured on the live ledger** | `rc=14`, empty output. The live ledger is WAL with no sidecars right now. See Critical 1. |
| Phase 2B: "`.backup` is the correct snapshot verb" | **Half wrong** | `.backup` from a `mode=ro` handle fails (`rc=1`) in exactly the state the ledger is in now. It only worked in my test while a writer was live. See Critical 1. |
| Phase 1/2C: the reaper calls `bootstrap-session.sh` | **Incomplete** | `bootstrap-session.sh:244-251` **refuses (exit 1)** when the session exists without `--add-lanes`, and `--add-lanes` can never create the supervisor window. See Critical 3. |
| Phase 2B: `immutable=1` is "actively unsafe" under a writer | **Confirmed, with the number** | Measured: returned `1` where the truth was `2`. Silently missed a committed row. |
| Council counts (297/166 literals, 770 branches) | **Drifted again** | Measured today: **414** non-main branches, **202** worktrees, **416** socket entries. The audit said 770/346/416. Do not hardcode any of them. |

---

## Critical Gotchas

### 1. `file:$LEDGER?mode=ro` cannot open the live ledger — and the failure reads as "zero rows"

**Severity**: Critical · **Category**: Data-blind instrument / false-green gate
**Affects**: every ledger read in this PRP — the session reaper (A1/A2), the events-consumed gate
(D1), links-non-empty (S8), the corpus verbatim checker (S7), every auditor.
**Source**: measured on this machine, 2026-08-19; https://sqlite.org/uri.html

**What it is**. INITIAL.md makes `file:PATH?mode=ro` an absolute constraint. Measured against the
real file:

```
$ python3 -c "... read header bytes 18/19 of ~/.local/state/agent-dotfiles-supervisor/ledger.sqlite3"
magic: SQLite format 3
write_version: 2 read_version: 2 -> WAL

$ ls ~/.local/state/agent-dotfiles-supervisor/ | grep -E 'ledger.sqlite3-(wal|shm)$'
NONE (checkpointed state)

$ sqlite3 "file:$L?mode=ro" 'select count(*) from sessions;'
Error: in prepare, unable to open database file (14)
rc=14
```

A read-only connection to a WAL database must create the `-shm` shared-memory file and **cannot**.
When a writer happens to be live the sidecars exist and the same command works. *That* is why
seat-raw-2 and seat-raw-3 disagreed about the journal mode — they were not looking at different
files, they were looking at the same file in two different sidecar states.

**Why it is critical**: it is silent. Combined with gotcha 2 below, a gate reads `""`, compares it
numerically, and exits **0**.

**Three more measured facts the fix depends on**:

```
file:$DB?mode=ro                 -> Error (14)      # no sidecars
file:$DB?mode=ro&immutable=1     -> 2               # works
file:$DB?mode=ro&nolock=1        -> Error (14)      # does NOT help
sqlite3 "file:$DB?mode=ro" ".backup snap"  -> Error: unable to open database file  rc=1
python3 sqlite3.connect('file:...?mode=ro', uri=True)  -> works, AND CREATES -wal/-shm
```

Two consequences nobody has recorded:
- **Python's `mode=ro` is not read-only at the filesystem level.** It creates `ledger.sqlite3-shm`
  and `-wal` in the state directory as a side effect. Verified: the CLI failed, Python then
  succeeded, and the sidecars appeared; the CLI then succeeded. In a directory the process cannot
  write, Python fails too (measured `rc=14` under `chmod a-w`).
- **`immutable=1` is a silent liar under a live writer.** Measured: `immutable=1` returned `1` when
  the committed truth was `2`. Never use it while any supervisor process may be writing.

**How to detect it**: run any ledger read as a bash gate would, with stderr suppressed, and print the
captured value in brackets. If it is `[]`, the instrument is blind.

**How to avoid/fix** — one shared helper, used by every reader in this PRP:

```bash
# ❌ WRONG — fails rc=14 right now, empty output, gate goes green
count=$(sqlite3 "file:$LEDGER?mode=ro" 'select count(*) from events where notified_at is null;' 2>/dev/null)

# ✅ RIGHT — scripts/supervisor/ledger-snapshot.sh
# Copies main + sidecars together (a bare `cp` of the main file alone is a torn read),
# then opens the COPY read-write, which is allowed to make its own -shm.
snapshot_ledger() {
  local src="${1:?ledger path}" dst
  dst="$(mktemp -d "${TMPDIR:-/tmp}/ledger-snap.XXXXXX")/ledger.sqlite3"
  cp -p "$src" "$dst" || return 3
  for suf in -wal -shm; do [ -e "$src$suf" ] && { cp -p "$src$suf" "$dst$suf" || return 3; }; done
  # Prove the copy opens AND that the table we are about to trust exists.
  sqlite3 "$dst" 'select 1 from sqlite_master limit 1;' >/dev/null 2>&1 || return 3
  printf '%s\n' "$dst"
}
SNAP="$(snapshot_ledger "$LEDGER")" || { log "REFUSED: cannot snapshot ledger -- not reporting a count I could not read"; exit 3; }
```

Measured green: copying `db` + `-wal` + `-shm` to a temp dir and opening the copy returned the
correct row count (`3`) while a writer was live.

**Rules this creates for the PRP**:
- **No ledger reader may report a number it did not prove it could read.** Exit non-zero and page;
  never emit `0`.
- The snapshot is also the answer to "the ledger is READ ONLY": the *snapshot* is what the corpus
  work analyses, so the read path can never mutate the original.
- **Positive control, mandatory**: point the checker at a deliberately unreadable path and assert it
  exits non-zero. Without it, the checker's "0 violations" is untested.

---

### 2. A gate that compares an empty string to a number exits 0 — measured

**Severity**: Critical · **Category**: False-green gate
**Affects**: every CI gate and auditor in Group B/D (S5, S7, S8, S9, S10, D1, E1).

```
$ bash -c 'set -uo pipefail; n=""; if [ "$n" -gt 0 ]; then echo FAILGATE; exit 1; fi; echo GREEN; exit 0'
bash: line 1: [: : integer expected
GREEN
gate exit=0
```

The `[` builtin errors (exit 2), which is not "true", so the `if` body is skipped and the script
falls through to success. **`set -e` does not save you** — the Bash manual's `-e` exemption covers
"part of the test in an `if` statement" verbatim, the same clause as the `!` trap that killed the
sibling repo's guard for 5½ months.

This composes with gotcha 1 into the estate's worst possible outcome: **the database cannot be
opened, so the count is empty, so the gate reports the system clean.**

**How to avoid/fix**:

```bash
# ❌ WRONG
n=$(query 2>/dev/null); if [ "$n" -gt 0 ]; then exit 1; fi

# ✅ RIGHT — validate the instrument before believing the verdict
n=$(query) || { echo "::error::query failed -- refusing to report a count"; exit 3; }
case "$n" in ''|*[!0-9]*) echo "::error::non-numeric result [$n] -- instrument blind"; exit 3 ;; esac
if [ "$n" -gt 0 ]; then echo "::error::$n violations"; exit 1; fi
echo "0 violations (instrument verified readable)"
```

**Three distinct exit codes, deliberately**: `0` clean, `1` violations found, `3` could not measure.
A gate with only 0/1 cannot express "I was blind", which is how this estate got here.

---

### 3. `tmux new-session -A` fails from a headless job whenever the session exists

**Severity**: Critical · **Category**: The actuator does not work
**Affects**: A1 — the one actuator that has never existed.
**Source**: measured, tmux 3.5, isolated `TMUX_TMPDIR` + `-L` socket.

Phase 2B prescribes `tmux new-session -A -d -s "$SESSION"` as the idempotent reaper body. Measured:

```
new-session -d -s prod                       rc=0   (created)
new-session -A -d  -s prod   (exists)        rc=1   open terminal failed: not a terminal
new-session -A -D -d -s prod (exists)        rc=1   open terminal failed: not a terminal
has-session -t '=prod' || new-session -d -s prod    rc=0   <-- the working form
new-session -A -d -s mysess  (mysession exists)     rc=0, and CREATED A SECOND SESSION 'mysess'
```

`-A` makes `new-session` behave like `attach-session`, and there is no terminal to attach to under
launchd. **So the reaper returns non-zero on every healthy tick** — a job that pages when nothing is
wrong, which trains Jon to filter it (anti-goal 2), and whose exit code cannot be used as the
liveness signal. The last line is the second half: `-A` does **not** exact-match, so a typo'd or
prefix name silently creates a *new* session rather than adopting the real one.

**How to avoid/fix**:

```bash
# ❌ WRONG — rc=1 on every healthy tick; prefix-creates a decoy session on a typo
tmux new-session -A -d -s "$SESSION"

# ✅ RIGHT — guard with exact match, create only on real absence, verify afterwards
if tmux has-session -t "=$SESSION" 2>/dev/null; then
  log "session '$SESSION' present -- nothing to do"; exit 0
fi
log "session '$SESSION' ABSENT -- creating via bootstrap-session.sh"
bash "$HERE/bootstrap-session.sh" --session "$SESSION" --lanes "$LANES" || {
  notify "REAPER FAILED to rebuild '$SESSION'. Nothing is running. Rebuild by hand: bootstrap-session.sh --session $SESSION"
  exit 1
}
tmux has-session -t "=$SESSION" 2>/dev/null || { notify "REAPER reported success but '$SESSION' still absent"; exit 1; }
```

**Positive control for the test**: create the session, tick the reaper, assert it exits **0** and
created nothing. Then kill it (`kill-session -t "=name"`, never `kill-server`), tick, assert
creation. A reaper tested only on the absent case is the one that pages every three minutes forever.

---

### 4. `bootstrap-session.sh` REFUSES on a partial session, and cannot repair one

**Severity**: Critical · **Category**: Actuator gap the plan assumes away
**Affects**: A1/A2. **Source**: `scripts/supervisor/bootstrap-session.sh:244-251, 259-292, 296-314`

Three measured properties of the script the reaper is supposed to invoke:

1. **Session exists, no `--add-lanes` → `exit 1`, no repair** (`:244-251`). Correct for a human;
   fatal for an unattended reaper that finds a session with 1 of 10 windows.
2. **`--add-lanes` never creates the supervisor window.** The lane loop is
   `idx=$SUPERVISOR_WINDOW; while idx < SUPERVISOR_WINDOW+LANES-1; idx++` (`:296-297`) — it starts
   *after* the supervisor slot. A session that lost exactly its supervisor window **cannot be
   repaired by this script at all**, in either mode.
3. **`--add-lanes` never calls `adopt-session`** (`:274-287`, and the comment says so deliberately).
   So a session the reaper tops up is never registered in the `sessions` table — and A2 makes that
   table the reaper's own trigger. **The reaper would repair a session and then forget it.**

Also: existing windows are "left alone" (`:299-302`) — no `send-keys`, so a window whose agent died
is counted as healthy. `has-session` returning 0 says nothing about whether anything is running.

**How to avoid/fix**: give the reaper a three-state classifier, not a boolean, and only ever hand
`bootstrap-session.sh` the case it is built for.

```bash
classify_session() {                       # absent | partial | complete
  tmux has-session -t "=$1" 2>/dev/null || { echo absent; return; }
  n=$(tmux list-windows -t "=$1" -F '#{window_index}' 2>/dev/null | grep -c . || true)
  [ "${n:-0}" -ge "$LANES" ] && echo complete || echo partial
}
case "$(classify_session "$SESSION")" in
  complete) exit 0 ;;
  absent)   bootstrap-session.sh --session "$SESSION" --lanes "$LANES" ;;   # the supported path
  partial)  bootstrap-session.sh --session "$SESSION" --lanes "$LANES" --add-lanes
            # --add-lanes does NOT adopt; do it explicitly, and do not let it fail silently
            python3 "$HERE/cli.py" adopt-session --session "$SESSION" --source reaper.sh \
              || notify "reaper: '$SESSION' topped up but NOT recorded in sessions -- it will be re-reaped every tick" ;;
esac
```

**Separately, and it is a small patch worth making**: fix `bootstrap-session.sh`'s `--add-lanes`
loop to also create `$SUPERVISOR_WINDOW` when it is missing, with a test that removes exactly that
window and asserts recovery. Otherwise the reaper has an unrepairable state.

---

### 5. S2's branch guard, landed before A8, takes the whole estate offline

**Severity**: Critical · **Category**: Ordering hazard / self-inflicted outage
**Affects**: S2, A8, A1, A9. **Source**: measured git state + `docs/.../codebase-patterns.md` plist table.

Measured now: the shared checkout is on `fix/director-tick-fanout`; four of six live LaunchAgents
execute from it. `run-from-main.sh` refuses (exit 78) on any ref that is not an ancestor of
`origin/main`. **So the moment S2's wrapper is inserted into those four plists, all four jobs stop
running** — including, if it is also wrapped, the new session reaper. The remediation would ship the
outage it exists to prevent.

Worse, Phase 2B's own wrapper `exit 78`s when `git fetch` fails. **A network blip disables the only
actuator that can rebuild a dead estate** — verbatim the root cause the audit found (refusal on
uncertainty, gating the actuator, in the exact conditions it is needed).

**How to avoid/fix**:

```bash
# ✅ Ordering, non-negotiable:
#   1. advance live/ to a commit that IS an ancestor of origin/main
#   2. repoint all six plists at live/  (A8)  and bootout/bootstrap each one
#   3. verify with `launchctl print`, not the plist on disk
#   4. ONLY THEN insert run-from-main.sh

# ✅ And the wrapper must degrade, not refuse, on a fetch failure:
if ! git -C "$REPO" fetch --quiet origin main; then
  notify "run-from-main: fetch failed; falling back to the last-known origin/main ref"
  # do NOT exit -- a stale-but-real origin/main is a better gate than no job at all
fi
git -C "$REPO" merge-base --is-ancestor HEAD origin/main; rc=$?
case $rc in
  0) exec "$@" ;;
  1) notify "REFUSED: $(git -C "$REPO" rev-parse --short HEAD) is not an ancestor of origin/main. Nothing ran. Merge it, or repoint this job at live/."; exit 78 ;;
  *) notify "REFUSED: merge-base errored ($rc). Nothing ran."; exit 78 ;;
esac
```

**The reaper is exempt from S2 by design, and the exemption must be written down**, with the reason:
a guard that can prevent recovery is worse than an unguarded recovery. If that is unacceptable, the
reaper lives in `live/` and is *checked* rather than *wrapped*.

`exit 78` shows in `launchctl list` as raw **19968** (78 × 256). The A9 sweep must decode it as a
deliberate refusal, not a crash, or the refusal channel becomes the alarm channel.

---

### 6. A user-global blocking `Stop` hook fires on all 162 `claude -p` lanes

**Severity**: Critical · **Category**: Cost / runaway
**Affects**: S1, F3, D6. **Source**: `scripts/supervisor/dispatch-claude-print.sh:2,188-235`;
hooks doc — `PreToolUse` and friends fire in every permission mode including `bypassPermissions`.

S1's `Stop` hook lands in `~/.claude/settings.json`, which is **user-global**. 162 of 196 lanes run
`claude -p`. A `Stop` hook that exits 2 blocks the stop and makes Claude keep working — on every one
of those lanes, in parallel, up to the 8-consecutive-block cap. This estate has already burned $80
of credits to $8 in one day (D6) with no stand-down path.

**How to avoid/fix**:

```bash
#!/usr/bin/env bash
# check_stop_authorized.sh — S1
set -uo pipefail
INPUT=$(cat)
val() { printf '%s' "$INPUT" | python3 -c 'import json,sys;print(json.load(sys.stdin).get(sys.argv[1]) or "")' "$1" 2>/dev/null; }

# 1. Honour the loop cap or the hook is overridden and reads as installed-but-ignored.
[ "$(val stop_hook_active)" = "True" ] && exit 0
# 2. SCOPE. Only the supervisor's own sessions are governed; a lane is not the supervisor.
case "$(val cwd)" in
  "$SUPERVISOR_REPO"|"$SUPERVISOR_REPO"/*) : ;;
  *) exit 0 ;;
esac
# 3. Blindness is NOT authorisation -- this is where stop-gate.sh is the counterexample, not the model.
[ -n "$(val transcript_path)" ] || { echo "STOP REFUSED: hook could not read the transcript; blindness is not authorisation." >&2; exit 2; }
stop_is_authorized || { echo "STOP REFUSED: no \$STATE/handoff/<session>.blocked naming a Jon-only decision, and no Telegram send in 10m." >&2; exit 2; }
exit 0
```

`~/source/repos/skills-research/Hill90/scripts/hooks/stop-gate.sh` fails **open** on four separate
unreadable-input paths (lines 15/21/26/32). For S1 that is exactly backwards: the rule is *the agent
may not go quiet*, and "I could not tell" is the state in which it goes quiet. **Fail closed on
blindness, and scope by `cwd` so the closed failure cannot reach 162 lanes.**

**Mandatory acceptance**: a test that drives the hook with `stop_hook_active=true`, with a lane
`cwd`, and with an empty transcript, asserting `0`, `0`, `2`. And a costed dry run on **one** lane
before the hook is installed globally.

---

## High Priority Gotchas

### 7. The reaper resurrects a session whose ledger lane claims are stale

**Severity**: High · **Category**: State divergence
**Affects**: A1, A10, AGENTS.md invariants 3/9/10.

A tmux server restart destroys every session; `@N` window IDs restart from `@0` (tmux(1): IDs are
unique "for the life of the ... window **in the tmux server**"). The reaper then rebuilds
`agent-supervisor` with fresh windows — but the ledger still holds lane rows and task claims for the
*old* windows. `grep -n window_id scripts/supervisor/core.py` returns **nothing**, so the ledger
keys lanes by name, not `@id`: the new `free-3` inherits the old `free-3`'s claim. A dispatch then
either skips a genuinely free lane or hands work to one it thinks is busy.

**Fix**: the reaper reconciles before it reports success, and it does **not** restart lanes
(invariant 3 survives — the session is rebuilt, the lanes are marked, not resumed):

```bash
bootstrap_ok && for lane in $(claimed_lanes_for "$SESSION"); do
  python3 "$HERE/cli.py" lane-free --lane "$lane" --reason "session rebuilt by reaper; prior claim cannot survive a server restart"
done
```
The refusal-names-its-actuator clause applies: each freed lane's task must be reported as *needing
redispatch*, naming the command, not silently orphaned.

### 8. A trigger, a hook, or a gate installed over existing contamination looks clean

**Severity**: High · **Category**: Scope confusion
**Affects**: S6, S4, S5, S9, S10. **Source**: `core.py:1085-1097` argues this for the existing trigger.

A `BEFORE INSERT` trigger binds **future** inserts only; `CREATE TRIGGER` succeeds over 581
contaminated rows and reports nothing. The same shape holds for every hook (S4's three live public
violations survive the hook that prevents new ones) and every ceiling auditor (414 branches / 202
worktrees today).

**Fix**: every enforcement mechanism ships as a **pair** — the preventer and a one-shot scan of the
existing corpus that refuses to install until the scan is clean or the rows are explicitly
grandfathered by count. Copy `core.py:1136-1144`: probe first, `RuntimeError` naming the offending
rows and the exact repair command. Grandfathering must be **by count so the number can only go
down** (seat 4's shape for the 43 refusal sites).

### 9. `REGEXP` in a trigger bricks every INSERT; `'*?'` in GLOB matches everything

**Severity**: High · **Category**: SQL quirk with a fail-closed blast radius
**Affects**: S6. **Source**: Phase 2B measurement; https://sqlite.org/lang_expr.html

Python's `sqlite3` defines no `regexp()`. `CREATE TRIGGER` using it succeeds; **every subsequent
INSERT into `items` — honest ones included — raises `OperationalError: no such function: regexp`**
from any connection that did not register it. `core.py` is the writer, so this bricks ingest.

And the GLOB substitute has its own trap: `?` is a single-character wildcard, so `'*?'` means "any
non-empty string" — the trigger would reject **every** hard item. Write `'*[?]'`.

```sql
-- ✅ RIGHT: built-in operators only, classifier pinned literally in the schema
WHEN NEW.weight = 'hard' AND NEW.kind IN ('directive','parameter')
 AND ( NEW.source_text GLOB '*[?]'
    OR lower(NEW.source_text) GLOB 'what *' OR lower(NEW.source_text) GLOB 'why *'
    OR lower(NEW.source_text) GLOB 'how *'  OR lower(NEW.source_text) GLOB 'should *' )
BEGIN SELECT RAISE(ABORT, 'a question may not be recorded as a hard item'); END;
```
Use `RAISE(ABORT)`, never `RAISE(IGNORE)` (silently drops the row — this audit's own defect) and
never `RAISE(ROLLBACK)` (kills the whole ingest transaction). **Publish the count this exact literal
produces at landing**; the 209/305/581 disagreement *is* a disagreement about this literal, and the
plan must not silently pick one.

**Test both directions**: a synthetic hard-from-question insert must raise, and a legitimate
non-interrogative hard insert must succeed — from a **fresh connection**, not the migration's.

### 10. `ALTER TABLE ADD COLUMN ... NOT NULL` requires a DEFAULT

**Severity**: High · **Category**: Migration failure
**Affects**: `prompts.provenance`.

`provenance TEXT NOT NULL CHECK (provenance IN ('human','agent'))` cannot be added as written.

```sql
-- ✅ Path A, and 'unknown' is the honest value: it distinguishes "not yet backfilled" from "human"
ALTER TABLE prompts ADD COLUMN provenance TEXT NOT NULL DEFAULT 'unknown'
  CHECK (provenance IN ('human','agent','unknown'));
```
Tightening later needs the documented 12-step rebuild, which is the shape `core.py:767-803` already
uses. Do not silently default to `'human'` — that would assert the very thing C6 says is false.

### 11. `PostToolUse` cannot block; hook matchers cannot see a command

**Severity**: High · **Category**: Mechanism does not do what the seat said
**Affects**: S5, S4. **Source**: https://code.claude.com/docs/en/hooks.md

- The seat specifies **`PostToolUse`** for S5. `PostToolUse` fires **after** the write; exit 2 is
  shown to Claude and undoes nothing. To *prevent* a `.sh` landing in `~/.local/state`, it must be
  **`PreToolUse`** on `Write|Edit`. Flag this to Jon as a correction, not a silent substitution.
- Matchers match the **tool name only**, literally and case-sensitively. S4's
  `gh (issue|pr) (create|edit|comment)` is not a matcher. Use `matcher: "Bash"` (optionally the `if:
  "Bash(gh *)"` pre-filter) and grep `tool_input.command` from the stdin JSON inside the script.
- Multiple hooks on one event run **in parallel**; a `deny` does not suppress a sibling's side
  effects. Do not write hooks that assume ordering.

### 12. Claude Code fails OPEN on a missing hook script

**Severity**: High · **Category**: Guard that looks installed
**Affects**: all four hooks. **Source**: `tests/supervisor/test_protect_shared_checkout.sh:8-13` —
this repo lost a guard exactly this way (settings pointed at `.claude/hooks/…`, script shipped at
`.claude/…`).

**Fix**: every hook needs the two-part test — (a) read the command out of the **real**
`~/.claude/settings.json`, resolve it, assert the file exists and is executable; (b) feed synthetic
stdin JSON and assert exit 2. Part (a) is the one that matters: an unwired hook is indistinguishable
from a compliant estate. The installer must be idempotent, must back up the existing file, must have
an uninstaller, and must **validate the JSON before writing** — a corrupted user-global
`settings.json` breaks every Claude session on the machine, not just this repo's.

### 13. `plistlib` cannot parse 5 of 6 live plists — a naive sweep reports a false clean

**Severity**: High · **Category**: Blind instrument
**Affects**: A8, A9. **Source**: Phase 2A measurement (`ExpatError: not well-formed`, line 14 col 53).

XML forbids `--` inside comments; the house comment style uses it. `launchctl` accepts it; a strict
parser does not. A sweep written as `try: plistlib.load() except: continue` reports **one** compliant
plist and **zero** violations.

**Fix**: `plutil -convert xml1 -o - "$f"` (or `-lint`), and **treat a parse failure as a failure,
never a skip**. Positive control: `plistlib` parses `supervisor-watchdog` fine, so the parser works —
the five failures are real, not a broken instrument.
**And read `launchctl print`, not the file**: editing a plist without `bootout`/`bootstrap` leaves
the old `ProgramArguments` live, so a file-based check verifies the intention, not the running job.

### 14. launchd exit-status decoding, and the wildcard `StartCalendarInterval`

**Severity**: High · **Category**: API quirk
**Affects**: A9, S3, S5, S10.

`launchctl list`'s status column is the raw `waitpid` word: `768 = 3 << 8` → exit 3;
`19968 = 78 << 8` → the deliberate `EX_CONFIG` refusal. Negative = signal.
`StartCalendarInterval` treats **missing keys as wildcards** — `{Hour: 3}` fires 60 times, once a
minute for an hour. Always pin `Minute`.
`KeepAlive{SuccessfulExit: false}` on a job that refuses with 78 respawns it in a hot loop — do not
use it on anything wrapped by `run-from-main.sh`.
`StartInterval` below 10s is silently throttled (`ThrottleInterval` default 10).
**Positive-control the A9 sweep** by planting a plist that exits 3 and asserting the sweep reports
it, before trusting a clean sweep.

---

## Medium Priority Gotchas

### 15. `tmux display -t` exits 0 for a nonexistent target — and silently answers about the wrong one

`display-message -p -t '=nosuch:@0'` → prints `:` and exits **0** (re-measured today). The S3
prescription is the defect A10 exists to fix. Use `has-session -t "=sess:@id"` (exits 1, "can't find
window: @99") or `list-panes -t`. Without the `=`, `has-session` **prefix-matches** — `has-session -t
mysess` returns 0 against `mysession`. Every `has-session` and every `kill-session` in this estate
takes `=`. `bootstrap-session.sh:219-229` already documents this from a real #137 bug; copy it.

### 16. Reaping "dead" tmux sockets and "merged" branches can destroy live work

**Affects**: S10 / `reap.sh`. Measured today: **416** socket entries, **202** worktrees, **414**
non-main branches, of which **347** are *not* merged into `main`.

- A socket file's age says nothing about whether its server is alive. **Only remove a socket after
  `tmux -S "$sock" list-sessions` fails**, never by mtime.
- Squash-merged branches read as unmerged. `git branch -d` refuses them (safe); `git branch -D`
  destroys them (not). **Never `-D` in an automated reaper.** With 202 worktrees pinning branches,
  `-d` also refuses a checked-out branch — that is a feature.
- `git worktree prune` only removes admin files for already-missing directories, so it is safe
  unconditionally — but a **moved** worktree needs `git worktree repair`, not prune. Dry-run first
  (`prune -n -v`); that dry-run discipline is what caught A6.

### 17. `restore.sh --session` is a redirect; automating it is destructive today

`restore.sh:121` overwrites `target_session` per row. Measured by the council: 156 restores into a
10-window session, and a bare run resurrects five sessions including a test one. **The split into
`--only-session` must land before anything schedules restore**, its dry-run must exit before any
`new-session` (`bootstrap-session.sh:114-155` is the validate-before-mutate model), and #347's
acceptance grep must be replaced — `grep -qE "claude.print|harness_session_id|detached"` passes
against unfixed code because `harness_session_id` appears for unrelated reasons.

### 18. Verifying by grepping for the text you just sent

`heartbeat.sh:149` builds `MSG` containing `` `esc to interrupt` ``; `:197` greps the whole pane for
`esc to interrupt`; `:200` is unreachable. The same file does it right at `:93` (footer, not
scrollback). `director-route.sh:149` carried a private copy of an idle matcher that could never
match, and discarded Jon's Telegram replies for a week (#350/#352).
**Rule for this PRP: one shared matcher, sourced — never a private copy; and never verify against a
region that contains your own message.**

### 19. Deduplicating on a name

`ci_gate.py:_latest_per_name` keys on the check-run name; `fixpass-evidence.yml:34` and
`ui-evidence.yml:26` both declare `gate:`. Rename one (one line) **and** add the recurrence lint —
~15 lines of stdlib Python over `.github/workflows/*.yml`, no dependency, auto-discovered by
`unittest`. **Could not find** a first-party Actions linter that enforces cross-workflow job-name
uniqueness. The same class lurks in any plist sweep keyed on a script basename: `live/` and the
shared checkout share basenames.

### 20. macOS instrument traps that look like clean results

`pgrep -c` returns empty even with matches; `find -newermt` matched 0 of 1,159 files; `log show`
returns 0 lines without elevation; `lsof` is at `/usr/sbin/lsof`, which is **not** on the LaunchAgent
`PATH` (`poller-recover.sh:157-161`, and the tracked plist's `PATH` confirms `/usr/sbin` is absent).
**Every one of these returns success.** Resolve absolute paths in the script, and positive-control
each absence assertion before trusting it.

---

## Low Priority Gotchas

### 21. Shell-profile output corrupts hook JSON
A profile that `echo`s in a non-interactive shell prepends text to the hook's stdout and breaks
parsing. Guard profiles with `if [[ $- == *i* ]]`. Parse with `python3 -c`, not `jq` — `jq` is not
guaranteed on this machine and the estate's stdlib-only rule already says so.

### 22. `set -uo pipefail` is the house default, `set -euo` is not
38 files vs 1 (`bootstrap-session.sh:63`). These scripts want to report, not abort. A new actuator
that adds `-e` will exit on the first benign non-zero — and `tmux list-sessions` with **no server
running exits 1** (measured), which is precisely the total-death case. **A reaper with `set -e`
aborts exactly when everything is dead.**

### 23. `comm`-based set difference no-ops when the left side is empty
Measured: `comm -23 <(empty) <(live)` prints nothing and exits 0 — so a reaper whose ledger query
failed does nothing and reports success. Assert the ledger side is non-empty before differencing;
that is the same non-empty-glob positive control `test_shell_suites.py:65-68` already uses.

---

## Irreversible actions — every one needs an authorisation gate

| Action | Why irreversible | Required gate |
|---|---|---|
| Editing agent-dotfiles #237, #174, PR #55 | Public artifacts; edit history is visible | Jon's explicit go; preserve the original text in a private note first |
| `agent-tui` → public | Cannot be un-seen | Reserved to Jon in the corpus itself |
| Deleting 1,057 `hill90-app` prompt rows | His corpus | Verified restorable backup (restore it into a temp DB and count, do not trust the file's existence), plus `safe-deletion`: look at the rows before deleting |
| Rewriting ~588 rows of his words | `text_raw` is the evidence other claims are settled against; `core.py` says it is never altered after insert | Write to a new column/table, never over `text_raw` |
| Deleting the three `at14-scratch-*` `sessions` rows | Live table | Inspect first; a DELETE with no WHERE-guard on a table whose PK is a free-text name is one typo from removing a production row |
| `git branch -D` in `reap.sh` | Unmerged work | Never automate `-D` |
| Removing tmux socket files | Orphans a live server | Only after a failed connect |
| Rewriting `~/.claude/settings.json` | Breaks every Claude session on the machine | Back up, validate JSON, ship an uninstaller |

**The Telegram bot token** in prompts row `mp-5e0dfc607d119fd4` (seat-raw-1) is a credential exposure
outside the 51. **Could not check** — I did not open the ledger (see Critical 1; and it is read-only
by constraint). Treat as exposed until rotation is proven: rotate first, then redact, and note that
redacting the row does **not** un-expose an already-exported corpus.

---

## Gates that can pass while the system is broken — the checklist

Each of these is a measured or structural false-green. **A gate must fail this list before it counts.**

- [ ] Ledger unreadable → count empty → `[ "" -gt 0 ]` errors → **exit 0**. (Critical 1 + 2.)
- [ ] `plistlib` parse error skipped → 1 of 6 files examined → **"zero violations"**. (13.)
- [ ] `tmux display -t` on a dead target → **exit 0**. (15.)
- [ ] `! cmd` or a bare guard inside `if` under `bash -eo pipefail` → **never aborts**. (Bash manual,
      `-e` exemption; reproduced in three lines by Phase 2B.)
- [ ] Trigger/hook installed over existing contamination → **succeeds, changes nothing**. (8.)
- [ ] `has-session` without `=` → passes against a **different** session. (15.)
- [ ] `pgrep -c` / `find -newermt` / `log show` → empty **is** the clean result. (20.)
- [ ] A `grep` that matches the message the script just sent → **always green**. (18.)
- [ ] `comm` with an empty left side → **nothing to do, exit 0**. (23.)
- [ ] A hook whose script path does not resolve → **fails open, silently**. (12.)

**Standardise two literal test-name prefixes** — `mutation-check:` and `positive-control:` — so
`grep -rn 'mutation-check:\|positive-control:' tests/` is the committed evidence the meta-criteria
demand. Neither string exists in the tree today (Phase 2A grepped: zero matches).

---

## Anti-pattern: the guard that gates the actuator

The audit's root cause is that every actuator sits behind a refusal-on-uncertainty. **Four
mechanisms in this very plan re-create it**, and each needs an explicit exemption written down:

1. `run-from-main.sh` gating the reaper (Critical 5).
2. `set -e` in the reaper, aborting on `tmux list-sessions`' exit 1 when no server is running (22).
3. The S1 `Stop` hook failing open on blindness — going quiet is the failure it exists to prevent (6).
4. The ledger snapshot failing and the reaper defaulting to "nothing to do" (Critical 1, 23).

**The rule to carry into the PRP** (seat 4's proposed 11th invariant, sharpened): *a refusal must
name what acts instead, and no refusal may sit between total death and the actuator that fixes it.*

---

## Confidence Assessment

**Gotcha coverage: 8.5/10.**
- **False-green instruments**: high confidence. Four measured, two compounding, live-ledger verified.
- **tmux / launchd / SQLite mechanics**: high. All measured on this machine at the real versions
  (tmux 3.5; sqlite CLI 3.51.0, Python module 3.53.4).
- **Ordering and blast radius**: medium-high. Reasoned from measured git/plist state; the S2-before-A8
  outage is a prediction, not an observation — it should be dry-run before anyone believes me.
- **Security**: medium. One credential exposure relayed, not confirmed.

**Could not check**:
- The ledger's contents — `mode=ro` fails (Critical 1) and the constraint forbids anything stronger.
  Every corpus number in this PRP (581, 703, 1,057, 920) is relayed from the seats, not re-measured.
- Whether `claude -p` honours a user-global `Stop` hook. The docs say `-p` does not grant *workspace
  trust* (which gates **project** hooks); user-global hooks are not documented as exempt. Critical 6
  assumes they fire. **Test on one lane before installing globally** — if they do not fire, S1's
  scope shrinks and so does its risk.
- `jonhill90/skills@5688dfe1` — not fetched.
- Whether `@N` IDs actually restart at `@0` after a server restart — inferred from the man page's
  "in the tmux server" scoping; not measured (would require restarting a server).

**Recommendation**: the PRP's "Known Gotchas" section should lead with Critical 1–3, because each
one means an implementer following the current planning documents literally ships something that
does not work and reports that it does.
