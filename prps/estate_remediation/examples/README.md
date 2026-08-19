# estate_remediation — Code Examples

**These are extracted code files, not references.** Every block below was copied
out of a real file in this estate (or, for one example, out of another repo on
this machine) at commit `6b7c4435`, 2026-08-19. Read them; do not go looking for
the originals first.

## Overview

Five of the six examples are the *house style* an implementer must match — a
shell actuator, a shell test, a Claude Code hook, the notification path, and a
SQLite migration. The sixth is different in kind: it is the estate's best
correct-vs-broken pair, extracted into one annotated file, because the same
author wrote the fix and reintroduced the bug 104 lines later in the same file.

**One correction to the brief, up front:** the brief anticipated that no Claude
Code hook example might exist and asked for a `NO_EXAMPLE_EXISTS.md`. That file
is not here, because working hooks *do* exist on this machine — including a
`Stop` hook, the exact event S1 needs. See Example 3.

## Examples in This Directory

| File | Source | Pattern | Relevance |
|---|---|---|---|
| `example_1_shell_actuator_house_style.sh` | `scripts/supervisor/bootstrap-session.sh` + `poller-recover.sh:140-175` | Shell actuator: header, env config, arg parsing, mkdir lock, validate-first, refusal-that-names-its-actuator, `--dry-run`, exit codes | 10/10 |
| `example_2_shell_test_isolation_and_positive_control.sh` | `tests/supervisor/test_bootstrap_session.sh`, `scripts/supervisor/tmux-isolation.sh`, `tests/supervisor/test_observed_absence_sampling.sh` | Shell test: assertions, tmux isolation, scratch ledger, traps, **positive-controlled absence** | 10/10 |
| `example_3_claude_code_hooks.sh` | this repo's `.claude/`; `skills-research/Hill90/scripts/hooks/stop-gate.sh` | `settings.json` schema, stdin payload, exit-code contract, `Stop` hook, global installer requirements | 10/10 |
| `example_4_notify_send_path.py` | `scripts/supervisor/watchdog_notify.py` | Pure decision core + thin actuator; `SendError`; the three live defects D3/D4/D5 in situ | 10/10 |
| `example_5_sqlite_migration_and_trigger.py` | `scripts/supervisor/core.py` | `_migrate_*` rebuild-in-place; `BEFORE INSERT` + `RAISE(ABORT)`; pre-flight scan; read-only access | 10/10 |
| `example_6_pane_match_correct_vs_broken.sh` | `scripts/supervisor/heartbeat.sh:84-96` and `:190-201` | The trap and the fix in one file — finding E2 | 10/10 |

---

## Example 1: Shell actuator, house style

**File**: `example_1_shell_actuator_house_style.sh` · **Relevance**: 10/10

### What to Mimic
- **The header that argues for the script's existence.** Every load-bearing
  script here opens with WHY it exists, WHAT it refuses to do, and the incident
  that taught it. `-h` prints the header (`sed -n '1,40p' "$0"`). A new actuator
  without this does not match the estate.
- **Session names from config, never literals.** `SESSION="$(lanes_session_or_default)"`.
  There are 304 `agent-supervisor` and 168 `director` literals in
  `scripts/supervisor/*.sh` today — finding A11, asked 14 times.
- **The reclaimable `mkdir` lock.** macOS ships no `flock(1)`; `mkdir` is atomic
  anyway. The lock records holder PID and timestamp so a lock orphaned by
  SIGKILL can be told from a live one and reclaimed. A non-reclaimable lock
  makes the actuator die silently exactly once, which is the estate's whole
  failure mode.
- **Validate everything before touching anything**, each guard citing the review
  that added it (`--session` containing `:`; `command -v` matching a shell
  builtin; `lsof` not on the LaunchAgent PATH).
- **The refusal that names its actuator.** Four of five lines in the refusal
  block are the naming. Seat 4's proposed 11th invariant.
- **`--dry-run` as a first-class path**, via a `run()` wrapper. This discipline
  is what caught restore.sh planning 156 restores into a 10-window session.
