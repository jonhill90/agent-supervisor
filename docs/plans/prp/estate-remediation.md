# PRP: Estate Remediation — every finding from the 2026-08-19 council

**Format**: Jon's PRP framework (`jonhill90/skills@5688dfe1`), `generate-prp` → `execute-prp`.
**Source of truth**: the six council seats, 2026-08-19. Nothing in this PRP is the supervisor's own assessment.
**Companion**: `estate-remediation/execution/execution-plan.md` — the parallel execution plan.
**Scope**: ALL of it. 51 tasks. No item from any seat is deferred without being named here as deferred and why.

---

## Goal

The estate must survive its own death without Jon, must be unable to misquote him, must be unable to
run code that is not on `main`, and must produce product rather than machinery. Every rule is
enforced by a mechanism that runs **outside the agent's turn**, because the agent's judgement fails
hardest exactly when it is most confident.

**Done means**: the supervisor session can be killed at random and is back inside 5 minutes with no
human action; every one of the ten STANDARD rules has a failing test that goes green; and the first
product commit since 2026-08-09 is on `main`.

---

## Why

- **2026-08-19, four recorded outages**, each ending only when a human typed something.
  `restart-history` is zero bytes. `bootstrap-session.sh` — the only code that can create a session —
  has **zero callers** in any script, any plist, or the (empty) crontab.
- **357 machinery PRs merged, 0 commits to product main.** Jon: *"I got more done 2 weeks ago with
  just my basic skill. And now i dont have anything to show."*
- **52 status polls in 9 days** — he hand-monitored, from his phone, a loop whose entire purpose was
  to not need hand-monitoring.
- **`~/.claude/settings.json` has no `hooks` key at all.** Every rule he repeated 14–53 times was
  left to the agent's judgement. That is the root cause of every other line in this document.

---

## What

### Core outcomes

1. **Self-healing**: a session that disappears comes back, by set-difference between an owned-sessions
   table and `tmux ls`, driven by a launchd job that contains no model call.
2. **The STANDARD, enforced**: S1–S10 as hooks, wrappers, triggers and CI gates.
3. **Honest instruments**: no health predicate that can read OK while nothing executes; no recovery
   that stamps success it did not earn; no guard that verifies itself against its own output.
4. **A corpus that is his words**: provenance-tagged, verbatim-verified, questions never stored as
   decisions.
5. **Product**: Phase 4, and `agent-tui` public.

### Success criteria

- [ ] `tmux kill-session -t agent-supervisor` → session exists again within 300s, unattended, twice in a row.
- [ ] `git merge-base --is-ancestor HEAD origin/main` is enforced at every launchd entrypoint; violating it exits 78 and pages.
- [ ] A `Stop` returns non-zero unless a blocked-file names a Jon-only decision or the queue is empty.
- [ ] `gh issue create` containing profanity attributed to Jon is **blocked** by a hook, not by an agent remembering.
- [ ] `agent-dotfiles` #237, #174, PR #55 no longer quote him with profanity.
- [ ] Zero `.sh`/`.py` files under `~/.local/state/**` that are not also `git ls-files` tracked.
- [ ] `SELECT count(*) FROM items i JOIN prompts p USING(prompt_id) WHERE p.text_raw REGEXP '^\s*\w.*\?\s*$' AND i.weight='hard'` → **0**.
- [ ] Every `prompts.text_raw` is a byte-exact substring of a source `.jsonl`; every real user message has a row. CI asserts both directions.
- [ ] `count(links) > 0` and the conflicts view returns rows for a seeded contradiction.
- [ ] Every module under `scripts/supervisor/` has ≥1 non-test importer, or is deleted.
- [ ] `events` rows older than 1h with `notified_at IS NULL` → 0.
- [ ] Every 30-minute report sends, **including when the count is zero**, and leads with the miss.
- [ ] Quota `UNKNOWN` twice → state decays to `UNSAFE` and dispatch halts.
- [ ] One ACP lane has completed one real task, or `acp_transport.py` is deleted.
- [ ] `agent-tui` visibility = public.
- [ ] ≥1 commit to a product `main` (agent-tui or hill90-app) authored under this plan.

---

## All Needed Context

### Council evidence (MUST READ before any task)

```
docs/audit/2026-08-19-council/seat-1-outside-harness.md    external trigger argument
docs/audit/2026-08-19-council/seat-2-verify-and-extend.md  outage forensics, harness hijack
docs/audit/2026-08-19-council/seat-3-human-cost.md         499 messages, 78.2% corpus contamination
docs/audit/2026-08-19-council/seat-4-table.md              14 rows, tool-enforced fixes
docs/audit/2026-08-19-council/seat-5-prescriptions.md      dry-run-tested remedies + wrong prescriptions
docs/audit/2026-08-19-council/seat-6-standard.md           S1-S10, the standard
```

### Codebase anchors

```
scripts/supervisor/bootstrap-session.sh:260   the ONLY new-session that is safe to automate
scripts/supervisor/restore.sh:121,201         --session is a REDIRECT not a filter (destructive)
scripts/supervisor/poller-recover.sh:155      exit 0 on missing session — the false-success line
scripts/supervisor/watchdog.sh:955,1073-1082  "recovery handles this" literal; success stamping
scripts/supervisor/heartbeat.sh:93,197        correct tail -1 at 93; the same trap reintroduced at 197
scripts/supervisor/watchdog_notify.py:299,336 hardcoded inbox-poll msg; unbounded stopped exemption
scripts/supervisor/ci_gate.py:93              two workflows both named `gate:` — dedup race
scripts/supervisor/itemize_prompts.py         --load writes model-supplied kind/weight verbatim
scripts/supervisor/cli.py:962                 _is_supervisor_lane() — a string compare, not a gate
scripts/supervisor/acp_transport.py           302 lines, tested, zero importers
tests/supervisor/test_shell_suites.py:23      globs test_*.sh — shell tests ARE enforced by CI
~/.claude/settings.json                       no `hooks` key exists
```

### Known gotchas — each has already cost a session

1. **`restore.sh --session X` is a redirect, not a filter.** Dry-run plans 156 restores into a
   10-window session. Never wire it until T14 splits the flag.
2. **A `!`-negated pipeline never aborts a `bash -eo pipefail` CI step.** That is how the
   `--remove-orphans` guard was green and dead for 5½ months. Write guards as explicit `if`/`exit`.
3. **Passing tests are not a working feature.** `acp_transport.py`, `poller-leak-cleanup.sh`,
   `contest-stop.sh` — all tested, all with zero callers.
4. **An acceptance grep can match a comment.** #347's own failing test is green against unfixed code.
5. **`pgrep -c` returns empty on macOS**; `find -newermt` matches 0 of 1159 files; `log show` returns
   0 lines without elevation. All three look exactly like clean results. Positive-control every absence.
6. **`window_id` (`@N`) does not survive a tmux server restart.** Address by name, resolve fresh.
7. **A test harness can claim the production session name on the default socket** — one did, and the
   production loop ticked it. Isolate tests with `TMUX_TMPDIR`.
8. **`docker exec` without `-i` silently drops stdin.** (Applies to any Hill90-side task.)
9. **NEVER `tmux kill-server`.** It destroyed the estate three times. Exact-match kills only.
10. **Usage credits are a UPS.** An exhausted window that keeps ticking burned $80 → $8 on 2026-08-15.

### Desired tree (new files only)

```
scripts/hooks/check_stop_authorized.sh        S1
scripts/hooks/run-from-main.sh                S2
scripts/hooks/no_quote_profanity.py           S4
scripts/hooks/no_code_in_state.py             S5
scripts/hooks/require_adversarial_review.py   ASKS gate
scripts/supervisor/session-reaper.sh          A2 — the actuator
scripts/supervisor/launchd-sweep.sh           A6
scripts/supervisor/reap.sh                    S10
scripts/supervisor/link_items.py              S8 deterministic linker
scripts/supervisor/sessions.conf              owned-session registry (file mirror of the table)
ASKS.tsv                                      one row per explicit ask + its verification command
~/Library/LaunchAgents/com.jonhill.session-reaper.plist
~/Library/LaunchAgents/com.jonhill.launchd-sweep.plist
```

---

## Implementation Blueprint

### Task list

Grouped by concern; execution order is in the execution plan, not here.