- **Exit codes carry meaning** and are documented in the header (`2` = "some
  lane could not be brought back, and that is not a crash"; `78` = S2's refusal).

### What to Adapt
- The reaper (A1/A2) inverts the direction: it reads the `sessions` table,
  set-differences against `tmux ls`, and *calls* `bootstrap-session.sh` for each
  missing owned session. Keep the lock, logging, dry-run and refusal shapes.
- `adopt-session` is the **write** side of A2; the reaper is the read side.

### What to Skip
- The harness-inference block (`--harness` from `--agent`'s basename) is
  bootstrap-specific.
- `set -euo pipefail` vs `set -uo pipefail`: several scripts use the latter
  deliberately because they inspect exit codes. Choose consciously and comment.

### Why This Example
The session reaper is the one actuator that has never existed, and it is a near
sibling of this file. Copying the shape is most of the work.

---

## Example 2: Shell test — isolation and the positive control

**File**: `example_2_shell_test_isolation_and_positive_control.sh` · **Relevance**: 10/10

### What to Mimic
- **`assert_isolated_tmux`, always.** `tmux kill-server` destroyed this estate
  three times. The guard refuses when `$TMUX` is set or `$TMUX_TMPDIR` is unset
  or missing. Since #185 it covers session *creation* too.
- **Redirecting `TMUX_TMPDIR` redirects what "default" MEANS.** That is the
  mechanism that makes it safe to test session creation at all.
- **A scratch ledger** via `AGENT_SUPERVISOR_STATE_DIR`. Mandatory for anything
  that writes; the corpus work makes it absolute.
- **`ok` / `bad` / `check` and a pass/fail counter.** No framework.
- **Exact-match kills in an `EXIT INT TERM` trap**, with every variable the trap
  touches declared before the first line that could fail.
- **Assert the property, never a snapshot literal.** `before_existing="$(windows)"`
  then compare — because tmux's `base-index` is a user setting and hardcoding
  `1` tested the CI runner's config, not the script.
- **`SKIP`, don't fail, when the instrument is absent** (`command -v tmux`).
- **The positive control (section E).** Plant a violation, assert it is
  detected, remove it, *then* assert absence. Six false-clean results happened
  in one day in the sibling estate. Note the `/tmp` prefix gotcha: `$TMPDIR` on
  macOS overflows AF_UNIX's ~104-byte `sun_path` limit and tmux reports it as
  "File name too long", which reads like a setup bug.

### What to Adapt
- The rules being asserted. The scaffolding is reusable verbatim.
- `test_observed_absence_sampling.sh`'s three adverse conditions (inside a tmux
  pane with `$TMUX` set; from a real `git worktree add` checkout; interrupted
  with SIGKILL) — apply the ones relevant to the gate under test.

### What to Skip
- The continuous background sampler is worth it only where a leak is transient.
  A one-shot positive control is enough for most CI gates in this PRP.

### Why This Example
Every new gate here lands as a test of this shape, and `test_shell_suites.py`
globs `test_*.sh` into `unittest discover` — so a shell test dropped in
`tests/supervisor/` **is** genuinely enforced by CI. Verified, not assumed.

---

## Example 3: Claude Code hooks

**File**: `example_3_claude_code_hooks.sh` · **Relevance**: 10/10

### What to Mimic
- **The `settings.json` schema**, from the widest real example on this machine
  (`skills-research/Hill90`), which registers `PreToolUse`, `PostToolUse`,
  `Stop` and `PreCompact`. Note that `Stop`/`PreCompact` entries carry **no**
  `matcher`; per-tool events do (`"Bash"`, `"Edit|Write"` — a regex alternation).
- **The exit-code contract**: `0` allows (stdout not shown to the model), `2`
  **blocks** and feeds stderr back as the reason, anything else is a
  non-blocking error and the tool call proceeds. A hook that prints a reason and
  exits 0 has done nothing.
- **Parse the stdin payload with `python3 -c`** (stdlib), not `jq`. Both are in
  use here, but `jq` is not guaranteed on the machine and these hooks install
  globally.
- **Narrow fast.** Immediate `exit 0` on anything the hook does not care about.
- **`stop-gate.sh`'s four fail-open gates**, which ask "can this hook SEE?"
  before judging, and say so via `systemMessage` rather than passing silently.
- **The refusal text** names the command, the incident, and the alternative with
  a literal command to run.

### What to Adapt
- `stop-gate.sh`'s rule set is "if you touched X you must have run Y". S1's is
  "are you *allowed* to stop" — a `$STATE/handoff/<session>.blocked` file naming
  a Jon-only decision, plus a Telegram send logged in the last 10 minutes, or
  zero dispatchable issues.
- **Fail-open vs fail-closed is the real design call** and must be argued in the
  PRP. `~/.claude/settings.json` is global, so a `Stop` hook failing closed on a
  blind instrument can wedge every session on the machine. Recommendation in the
  file: fail open on blindness, fail closed on a readable transcript showing an
  unjustified stop, and **page on the fail-open path** so blindness is never
  silent — which is precisely what D3's `NOTIFY-PATH-STALE` got wrong.

### What to Skip
- `$CLAUDE_PROJECT_DIR` — it has no meaning in the user-global file. Use
  absolute paths there.
- `PreCompact`/transcript-backup hooks; out of scope.

### Why This Example
Four to five of the ten STANDARD rules are hooks, and the feature analysis
states there is "no working example in this estate to copy from." **That is now
corrected: there are three, including a `Stop` hook.** What remains true is that
`~/.claude/settings.json` has no `hooks` key at all — verified 2026-08-19, its
keys are exactly `alwaysThinkingEnabled, effortLevel, enabledPlugins,
skipDangerousModePermissionPrompt, theme, tui, voiceEnabled`. Nothing is
enforced globally. Part 4 of the file lists the six requirements the installer
must meet (backup, merge-don't-overwrite, `json` module not `sed`, idempotent,
absolute paths, verify by triggering a block).

---

## Example 4: The notification send path

**File**: `example_4_notify_send_path.py` · **Relevance**: 10/10

### What to Mimic
- **Pure decision core + thin actuator.** `decide_*` does no I/O and sends
  nothing; `check_and_notify` reads state, calls an *injected* sender, and
  persists the episode flag. That injection is what lets S1–S5, A4 and A5 be
  tested without paging Jon.
- **Classify, then decide** — two functions. The threshold comparison lives in
  the decider, so it stays a decision-time parameter rather than being baked
  into the fact read off disk.
- **Blindness is its own state.** `"unreadable"` is never folded into "fine".
- **The flag means "a human has been told", never "we tried."** The whole audit
  is instances of the second recorded as the first.
- **`SendError` and the two `except` blocks.** An `OSError` from a missing or
  non-executable notifier once killed the process with a traceback instead of
  producing the "escalation did NOT reach a human" line — "the estate's loudest
  failure came out as its quietest." Catch the whole family, and treat a timeout
  identically: a channel that hangs reached nobody.
- **The message standard**, from `build_heartbeat_message`'s docstring: how
  stale, against what threshold, and one command to look deeper — readable from
  a lock screen.

### What to Adapt
- Three live defects are annotated in place and are work items, not patterns:
  **D5** (`state: stopped` exemption unbounded in time — bound it), **D4** (the
  `inbox-poll` message hardcoded for all three subscribers, naming the wrong
  subsystem, file and threshold; the caller must supply its own, and the test
  must assert paged-threshold == caller's-threshold), **D3**
  (`NOTIFY-PATH-STALE` returned as a string into an unread log — it must exit
  non-zero and page via the surviving channel).

### What to Skip
- Do **not** build a new channel. Telegram delivery is proven — 88 messages
  landed during the outage. Fix the path.

### Why This Example
A4, A5, D3, D4, D5 and all of S1–S3's paging route through this file. Every new
page must also clear the anti-goal: *do not make alerting louder*. The
one-per-episode flag is the mechanism that makes new pages additions rather than
a storm, and D2's "always send the 30-minute report" must be reconciled
explicitly as **more frequent truthful reports, not more alarms.**

---

## Example 5: SQLite migration and trigger

**File**: `example_5_sqlite_migration_and_trigger.py` · **Relevance**: 10/10

### What to Mimic
- **There is no migrations directory.** A migration is a `_migrate_*` method on
  `core.py` plus one call line in `__init__`. Verified.
- **Idempotence first**: probe `sqlite_master`, return early if already current.
- **`PRAGMA table_info` — ask which columns exist, never assume.** A hardcoded
  copy list would read a column that does not exist on one path and silently
  drop recorded data on another.
- **Per-column backfill expressions, each argued**, recording what actually
  happened rather than a uniform guess — and never guessing where "not
  resolved" is the honest answer.
- **`BEGIN IMMEDIATE`, one transaction, rollback on `BaseException`, `finally:
  close()`.** Foreign keys off only around the rebuild.
- **The `failpoint=` parameter.** It is how the rollback path gets tested. Every
  new migration must accept and honour it.
- **The `BEFORE INSERT` + `RAISE(ABORT)` trigger** — S6's mechanism exactly.
  It surfaces to Python as `sqlite3.IntegrityError`, indistinguishable from a
  real index violation, so callers need not know which mechanism caught it.
- **The pre-flight scan.** A trigger only fires on *future* inserts; it does not
  scan existing rows the way `CREATE UNIQUE INDEX` does. Installing one over a
  contaminated table looks clean and is not. Scan by hand first, and **refuse
  loudly rather than pick a winner** — "failing to migrate is better than
  silently dropping a row."
- **`id != NEW.id`** — the legitimate-retry exclusion. S6's analogue: an
  honestly-labelled `kind='question'` hard row must still pass; only the
  `directive` + `parameter` subset is the defect.

### What to Adapt
- **Pin S6's interrogative regex in the migration and publish the count it
  produces at landing time.** The three seats got 209 / 305 / 581 *because the
  classifier differed*. The contested artifact is the classifier itself. Do not
  cite 305 or 581 as settled.

### What to Skip
- Do not copy `lanes`' specific columns. Copy the transaction skeleton.

### Why This Example
S6's trigger, `prompts.provenance`, the `possibility_count` redefinition and A2's
`sessions` registration all land through these two shapes. The file also carries
the read-access constraint: two seats found **different journal modes on the same
file** (`delete` + `immutable=1` vs WAL with vanishing sidecars). Determine the
mode before choosing the access method.

---

## Example 6: Correct vs broken pane matching

**File**: `example_6_pane_match_correct_vs_broken.sh` · **Relevance**: 10/10

### What to Mimic
- **`grep -v '^[[:space:]]*$' <<<"$p" | tail -1 | grep -q 'esc to interrupt'`.**
  A busy marker is a statement about the pane's *current footer*, never about
  text anywhere in its scrollback.
- **Address windows by `#{window_id}`**, never index.
- **One shared matcher function, called from every site.** The audit's gotcha #7
  records the same class in `director-route.sh:149` — "any private copy of a
  matcher is this defect." Two copies drifted here inside one file.

### What to Avoid
- **The whole-pane grep at line 197.** It searches for a string that `$MSG` —
  typed into that same pane four lines earlier — is guaranteed to contain. The
  condition is always true and **line 200 is unreachable**. Every nudge in the
  estate's history reported success.
- Fixing only the grep. The message must also be made incapable of matching, or
  this re-breaks the next time someone edits the text.

### What to Skip
- Nothing. Read the whole file, including the two gotchas at the bottom
  (claude-print lanes have no pane at all — 162 of 196 lanes; `window_id` does
  not survive a tmux server restart, which is why invariant 5 is *necessary and
  insufficient*).

### Why This Example
The header comment at line 84 describes this trap in detail and the code at line
197 walks straight into it, in the same file, by the same author. Reading either
half alone teaches nothing. The lesson is that the discipline must be applied at
every read of a pane — which is an argument for the shared helper, not for
vigilance.

---

## Usage Instructions

**Study phase.** Read all six. Read example 6 first if short on time — it is the
cheapest way to understand what kind of defect this whole PRP is remediating.

**Application phase.** Copy the scaffolding verbatim (locks, traps, assertion
helpers, transaction skeletons); adapt only the rules. Where an example carries
an annotated live defect (`D3`/`D4`/`D5` in example 4, `E2` in example 6), that
is a work item, not a pattern.

## Pattern Summary

### Common across examples
1. **Verify the instrument before believing the verdict.** The positive control
   (ex. 2), `"unreadable"` as its own state (ex. 4), the pre-flight scan (ex. 5),
   the fail-open gates that announce themselves (ex. 3), and the resolved-by-
   absolute-path `lsof` (ex. 1) are all the same idea.
2. **A refusal must name its actuator.** Ex. 1's refusal block, ex. 3's `BLOCKED:`
   message, ex. 5's `RuntimeError`. 43 sites in the estate refuse without naming
   one; that count may only go down.
3. **Assert properties, never snapshot counts.** The audit's own numbers drifted
   297→304 inside 24 hours.
4. **Argue the decision in a comment, once, where the code is.** Every one of
   these files is more comment than code, and that is the convention.
5. **Reclaimable / idempotent / re-runnable.** Locks, migrations and actuators
   all assume they will be killed mid-run.

### Anti-patterns observed (all live, all in this codebase)
1. **Verifying an effect by matching text you just wrote.** (ex. 6, E2)
2. **A degraded instrument reporting into its own unread log.** (ex. 4, D3)
3. **A time-unbounded suppression.** (ex. 4, D5)
4. **A message hardcoded for one caller and reused by three.** (ex. 4, D4)
5. **A private copy of a matcher.**
6. **Installing a guard over data that already violates it**, without scanning.
7. **A `!`-negated pipeline in a `bash -eo pipefail` step** — it never aborts;
   this made a sibling repo's guard green and dead for 5½ months. Check every
   new bash gate for this exact shape.

## Source Attribution

Archon was NOT available; everything here is repo-local or machine-local.

**From this repo** (`/Users/jon/source/repos/Personal/agent-supervisor/.worktrees/plan/audit-remediation`, commit `6b7c4435`):
- `scripts/supervisor/bootstrap-session.sh:1-62,140-200,240-290`
- `scripts/supervisor/poller-recover.sh:39-62,140-175`
- `scripts/supervisor/restore.sh:1-60`
- `scripts/supervisor/heartbeat.sh:84-96,190-201`
- `scripts/supervisor/watchdog_notify.py:1-38,280-350,590-665`
- `scripts/supervisor/core.py:271-274,702-790,1011,1040-1170`
- `scripts/supervisor/tmux-isolation.sh:1-16` (whole file)
- `tests/supervisor/test_bootstrap_session.sh:1-80`
- `tests/supervisor/test_observed_absence_sampling.sh:1-70`
- `.claude/settings.json`, `.claude/protect-shared-checkout.sh` (whole file)

**From elsewhere on this machine** (hooks, since the brief asked whether any exist):
- `/Users/jon/source/repos/skills-research/Hill90/.claude/settings.json` — 4 events
- `/Users/jon/source/repos/skills-research/Hill90/scripts/hooks/stop-gate.sh` — 99 lines, a **Stop** hook
- Also present, not extracted: `block-local-deploy.sh` (143 lines, PreToolUse/Bash),
  `shellcheck-on-edit.sh` (40 lines, PostToolUse), and PreCompact/PostToolUse hooks
  in `agent-dotfiles` and `vibes-v3`.

---

Generated: 2026-08-19 · Feature: `estate_remediation` · Total examples: 6 · Quality: 9/10