**RECOVERY (R)**
- **T1** `sessions` table: insert `agent-supervisor`, `director`; delete the three `at14-scratch-*` rows. Mirror to `sessions.conf`.
- **T2** `session-reaper.sh` — set-difference between owned sessions and `tmux ls`; calls `bootstrap-session.sh` for each missing one. **Zero model calls.**
- **T3** `com.jonhill.session-reaper.plist` — StartInterval 300, RunAtLoad true, runs from `live/` via T7's wrapper.
- **T4** `watchdog.sh` `no_session` branch: call the reaper instead of `exit 0`.
- **T5** `poller-recover.sh:155` → `exit 1`; watchdog must not write `.poller-recovery-last-success` on a tick whose state was `no_session`.
- **T6** Watchdog restart-ceiling: on breach, escalate **and** hand to the reaper. `ESCALATE` unreachable without a rebuild attempt.
- **T7** `run-from-main.sh` wrapper; repoint all `com.jonhill.*` plists through it and onto `$SUPERVISOR_LIVE`.
- **T8** `launchd-sweep.sh` + plist — page on any `com.jonhill.*` with `LastExitStatus != 0` twice consecutively.
- **T9** `sessions.conf` consumer: replace the 297 `agent-supervisor` and 166 `director` literals.
- **T10** Test-isolation guard: refuse to operate on a session on the default socket that a test fixture created; all shell tests use `TMUX_TMPDIR`.
- **T11** Target-reachability preflight in `heartbeat.sh`, `director-loop.sh`, `quota-watch.sh`: unreachable target → Telegram + non-zero.
- **T12** `restore.sh`: split `--session` (redirect, human-only) from `--only-session` (filter, scheduler-safe).
- **T13** Close #347 properly — `restore.sh` must place claude-print lanes; replace the comment-matching acceptance grep with a placement test.
- **T14** Retire or wire `contest-stop.sh`: PR #390 merged and called from a reachable point, or deleted.

**HOOKS / STANDARD (H)**
- **T15** `check_stop_authorized.sh` (S1).
- **T16** `no_quote_profanity.py` (S4) — `PreToolUse` on `Bash:gh (issue|pr) (create|edit|comment)` and `Write:*.md`.
- **T17** `no_code_in_state.py` (S5) — `PostToolUse` reject `~/.local/state/**` paths that are executable/`.sh`/`.py`.
- **T18** `require_adversarial_review.py` — block `merge`/`push`/`launchctl` without a review verdict for current HEAD.
- **T19** `SessionStart` hook printing the main-ancestry verdict for the session cwd (S2 second half).
- **T20** **Register every hook in `~/.claude/settings.json`.** Single-owner task — no other task edits this file.
- **T21** Edit `agent-dotfiles` #237, #174, PR #55 to remove profanity attributed to Jon. *(Irreversible damage; do first in its group.)*
- **T22** Move `phase-report.sh` and any other `~/.local/state/**` executable into `scripts/supervisor/`, tracked.
- **T23** `reap.sh` + daily plist — branch/worktree ceilings, `git worktree prune` unconditional.
- **T24** Flip `--dangerously-skip-permissions` default to scoped; bypass requires a per-lane flag recorded in the ledger.

**CORPUS (C)**
- **T25** `prompts.provenance` column, NOT NULL, sourced from `promptSource`.
- **T26** Rewrite `itemize_prompts.py`: `kind` and `weight` from deterministic rules; the model may propose `body` text only.
- **T27** SQLite `BEFORE INSERT` trigger on `items`: raise when the joined prompt is interrogative and `weight='hard'`.
- **T28** Repair the 581 contaminated hard items and the 7 paraphrase rows; re-ingest the missing 08-19 messages.
- **T29** Delete the 1,057 rows sourced from `hill90-app` (excluded repo, twice).
- **T30** `link_items.py` — deterministic comparator over `resolved_to` keys; populate `links`.
- **T31** Rename/fix `possibility_count` — it currently counts hard parameters.
- **T32** Wire `update_text_clean` (95.1% of rows untouched); one caller, in the ingest path.
- **T33** CI: corpus verbatim + complete, both directions (S7).
- **T34** CI: `items > 500 AND links = 0` → fail (S8).

**NOTIFICATION / HONEST INSTRUMENTS (N)**
- **T35** `events` consumer + CI orphan test: unnotified rows older than 1h → 0.
- **T36** Report always sends; leads with `MISS: n/30 (N consecutive)`; three misses page.
- **T37** Delete the `NOTIFY-PATH-STALE` fallback; stale path exits 1 and pages through the surviving channel.
- **T38** `watchdog_notify.py:299` — parameterize the hardcoded `inbox-poll` message and threshold.
- **T39** `watchdog_notify.py:336` — bound the `state: stopped` staleness exemption in time.
- **T40** Quota: decay `UNKNOWN`×2 → `UNSAFE`; real stand-down state; blind meter halts dispatch.
- **T41** Health predicate requires `pane_working > 0` or a recorded stand-down. Mutation-verified.

**GUARDS THAT CANNOT FIRE (G)**
- **T42** `ci_gate.py` — rename one of the two `gate:` jobs; workflow-lint test forbidding duplicate job names.
- **T43** `heartbeat.sh:197` — apply the `| tail -1 |` discipline already correct at line 93; pin the reproduction.
- **T44** #325's unreachable test — stop pinning `HEARTBEAT_STALE_AFTER=0` in all three cases.
- **T45** CI: every module under `scripts/supervisor/` has ≥1 non-test importer (S9).

**ARCHITECTURE (A)**
- **T46** ACP: one real lane completes one real task on `ACPTransport`, or `acp_transport.py` is deleted. **No third option.**
- **T47** Chain of command: `role`/`tier`/`parent_lane` in the schema; `dispatch.sh` selects by tier, not by freeness.
- **T48** Per-project tmux sessions restored and held by the reaper's owned-sessions table.
- **T49** AGENTS.md invariant: *a refusal-to-act must name what does act instead, or it is a bug.* Grep test grandfathering the 43 existing `a human should look` sites by count — the number may only go down.

**PRODUCT (P)**
- **T50** `agent-tui` → public.
- **T51** Phase 4 interface work — the first product commit. Agents drive every control before Jon sees it.

### Deferred, named rather than hidden

- **"Do research first, not from training data"** — no hook can distinguish a claim from weights from a
  claim from a page. A `Sources:` block checks paperwork, not honesty. **Not claimed as covered.**
- **"Ask a council before concluding"** — T15 can prove a subagent call happened; it cannot prove the
  reviewer was given a lens it could fail on. Full enforcement needs a reviewer-prompt schema plus an
  assertion that verdicts are sometimes adverse. Partial only.
- **"30 issues per 30 minutes"** = 1,440/day. Measured: 08-17 → 4, 08-18 → 10, 08-19 → 61. **Not
  encoded**, because encoding an unmeetable number manufactures the theatre he is angry about. T36
  reports the real rate every 30 minutes and he sets the number with that in front of him.

---

## Validation Loop

### Level 1 — syntax and static
```bash
shellcheck scripts/supervisor/*.sh scripts/hooks/*.sh
python3 -m py_compile scripts/supervisor/*.py scripts/hooks/*.py
```

### Level 2 — unit / shell suites (CI runs these via unittest discover)
```bash
python3 -m unittest discover -s tests -v
bash tests/supervisor/test_session_reaper.sh
bash tests/supervisor/test_poller_recover.sh
bash tests/supervisor/test_restore.sh
```

### Level 3 — the only test that matters
```bash
tmux kill-session -t agent-supervisor          # deliberate death
sleep 330
tmux has-session -t agent-supervisor && echo RECOVERED   # unattended, no human action
```
Run twice. A single pass is a coincidence.

### Level 4 — mutation checks (a test that cannot go red is decoration)
```bash
# revert T4, confirm test_session_reaper goes red
# add `session.roles = token.roles`-style shortcut, confirm the corpus test goes red
# insert a hard item from an interrogative prompt, confirm the trigger raises
```

---

## Anti-Goals

- **Do not add a 25th detector.** 24 exist and every one is correct. A new one produces a system even
  more articulate about its own death.
- **Do not make the alerting louder.** 88 Telegram messages were delivered on 2026-08-19. He was told
  every nine minutes for two hours.
- **Do not wire `restore.sh` before T12.** Both current invocations are destructive; proven by dry-run.
- **Do not auto-restart lanes.** AGENTS.md invariant 3 is correct: a fresh agent wearing a recovered
  lane's name looks healthy and has none of the context. The **session container** has no continuity to
  fake — that is what the reaper restores, and nothing more.
- **Do not fix `poller-recover.sh` and call it done.** It stops the false success; it repairs nothing.
