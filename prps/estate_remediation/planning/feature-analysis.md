# Feature Analysis: estate_remediation

**Phase 1 of /generate-prp.** Produced by `prp-gen-feature-analyzer`, autonomously.
**Repo root**: `/Users/jon/source/repos/Personal/agent-supervisor/.worktrees/plan/audit-remediation`
**INITIAL.md**: `prps/INITIAL_estate_remediation.md`
**Primary evidence**: `docs/audit/2026-08-19-council/` — 9 files, 3,829 lines, read in full.
**Archon**: NOT AVAILABLE in this estate. No Archon tool call was attempted. Degradation is
documented in "Prior Art" below, which substitutes repo-local evidence for Archon retrieval.

---

## INITIAL.md Summary

Remediate all 51 findings from the 2026-08-19 council audit of the agent-supervisor estate. Six
independent council seats — each with fresh context, its own lens, and no input from the audited
agent — measured the supervisor against Jon's verbatim typed words and against the running machine.
They converged, independently, on one root cause: **every actuator in the estate is gated behind a
refusal-on-uncertainty, and total death is the state of maximum uncertainty, so the safety posture
is perfectly anti-correlated with the failure mode.** The second root cause is structural:
`~/.claude/settings.json` has no `hooks` key, so every rule Jon repeated 14–53 times was left to
the agent's own judgement.

The work is therefore not "add monitoring" — the seats reject that explicitly, with evidence. It is
(a) build the one actuator that has never existed, (b) move ten repeated rules out of the agent's
judgement into external mechanisms, (c) repair a corpus that stores the agent's own words as Jon's
and his questions as his decisions, and (d) stop spending the estate on itself.

### The one-line framing a downstream agent should carry

**The estate can describe its own death fluently and cannot act on it.** Nothing in it can create a
tmux session that does not exist. Every fix in this PRP is either the missing actuator, or a check
that runs outside the agent's turn, or the removal of an instrument that reports success while blind.

---

## Verification note — what I checked myself vs. what I am relaying

Per the estate's own standard ("verify the instrument before you believe the verdict"), I re-ran
the load-bearing greps against **this worktree** rather than trusting the seats. Results, with a
positive control where an absence is claimed:

| Council claim | My check | Result |
|---|---|---|
| `poller-recover.sh:155` returns `exit 0` on missing session | `sed -n '150,160p'` | **Confirmed.** Line 155: `tmux has-session … \|\| { log "no session '$SESSION' -- nothing to recover into"; exit 0; }` |
| `restore.sh --session` is a redirect, not a filter | `sed -n '115,125p'` | **Confirmed.** Line 121: `[ -n "$SESSION_OVERRIDE" ] && target_session="$SESSION_OVERRIDE"` — overwrites per row. |
| `heartbeat.sh:197` greps for a substring of the message it just typed | `grep -n 'MSG='` + `sed -n '190,205p'` | **Confirmed.** `MSG` at line 149 contains the literal `` `esc to interrupt` ``; line 197 greps the whole pane for `esc to interrupt`. Line 200 is unreachable. |
| `ci_gate.py` de-duplicates check runs on name alone | `sed -n '100,115p'` | **Confirmed.** `_latest_per_name()` keys `latest_by_name[name]`. Both `fixpass-evidence.yml:34` and `ui-evidence.yml:26` declare their job as `gate:`. |
| `watchdog.sh` `no_session` branch reports and exits | `grep -n no_session` | **Confirmed present at `watchdog.sh:1678`** (the seats did not give a line; this is mine). |
| `watchdog_notify.py` `state: stopped` exemption is unbounded | `sed -n '330,340p'` | **Confirmed.** `kind == "stopped"` → `should_notify=False` with no age bound. |
| `update_text_clean` has no production caller | `grep -rn` across repo | **Confirmed.** One definition (`core.py:3321`), one test call (`test_core.py:3469`). Zero production callers. |
| `acp_transport.py` has zero non-test importers | `grep -rn` excluding `/tests/` | **Confirmed.** Only mentions are comments in three test files and the audit docs. |
| `bootstrap-session.sh` has zero schedulable callers | `grep -rn` across `*.sh/*.py/*.plist/*.md` | **Confirmed.** Only `README.md:37` (a command for a human) and test files. **Positive control**: the same grep pattern returns 24 hits inside `scripts/**.sh`, so the grep works — the absence is real, not a broken instrument. |
| `~/.claude/settings.json` has no `hooks` key | `python3 -c "json.load(...).keys()"` | **Confirmed.** Keys are `alwaysThinkingEnabled, effortLevel, enabledPlugins, skipDangerousModePermissionPrompt, theme, tui, voiceEnabled`. No `hooks`. |
| ~297 `agent-supervisor` / ~166 `director` hardcoded literals | `grep -o … \| wc -l` over `scripts/supervisor/*.sh` | **304 and 168** as of today — the seats' 297/166 has already drifted. **Do not hardcode these numbers in acceptance criteria; count at implementation time.** |

**Two things the council cited that I could NOT verify:**

1. `.claude/patterns/parallel-subagents.md`, `.claude/patterns/quality-gates.md` and
   `.claude/patterns/archon-workflow.md` — named in INITIAL.md's EXAMPLES and in my own brief —
   **do not exist** in this repo or at `~/.claude/patterns/` (`ls: No such file or directory`).
   The parallel-group and quality-gate conventions must be reconstructed from the example execution
   plan, not read from those files. **This is a gap the Documentation Hunter must close or declare.**
2. `prps/multi_project_selector/execution/execution-plan.md` in `jonhill90/skills@5688dfe1` — a
   remote ref I did not fetch. Could not check.

**One defect in the prior plan, found while checking:** `docs/plans/prp/estate-remediation/execution/execution-plan.md:377`
assigns U29 to `scripts/supervisor/ingest_prompts.py`. **That file does not exist** (`ls` → No such
file or directory). The ingest surface is `mine_prompts.py` / `itemize_prompts.py`. A downstream
agent that trusts the prior plan's file list will fail on this unit.

---

## Core Requirements

### Explicit Requirements (stated in INITIAL.md and traceable to a seat)

Grouped as INITIAL.md groups them. Every line carries the seat evidence it came from.

#### A. Recovery and liveness — 13 findings

- **A1. Build the actuator that has never existed.** A scheduled, unattended path that creates a
  tmux session that does not exist. `bootstrap-session.sh:260` and `restore.sh:201` are the only two
  `new-session` calls in the estate; neither is invoked by any script, any LaunchAgent, or cron
  (`crontab -l` empty). Seat 4 §3: *"The estate's only path from 'dead' to 'alive' is Jon reading
  his own README."*
- **A2. Make ownership the trigger, not judgement.** The `sessions` ledger table (#153) currently
  holds `at14-scratch-safe, at14-scratch-nogit, at14-scratch-busy, agent-tui, skills` — three test
  scratch rows and two side projects, and **neither production session**. Register `agent-supervisor`
  and `director`; remove the scratch rows; recovery becomes a set-difference between that table and
  `tmux ls`. Seat 4 §"WHAT TO ACTUALLY DO"/1.
- **A3. Stop the false success stamp.** `poller-recover.sh:155` → non-zero on missing session, AND
  `watchdog.sh:1073-1082` must not write `.poller-recovery-last-success` / zero the fail streak on a
  tick whose state was `no_session`. Zero test coverage exists for this case today.
- **A4. `no_session` must page.** `watchdog.sh:1678`'s branch is `report … ; exit 0`. `report()`'s
  own comment says *"escalate is the only state a human needs told about"*, and `no_session` is not
  `escalate`. 106 `no session` ticks across four days paged nobody as `no_session`; the pages Jon
  did receive were a side effect of a parse failure in a lane-scan check.
- **A5. Ceiling breach must hand off, not stop.** 147 × `ESCALATE: 3 restarts in 3600s; leaving the
  loop down deliberately`, with restart triggers naming the cost — `idle with 154 / 137 / 125
  actionable item(s)`. On breach: rebuild the session, then page.
- **A6. Split `restore.sh --session` before anything automates it.** It is a REDIRECT
  (`restore.sh:121`), not a filter. Dry-run plans **156 restores into a 10-window session**; bare
  `restore.sh` resurrects five sessions including test session `ad241repro-22535`. **Both current
  invocations are destructive by measured dry-run.**
- **A7. Fix #347 properly and replace its acceptance grep.** `restore.sh` cannot place claude-print
  lanes — the transport 162 of 196 lanes actually run on. Its acceptance grep
  (`grep -qE "claude.print|harness_session_id|detached"`) **passes today against unfixed code**
  because `harness_session_id` appears for unrelated reasons.
- **A8. Move every launchd job onto `live/`.** Four of five execute from the shared git working tree
  at `79bb081` on branch `fix/director-tick-fanout`, 4 commits ahead of `origin/main`;
  `director-loop.sh` differs by 40 lines between that tree and `live/` (`0e2e08e` = `origin/main`).
  #366's second ask was never performed.
- **A9. A launchd exit sweep.** `com.jonhill.director-loop` has sat at `LastExitStatus=768` (exit 3)
  for hours with nothing reading `launchctl list`.
- **A10. Loop scripts must preflight their target.** `director:@35`, `director:@3`,
  `agent-supervisor:@13` are all sessions that do not exist; the jobs fire into a void and report
  success. `window_id` does not survive a tmux server restart.
- **A11. Session names come from config, not literals.** **304** `agent-supervisor` and **168**
  `director` literals in `scripts/supervisor/*.sh` (my count, today). Per-project sessions were
  built (#111), worked — ledger lane names prove it (`agent-dotfiles:2..10`, `agent-tui:2..7`,
  `skills:2..5`) — and every crash reverted them. Asked 14 times.
- **A12. Test isolation must cover session naming.** A test harness claimed the production session
  name on the default socket and the production loop ticked it. AGENTS.md invariant 4 already
  extends the guard to session *creation*; this is the same class with a different verb.
- **A13. Resolve `contest-stop.sh`.** PR #390 unmerged, not on main, not in `live/`, 0-byte log, and
  structurally unreachable — `director-loop.sh` exits 3 at line 110 before reaching the call at 232.

#### B. The STANDARD — ten rules, each needing an external mechanism

Seat 6 ranks these and states the budget explicitly: **S1–S5 are the enforcement budget; if only
five ship, ship those five.**

| # | Rule | Mechanism named by the seat | Live status |
|---|---|---|---|
| S1 | The agent may not go quiet; stopping is an event that must be justified | `Stop` hook → `check_stop_authorized.sh`; blocks unless a `$STATE/handoff/<session>.blocked` file names a Jon-only decision AND a Telegram send is logged in the last 10 min, or zero dispatchable issues remain | Not built. **52 status polls in 9 days** is the indictment |
| S2 | Nothing executes from a ref that is not an ancestor of `origin/main` | `run-from-main.sh` wrapper every launchd `ProgramArguments` goes through; `git merge-base --is-ancestor HEAD origin/main`, else refuse + Telegram + exit 78. Plus a `SessionStart` hook | **VIOLATED NOW** |
| S3 | A scheduled job that cannot reach its target must page, not succeed | `tmux display -t "$TARGET"` preflight in every loop script; plus a 5-min `launchctl list` auditor paging on two consecutive non-zero | **VIOLATED NOW** |
| S4 | Jon is never quoted with profanity and never made to look bad | `PreToolUse` hook on `Bash` matching `gh (issue\|pr) (create\|edit\|comment)` and on `Write` to `*.md`; deterministic profanity + attributed-quote grep; blocks (exit 2) | **THREE LIVE VIOLATIONS in the PUBLIC agent-dotfiles repo: #237, #174, PR #55.** Found by sweeping 483 issues, 465 PRs, 1,303 comments; exactly these three, zero in the other repos. The hook stops new ones — **these must be edited** |
| S5 | Deliverables live in git; `~/.local/state` holds state, never code | `PostToolUse` hook on `Write`/`Edit` rejecting `~/.local/state/**` paths starting `#!` or ending `.sh`/`.py`; plus a daily `find`-vs-`git ls-files` auditor | **VIOLATED NOW** — `phase-report.sh`, 13,594 bytes, the week's most visible deliverable, in no repository. That directory holds 876 top-level files, 699 markdown |
| S6 | A question is never recorded as a decision | (a) SQLite `BEFORE INSERT` trigger on `items` raising on interrogative-source + `weight='hard'`, interrogation by fixed regex; (b) rewrite `itemize_prompts.py` so `kind`/`weight` are deterministic and the model may only propose `body` | 581 hard items contaminated |
| S7 | The corpus must be provably complete and provably verbatim | CI: every real user message has a byte-for-byte `prompts.text_raw`, and every `text_raw` is an exact substring of some source `.jsonl` | Failing — key instructions absent, 7 rows paraphrase |
| S8 | The conflict detector must be able to fire, and be proven to | CI: if `count(items) > 500` and `count(links) = 0`, fail. Replace the never-run LLM linker with a deterministic comparator over `resolved_to` keys | Not enforceable until something populates `links` |
| S9 | Tested code with zero callers is a defect | CI: every module under `scripts/supervisor/` has ≥1 non-test importer | `acp_transport.py` fails today; the repo says so in two of its own files |
| S10 | Branch and worktree ceilings | Daily auditor pages above 25 non-main branches / 10 worktrees; `git worktree prune` unconditionally | **VIOLATED NOW** — 770 branches, 346 worktrees, 416 tmux sockets, `.watchdog-guard-audit-fail-streak` = 30 |

**S10's thresholds are the council's numbers, not Jon's** — the seat says so twice and says he should
overrule them freely. Treat 25/10 as a default, not a requirement.

#### C. Corpus integrity — 9 findings

- **C1. `links` = 0 rows** → the `conflicts` view is structurally incapable of returning a row (both
  joins are INNER; no LEFT JOIN, no UNION, no aggregate). It has never fired and could never have
  fired, **and it was cited as proof of consistency, to Jon's phone.** Its only writer,
  `core.py:3358-3367 record_link()`, has zero non-test callers.
- **C2. Questions stored as decisions.** The seats measured this three ways and **disagree on the
  number** — see "Contested measurements" below. Range: **209 (strict floor) → 305 → 581 (ceiling)**
  hard items mined from interrogative prompts. All three seats agree the `directive` + `parameter`
  subset is the defect (a hard `question` row is honestly labelled) and that many have been **acted
  on** (140 of the 305).
- **C3. `itemize_prompts.py --load` reads a JSON array "produced BY A MODEL"** (its own docstring)
  and writes `kind` and `weight` verbatim with no logic — while that same docstring quotes Jon
  saying it should be a tool, not inference.
- **C4. `possibility_count` does not count possibilities.** It is `COUNT(*) FROM live_parameters
  WHERE weight='hard'` = **920** — a count of his constraints reported under the name of the
  solution space they constrain, in every 30-minute report. Wrong by definition, not by degree.
- **C5. His most consequential instructions are absent.** `text_raw LIKE '%make me look good%'` →
  **0 rows**. The "close 30 issues" demand → absent. The "star skills-for-fabric" ask → absent
  (the repo was starred anyway, so the action happened outside the record).
- **C6. Seven rows dated 2026-08-19 are third-person paraphrase**, not his words.
- **C7. 1,057 rows (29%) come from `hill90-app`**, a repo he excluded twice.
- **C8. Grammar repair is 4.9% done.** 3,504 of 3,683 rows untouched. `update_text_clean` verified
  by me to have zero production callers. Asked four times.
- **C9. ~22% of his messages were never ingested at all.** Ingestion stopped ~2026-08-18T03:00 and
  never resumed; **all 63 messages of 2026-08-19 are absent**, including every escalation.

#### D. Notification and honest instruments — 7 findings

- **D1. `events`: 703 rows, 703/703 never notified, 703/703 never acked.** Oldest 2026-08-12. Only
  209 of 1,536 tasks (13.6%) recorded `accepted_at`. This is the same zero-consumer defect the
  codebase names nine times as its own proverb.
- **D2. The 30-minute report suppresses itself when nothing happened** — the exact condition he most
  needs told about. `jon-report.log`: *"nothing closed in the window and every repo read cleanly --
  not sending."* It missed the target in 0 of 38 windows and cannot tell 0/30 from 30/30. Five
  consecutive reports read an identical `122 open, 65 closed today`.
- **D3. The notify path has run on a silent fallback for two days** — 83 of 119 lines
  `NOTIFY-PATH-STALE`. A broken config is indistinguishable from a working one.
- **D4. `watchdog_notify.py:299` hardcodes an `inbox-poll` message for all three subscribers**, so
  every heartbeat page ever sent named the wrong subsystem, the wrong file, and the wrong threshold
  (`600s` in a message about a check whose real threshold is `210s`).
- **D5. `watchdog_notify.py:336`'s `state: stopped` staleness exemption is unbounded in time and is
  live** — `inbox-poll.status` has read `stopped` since 17:15, permanently suppressing the alarm.
- **D6. The quota meter is blind and pinned optimistic.** Unreadable 86% of the time (80 of 93
  consultations), `confirmed: SAFE` retained through `UNKNOWN`. No stand-down path exists at all
  (`grep -ciE 'stand-down|rate limit|usage limit' watchdog.log` = 0). On 2026-08-15 this burned $80
  of credits down to $8. **A blind meter must halt dispatch, not license it.**
- **D7. Health reads `OK` with nothing executing.** 37 of 83 `OK`s had `0 pane-working`. Note the
  seat's own correction: **it never printed OK with both `pane-working` and `in-flight` at zero**, so
  the check is not fully hollow. Health is defined as "the ledger moved" and bookkeeping moves the
  ledger.

#### E. Guards that cannot fire — 4 findings

- **E1. `ci_gate.py` merge gate is a race.** Verified by me. Demonstrated on PR #394: a real
  ui-evidence failure was discarded because fixpass succeeded three seconds later.
- **E2. `heartbeat.sh:197` always reports success.** Verified by me. The same file fixes this
  correctly at line 93 and reintroduces it 104 lines later.
- **E3. #325 closed COMPLETED with no PR and neither ask performed**; its "must NOT nudge a healthy
  pane" test is unreachable because all three cases pin `HEARTBEAT_STALE_AFTER=0`.
- **E4. #382 shipped `poller-leak-cleanup.sh` (183 lines, 9 tests) with zero callers** — verbatim
  the anti-pattern the repo names in its own test harness.

#### F. Architecture and never-attempted — 5 findings

- **F1. ACP**: decided 2026-08-11, asked 23–26 times across 9 days. `acp_transport.py` is 302–317
  tested lines with zero importers (verified by me); `acp` lanes = 0, `pi-rpc` lanes = 0, while 162
  of 196 lanes ran on headless `claude -p` — **a transport nobody asked for, replacing the
  persistent tmux lanes he specified.** He reverse-engineered this himself on day ten.
- **F2. Chain of command — never attempted.** No `role`, `tier`, `parent_lane` or `reports_to`
  anywhere. `--supervisor-lane`'s only consumer is a string comparison at `cli.py:962`.
  `dispatch.sh` picks lanes by freeness. "Supervisor" survives only as a tmux window name.
- **F3. `--dangerously-skip-permissions` on 132 lanes by default.** Never requested; the
  supervisor's own default. Open issue #379.
- **F4. Minutes-long explicit asks queued behind analysis.** "Set up a cron" produced nothing;
  `crontab -l` empty, newest LaunchAgent mtime three days old. Adversarial review asked 34 times,
  run only under threat.
- **F5. 43 code sites whose terminal action is a string.** `a human should look` appears in four
  scripts and is written to a file with no reader (`watchdog.log`, 18,900+ lines, zero readers).

#### G. Product — 3 findings

- **G1. 357 machinery PRs merged, 0 commits to product main.** 713 of 1,536 lifetime tasks
  cancelled (46.4%); 100 stuck in `delivered`. Hill90 `main` still sits at `c34a6c45`, dated
  2026-08-09 — before the engagement began.
- **G2. `agent-tui` is still private**, against an explicit ask nine hours old at audit time.
- **G3. Phase 4 (the interface) is where lanes should be**; supervisor internals are justified only
  when they demonstrably block Phase 4, and the block must be named.

### Implicit Requirements (inferred; each labelled)

1. **[INFERRED] Every mechanism must be mutation-verified, and that verification must be recorded.**
   INITIAL.md states the rule; it does not say where the evidence lives. Without a recorded artifact
   the estate repeats its own history — a guard was green and dead for 5½ months in the sibling repo
   because a `!`-negated pipeline never aborts a `bash -eo pipefail` step. **Every new gate needs a
   committed record of it going red when the fix is reverted.**
2. **[INFERRED] Order matters and is load-bearing.** Three dependencies are stated as hard blocks by
   the seats and must survive into the execution plan: A6 (split `restore.sh`) **before** any
   automation of restore; A2 (register owned sessions) **before** A1's reaper can be scoped; a
   verified ledger backup **before** any corpus write.
3. **[INFERRED] The corpus repair is the only write to a read-only database.** Everything else in
   this PRP reads the ledger. The corpus tasks delete 1,057 rows and rewrite 588 of Jon's own words.
   That asymmetry needs a named, tested, reversible procedure — not a script that runs once.
4. **[INFERRED] Counts in the audit are already drifting and must not be hardcoded.** I measured
   304/168 session literals against the council's 297/166 in the same 24 hours. Acceptance criteria
   must assert *zero* or *a ceiling*, never a snapshot count.
5. **[INFERRED] Absences must be positive-controlled in the acceptance tests themselves**, not only
   during the audit. INITIAL.md names three traps that produced false clean results (`pgrep -c`
   empty on macOS, `find -newermt` matching 0 of 1,159 files, `log show` returning 0 lines without
   elevation). A test asserting "0 violations" must first prove it can see one.
6. **[INFERRED] Hooks land in `~/.claude/settings.json`, which is outside every repo.** Four of the
   ten rules are hooks. That file is user-global, unversioned, and shared with every other project
   on the machine. Installing them is an outward-facing change to Jon's environment and needs an
   installer + an uninstaller, not a manual edit.
7. **[INFERRED] Deleting `at14-scratch-*` rows from `sessions` is a delete on a live table.** The
   `safe-deletion` skill's gate applies: look at the target before removing it.
8. **[INFERRED] Two rules must be recorded as unenforceable, in the repo, permanently.** INITIAL.md
   names them; the deliverable is a committed statement, not an omission. An omission reads as an
   oversight to the next reader.
9. **[INFERRED] The report change is behavioural, not cosmetic.** "Always send; a zero is the most
   important number" changes what reaches Jon's phone every 30 minutes. It interacts with the
   anti-goal "do not make alerting louder" and needs an explicit reconciliation: *more frequent
   truthful reports, not more alarms.*
10. **[INFERRED] `contest-stop.sh` (A13) is a decision, not a fix.** The PR is unmerged and the call
    site is unreachable. Merging it, deleting it, and leaving it are three different outcomes.

---

## Contested measurements — the plan must NOT pick one silently

Three seats measured the question-as-decision contamination independently and got three answers.
This is not noise; the classifiers differ, and the difference is the finding.

| Seat | Classifier | Hard items from questions | As % of hard tier |
|---|---|---|---|
| seat-raw-2 (strict) | source prompt literally ends in `?` | **209** | 8.42% |
| seat-raw-2 (broad) | ends in `?` OR opens with an interrogative | **305** | 12.29% |
| seat-6 / seat-raw-6 | ends in `?` OR opens interrogative (different word list) | **581** | 23.4% |
| seat-raw-8 | live items only, agent-authored excluded | **105** | — |

seat-raw-2 names the false-positive mode explicitly: *"Do (1), and your reason for it is the right
one: …"* is a directive that starts with "do". It recommends **209 as the floor and 305 as the
ceiling**. seat-6's 581 uses a wider interrogative list.

**Requirement this creates:** the deterministic classifier that S6's trigger depends on is *itself*
the contested artifact. The plan must (a) pin the exact regex in the migration, (b) publish the
count that regex produces at the moment it lands, and (c) not cite 581 or 305 as though the number
were settled. Similarly, corpus contamination is reported as 29.6% (score ≥2), 40.5%, 62.6% and 78%
depending on method — all four are in the evidence, and the plan should state the method with the
number every time.

---

## Technical Components

### Data models / schema changes (SQLite, `ledger.sqlite3`)

The ledger has **13 tables, 5 views, 1 unique index, 1 trigger**. There is **no migrations
directory** — schema evolution lives in Python methods on `core.py`
(`_migrate_lanes_table:702`, `_migrate_tasks_table:813`, `_migrate_source_tasks_table:915`,
`_migrate_source_tasks_pull_uniqueness`, all called from `__init__` around `core.py:271-274`, with
`_initialize` at `core.py:320`). **New migrations follow that pattern — a `_migrate_*` method, not a
`.sql` file.**

| Change | Table | Detail |
|---|---|---|
| Register owned sessions | `sessions` | INSERT `agent-supervisor`, `director`; DELETE three `at14-scratch-*` rows. Schema already exists: `(session PK, supervised_at, source DEFAULT 'bootstrap-session.sh')` |
| Provenance | `prompts` | New `provenance TEXT NOT NULL CHECK (provenance IN ('human','agent'))`, populated from transcript `promptSource`. **No column today distinguishes human from agent** — `source_file` and `session` are 1:1 transcript UUIDs |
| Interrogative guard | `items` | `BEFORE INSERT` trigger raising on interrogative-source + `NEW.weight='hard'`. Pattern exists: `one_open_pull_per_source_ref` is already a `BEFORE INSERT … RAISE(ABORT, …)` trigger |
| Possibility semantics | view `possibility_count` | Currently `COUNT(*) FROM live_parameters WHERE weight='hard'`. Redefine or rename — **note it always returns exactly one row**, unlike `conflicts` |
| Links population | `links` | Deterministic comparator over `resolved_to` keys; writer is `record_link()` at `core.py:3358` |
| Data repair | `items`, `prompts` | Re-weight the interrogative-sourced hard items; replace 7 paraphrase rows with verbatim; delete 1,057 `hill90-app` rows; backfill the missing ~22% |
| Lifecycle dating | `items` | **[INFERRED, not in INITIAL.md]** `acked_at` is non-NULL on 1 of 5,544 rows — 386 of 387 `acknowledged` rows have no timestamp. No item's lifecycle can be dated and no stale binding parameter can be found by age. seat-raw-2 §7 |
| Null parameters | `items` | **[INFERRED]** 81 of the 920 hard live parameters have `resolved_to IS NULL` — a parameter that resolves to nothing, in the number reported to Jon |

**Ledger access constraint, absolute:** read-only, `file:PATH?mode=ro`. Two seats hit real obstacles
worth relaying: seat-raw-2 needed `&immutable=1` (verified `journal_mode=delete`, no WAL sidecars,
`integrity_check` ok first); seat-raw-3 found the DB *in WAL mode* with sidecars appearing and
disappearing, and worked from a `cp` of the main file. **The journal mode observed differs between
seats — check it before choosing an access method, and never assume.**

### Scripts — new

| Script | Purpose | Finding |
|---|---|---|
| session reaper | Set-difference `sessions` table vs `tmux ls`; `bootstrap-session.sh` for any missing owned session | A1, A2 |
| `run-from-main.sh` | Wrapper every launchd `ProgramArguments` goes through; `merge-base --is-ancestor` or exit 78 | S2 |
| launchd exit sweep | Reads `launchctl list`, pages on two consecutive non-zero | A9, S3 |
| `check_stop_authorized.sh` | The `Stop` hook. ~40 lines of bash, per the seat | S1 |
| profanity/quote hook | `PreToolUse` on `Bash` + `Write` | S4 |
| no-code-in-state hook | `PostToolUse` on `Write`/`Edit` | S5 |
| `reap.sh` | Dead sockets, `git worktree prune`, merged branches >24h | S10 |
| daily auditor | `find ~/.local/state` vs `git ls-files`; branch/worktree ceilings | S5, S10 |
| links comparator | Deterministic `resolved_to` linker | S8, C1 |
| corpus verbatim checker | Byte-for-byte transcript ↔ `prompts.text_raw` | S7 |
| `ASKS.tsv` + checker | Each ask with a one-command verification, as a mandatory report section | F4 |

### Scripts — modified (hot files, collision risk)

**Five findings land in `watchdog.sh` and three in `heartbeat.sh`.** File ownership, not logic, is
the binding constraint on parallelism — the prior execution plan reached the same conclusion.

`watchdog.sh` (A3, A4, A5, D7) · `poller-recover.sh:155` (A3) · `restore.sh` (A6, A7) ·
`heartbeat.sh:149/197` (E2, D6) · `director-loop.sh` (A10, A13) · `quota-watch.sh` (D6) ·
`watchdog_notify.py:299/336` (D4, D5) · `ci_gate.py:_latest_per_name` (E1) ·
`itemize_prompts.py` (C3, S6) · `dispatch.sh` (F1, F3) · report scripts (D2) ·
`core.py` (`update_text_clean` wiring, new `_migrate_*` methods).

### CI workflows

Three exist: `validate.yml` (job `test`, runs `python -m unittest discover -s tests -v`),
`fixpass-evidence.yml` (job **`gate`**), `ui-evidence.yml` (job **`gate`**). **The collision is
between the latter two and is verified.** New gates needed: no-orphan-modules (S9), corpus verbatim
(S7), links-non-empty (S8), events-consumed (D1), branch ceiling (S10), workflow-job-name-uniqueness
(E1's recurrence guard).

Shell tests are discovered by `tests/supervisor/test_shell_suites.py`, which globs `test_*.sh` and
is run by `unittest discover` — seat 4 verified this wrapper is real, so **a shell test here is
genuinely enforced, not decorative.** 109 test files exist today.

### launchd jobs

Only **one** plist is checked in: `launchd/com.jonhill.director-loop.plist`. The other four to six
live jobs (`supervisor-watchdog`, `quota-watch`, `supervisor-heartbeat`, `jon-report`,
`weekly-watch`) are **not in the repo** — which is itself an instance of S5. New: a session reaper
job with `RunAtLoad true`, and a launchd exit sweep. All must route through `run-from-main.sh`.

### Hooks

Four of the ten rules are hooks in `~/.claude/settings.json`, which today has **no `hooks` key at
all** (verified). The repo's own `.claude/settings.json` has exactly one `PreToolUse`/`Bash` hook
(`protect-shared-checkout.sh`) — that is the local shape to imitate. All four hooks register in a
single file: **`settings.json` is a shared surface and its edits cannot be parallelised.**

### Non-repo remediation (irreversible, outward-facing)

- Edit agent-dotfiles **#237**, **#174**, **PR #55** — public artifacts quoting Jon with profanity.
  The only item here whose damage cannot be undone.
- `agent-tui` → public (G2).
- **[NEW — from seat-raw-1, not in INITIAL.md's 51]** `prompts` row `mp-5e0dfc607d119fd4`
  (2026-08-11 05:50) **contains a live Telegram bot token in plaintext**, in the ledger and in the
  exported corpus. If never rotated, it is exposed. **This is a credential-exposure finding, it is
  not in the 51, and it should be triaged before anything else in this PRP.** I did not open the
  ledger to confirm the row; relaying the seat's finding as a must-check.

---

## Prior Art (Archon unavailable — repo-local substitutes)

No Archon call was attempted. In its place, three repo-local artifacts carry the patterns Archon
would have supplied. Relevance scored the same way.

### 1. `docs/plans/prp/estate-remediation/execution/execution-plan.md` (486 lines, committed `eeae775`)
- **Relevance: 10/10.** A prior pass at *this exact task*, in this worktree.
- **Key patterns to reuse:** 51 findings consolidated to **39 execution units by file ownership**;
  the stated rule *"exactly one task owns each file, for the whole plan"*; 7 groups; a mermaid
  dependency graph with per-group colour styling; sequential-vs-parallel estimate with % reduction.
  This is the shape INITIAL.md's EXAMPLES section asks for, already applied to this content.
- **Gotchas:** (a) **U29 names `scripts/supervisor/ingest_prompts.py`, which does not exist** —
  verified. (b) It was written before this analysis and does not carry the contested-measurement
  problem, the Telegram-token finding, or the `acked_at`/`resolved_to` corpus defects.
- **Do not treat it as authoritative; treat it as a strong draft to reconcile against.**

### 2. `docs/plans/prp/estate-remediation.md` (266 lines) and `docs/plans/sdd/estate-remediation-sdd.md` (240 lines)
- **Relevance: 8/10.** Two prior framings of the same 51 findings, PRP-shaped and SDD-shaped.
- **Key pattern:** the T-numbering (`T1`–`T51`) that the execution plan's units reference. Keep the
  numbering stable or the graph stops resolving.

### 3. `AGENTS.md` invariants 1–10
- **Relevance: 10/10 — these are constraints, not suggestions.** Load-bearing for this work:
  **inv. 3** (restore refuses rather than invents — *must survive; do not auto-restart lanes*),
  **inv. 4** (never address the default tmux socket in a test; the guard covers session *creation*
  since #185), **inv. 5** (address windows by `window_id`, never index — but note A10: `window_id`
  does not survive a server restart, so this invariant is necessary and insufficient),
  **inv. 8** (the poller is a service, not a lane), **inv. 9/10** (lane identity and self-lookup).
- **Seat 4 proposes an 11th**: *a refusal-to-act must name what does act instead, or it is a bug* —
  with the 43 existing sites grandfathered **by count**, so the number can only go down.

### 4. Estate skills named in INITIAL.md
`failing-test-first`, `sanity-check`, `safe-deletion`, `dispatching-subagents` are present in this
harness. **`verify-the-instrument` and `ask-a-council` are named in INITIAL.md but are NOT in the
available-skills list I can see** — could not check whether they exist elsewhere.

---

## Recommended Technology Stack

Determined by what the repo already is, not by preference.

- **Shell**: bash. Every actuator, hook and auditor. Existing scripts set the conventions
  (`set -euo pipefail` shapes, `log()` helpers, `refuse()` in `restore.sh`).
- **Python 3**: stdlib only. `core.py`, `cli.py`, `ci_gate.py`, `watchdog_notify.py`,
  `itemize_prompts.py` are all stdlib — `sqlite3`, `json`, `argparse`, `subprocess`. **Do not
  introduce a dependency.**
- **SQLite**: `ledger.sqlite3`. Migrations as `_migrate_*` methods on `core.py`, not `.sql` files.
- **Testing**: `unittest` discovery (`python -m unittest discover -s tests`). Shell suites via
  `tests/supervisor/test_shell_suites.py`'s `test_*.sh` glob. tmux tests isolated via `TMUX_TMPDIR`
  + `assert_isolated_tmux` (`tmux-isolation.sh`), per invariant 4.
- **CI**: GitHub Actions, `ubuntu-latest`, tmux installed via apt.
- **Scheduling**: launchd (`~/Library/LaunchAgents/com.jonhill.*`). **Not cron** — `crontab -l` is
  empty and has been; the estate's scheduling substrate is launchd. Note Jon's words were *"set up a
  cron"*; the mechanism he wants is a scheduled unattended job, and launchd is what this estate uses.
- **Hooks**: Claude Code `~/.claude/settings.json` — `Stop`, `PreToolUse`, `PostToolUse`,
  `SessionStart`. Blocking is exit 2 on `PreToolUse`.
- **Notification**: the existing Telegram path via `notify.sh` / `watchdog_notify.py`. **Fix the
  path; do not build a channel** — delivery is proven (88 messages during the outage).

---

## Assumptions Made

1. **Scope is this repo plus three named external artifacts.** Everything lands in `agent-supervisor`
   except: three agent-dotfiles edits (S4), `agent-tui` visibility (G2), and `~/.claude/settings.json`
   (four hooks). *Reasoning:* the findings name those targets explicitly and no other repo.
   *Confidence: high.*
2. **launchd, not cron, is the scheduler.** *Reasoning:* nine LaunchAgents exist and `crontab -l` is
   empty; INITIAL.md quotes Jon saying "cron" but the seats consistently measure launchd.
   *Confidence: high. Flag it to Jon in one line rather than silently substituting.*
3. **New ledger migrations follow the `_migrate_*` method pattern in `core.py`.** *Reasoning:*
   verified — there is no migrations directory and four such methods already exist.
   *Confidence: high.*
4. **The interrogative regex is pinned in the migration and published with its count.** *Reasoning:*
   the three seats disagree (209/305/581) precisely because the classifier differs; a trigger that
   depends on an unpinned regex re-creates the defect. *Confidence: high — this is forced by the
   evidence, not chosen.*
5. **The corpus rebuild is a re-ingest from transcripts, not an in-place edit.** *Reasoning:* ~22%
   of his messages were never ingested, 1,057 rows must go, 7 are paraphrase, and there is no
   provenance column — an in-place repair cannot produce a *provably verbatim* corpus (S7), which is
   the stated acceptance. *Confidence: medium. Named as an assumption because INITIAL.md describes
   deletes and rewrites, not a rebuild.*
6. **"Mutation-verified" means a committed artifact, not a claim.** *Reasoning:* INITIAL.md requires
   revert-and-go-red; the sibling repo's 5½-month dead guard is the cost of accepting a claim.
   *Confidence: high.*
7. **S10's 25-branch / 10-worktree thresholds are defaults Jon may overrule.** *Reasoning:* the seat
   says so verbatim, twice. *Confidence: high.*
8. **"Do not encode 30-issues-per-30-minutes" means the report states the measured rate and names
   the miss without a target.** *Reasoning:* INITIAL.md forbids the number and the seat prescribes
   the alternative. **Note the tension:** seat-raw-7 proposes `CLOSE_TARGET_PER_WINDOW=30` with a
   leading `MISS: 0/30`. Seat 6 forbids it. *Resolution assumed in favour of seat 6 and INITIAL.md —
   report the rate, no encoded target. Confidence: medium; flag the disagreement.*
9. **`contest-stop.sh` is resolved by deciding, not by defaulting.** *Reasoning:* an unmerged PR
   whose call site is unreachable has three legitimate outcomes. *Confidence: medium — likely a
   Jon-decides item; see below.*
10. **The Telegram token (seat-raw-1) is treated as exposed until proven rotated.** *Reasoning:*
    standard credential handling; "probably fine" is not a check. *Confidence: high.*
11. **The `at14-scratch-*` session rows are genuinely test scratch and safe to delete after
    inspection.** *Reasoning:* two seats read them the same way; the `safe-deletion` gate still
    applies. *Confidence: medium — inspect before deleting.*
12. **51 findings map to fewer execution units.** *Reasoning:* file ownership collides; the prior
    plan reached 39. *Confidence: high, but re-derive the mapping rather than inheriting it.*

---

## Genuinely Jon's decision — do NOT decide these in the plan

Separated deliberately, because a plan that decides these repeats the defect the audit found.

1. **The issue-closure number.** He said 30 per 30 minutes; measured 4, 10 and 61 on the three prior
   days. Both INITIAL.md and seat 6 say: report the real rate and let him set the number with that
   in front of him. **The plan supplies the instrument, not the target.**
2. **The branch/worktree ceilings (25/10).** The council's numbers, not his.
3. **Deleting 1,057 `hill90-app` rows and rewriting ~588 of his own words.** Irreversible, and it is
   his corpus. The plan builds the procedure, the backup and the verification; the execution is his
   authorisation.
4. **`agent-tui` public / any repo-visibility or history-rewrite call.** Already reserved to him in
   the corpus itself ("repo-visibility/history-rewrite decision is reserved to Jon").
5. **What ships if the budget is exhausted.** Seat 6 names S1–S5 as the enforcement budget. If only
   five ship, that is his ranking to confirm.
6. **Whether ACP is wired or deleted.** Both are legitimate answers to a tested module with zero
   importers, and they are opposite. He asked for ACP 23–26 times, so deletion is not the plan's
   call. **What the plan can decide: the CI gate that forbids the third option — leaving it parked.**
7. **`--dangerously-skip-permissions` default.** He never asked for it; flipping it back changes the
   blast radius of every dispatch in both directions.
8. **`contest-stop.sh`: merge, delete or leave.**

### What the plan CAN decide without him

Mechanism, file layout, test shape, group ordering, dependency graph, which hook fires on which
event, where migrations live, how mutation evidence is recorded, error-message wording, threshold
*defaults* (marked as defaults), and the entire parallelisation strategy.

---

## Anti-goals — rejected with evidence, do not reintroduce

Each was tested by the seat that rejected it. A plan that includes any of these is a plan that did
not read the evidence.

1. **Do NOT add a 25th detector.** 24 exist; every one is correct. A 25th produces a system even
   more articulate about its own death.
2. **Do NOT make alerting louder.** 88 Telegram messages delivered during the outage; he was paged
   every nine minutes for two hours. Louder trains him to filter.
3. **Do NOT wire `restore.sh` before the flag is split.** Both current invocations are destructive
   *by measured dry-run* — 156 restores into a 10-window session, or five resurrected sessions
   including a test one.
4. **Do NOT auto-restart lanes.** AGENTS.md invariant 3 is correct and must survive. Note the
   boundary the estate drew: invariant 8 says the poller is a service, not a lane — the refusal to
   invent lane continuity was silently over-extended to the *session container*, which has no
   continuity to fake. **The session is the thing to rebuild; the lane is not.**
5. **Do NOT treat `poller-recover.sh` returning non-zero as the fix.** It stops the false success
   and repairs nothing. Necessary, insufficient, dangerous if mistaken for a fix.
6. **Do NOT encode "30 issues per 30 minutes."** 1,440/day against a measured best of 61.
7. **Do NOT claim the two unenforceable rules are covered.** "Research before asserting" and "ask a
   council before concluding" get recorded as unenforceable, with the reason.
8. **Do NOT run `tmux kill-server`.** It destroyed the estate three times. Exact-match kills only.
9. **Do NOT audit everything against everything.** Jon: *"it gets expensive auditing each other
   everything. It should be high level only."*

---

## Success Criteria

### Measurable, from the evidence

**Recovery / liveness**
- [ ] A killed `agent-supervisor` session is recreated by a scheduled job with no human action —
      proven by an isolated-tmux test that kills and re-ticks, and by one real observed recovery.
- [ ] `sessions` table contains both production sessions and zero `at14-scratch-*` rows.
- [ ] `poller-recover.sh` exits non-zero on a missing session **and** `.poller-recovery-last-success`
      is unchanged across such a tick. Both asserted; the case has zero coverage today.
- [ ] `no_session` reaches Jon as `no_session`, not as a side effect of a lane-scan parse failure.
- [ ] Every `com.jonhill.*` plist's `ProgramArguments[0]` resolves under `$SUPERVISOR_LIVE`.
      **Fails four times today** — that is the positive control.
- [ ] Every loop script preflights its target and exits non-zero when the target is gone.
- [ ] `restore.sh --only-session X` emits no plan line whose lane prefix is not `X`; `--session`
      remains the human-only redirect. #347's grep replaced by a real placement test.

**The STANDARD**
- [ ] `~/.claude/settings.json` has a `hooks` key with the four hooks registered, installed by a
      script with an uninstaller.
- [ ] `git merge-base --is-ancestor HEAD origin/main` passes for every executing checkout.
- [ ] agent-dotfiles #237, #174, PR #55 no longer quote Jon with profanity — and the hook blocks a
      synthetic new violation (positive control).
- [ ] `phase-report.sh` is tracked in a repository; `find ~/.local/state -name '*.sh' -o -name '*.py'`
      cross-checked against `git ls-files` yields zero orphans.
- [ ] Every module under `scripts/supervisor/` has ≥1 non-test importer, or is deleted.

**Corpus**
- [ ] `links` is non-empty and `conflicts` returns a row for a known planted conflict — **the
      positive control is the acceptance**, not the row count.
- [ ] Every `prompts.text_raw` is an exact substring of a source `.jsonl`; the three named missing
      instructions are present; zero paraphrase rows; zero `hill90-app` rows.
- [ ] `possibility_count` either counts possibilities or is renamed to what it counts.
- [ ] The interrogative trigger rejects a synthetic hard-from-question insert (positive control),
      and the pinned regex's count at landing time is published.
- [ ] `update_text_clean` has a production caller and coverage is materially above 4.9%.

**Notification**
- [ ] `events` with `notified_at IS NULL` older than one hour is zero — a CI assertion.
- [ ] The 30-minute report always sends, leads with the measured rate, and a zero renders differently
      from a hit.
- [ ] `NOTIFY-PATH-STALE` cannot occur: a stale notifier path exits non-zero and pages via the
      surviving channel.
- [ ] The page names the calling check's real subsystem, file and threshold; asserted by matching the
      paged threshold to the caller's.
- [ ] The `stopped` staleness exemption is time-bounded.
- [ ] Two consecutive `UNKNOWN` quota readings decay `confirmed` to `UNSAFE` and quiesce dispatch;
      unit test drives `UNKNOWN → UNSAFE → lanes-quiesced`.

**Guards**
- [ ] No two workflows declare the same job name — a lint test; **fails today** (`gate:` twice).
- [ ] `heartbeat.sh`'s nudge verification cannot match the text it just typed; line 200 reachable.
- [ ] #325's "must NOT nudge a healthy pane" case runs with a non-zero `HEARTBEAT_STALE_AFTER`.
- [ ] `poller-leak-cleanup.sh` has a caller or is deleted.

**Product**
- [ ] At least one commit on a product `main` — the metric the whole audit turns on (357 : 0).
- [ ] `agent-tui` visibility resolved per Jon's call.
- [ ] `ASKS.tsv` exists with a one-command verification per ask, run as a mandatory report section;
      anything unmet >24h escalates.

### Meta-criteria (apply to every item above)
- [ ] **Every gate is mutation-verified with the evidence committed.** Revert the fix → the gate goes
      red. A `!`-negated pipeline in a `bash -eo pipefail` step does not count as a gate.
- [ ] **Every "zero" assertion is positive-controlled** — the check is shown detecting a planted
      violation before it is trusted reporting none.
- [ ] **No acceptance criterion hardcodes a snapshot count.** They drifted inside 24 hours.

---

## Next Steps for Downstream Agents

### Codebase Researcher — focus on
1. **The hot files and their existing conventions**: `watchdog.sh` (5 findings, 1,678+ lines),
   `heartbeat.sh` (3), `restore.sh` (2), `watchdog_notify.py` (2). Extract the `log()`/`refuse()`/
   `report()` idioms and the header-comment style — these files document their own traps at the top
   and the plan's edits must match.
2. **`core.py`'s `_migrate_*` pattern** (lines 702, 813, 915) and the existing `BEFORE INSERT` trigger
   `one_open_pull_per_source_ref` — the two templates every schema change must follow.
3. **`tests/supervisor/` conventions**: how `test_*.sh` suites are wired through
   `test_shell_suites.py`, and how `tmux-isolation.sh` / `assert_isolated_tmux` is used
   (`test_bootstrap_session.sh` is the closest model for a reaper test).
4. **The three CI workflows** and where a new gate registers.
5. **`.claude/protect-shared-checkout.sh`** — the estate's only existing hook; the shape to copy.
6. **Reconcile `docs/plans/prp/estate-remediation/execution/execution-plan.md` unit-by-unit against
   the real tree.** I found one dead file reference (`ingest_prompts.py`); assume there are more.

### Documentation Hunter — find docs for
1. **Claude Code hooks**: `Stop`, `PreToolUse`, `PostToolUse`, `SessionStart` — exact
   `settings.json` schema, matcher syntax, and **the exit-code contract** (which code blocks, which
   is advisory). Four of the ten rules depend on getting this exactly right, and there is no working
   example in this estate to copy from.
2. **launchd**: `RunAtLoad`, `StartInterval`, `LastExitStatus` semantics, and how `launchctl list`
   output should be parsed. Note exit 78 (`EX_CONFIG`) is being used deliberately as a refusal code.
3. **SQLite**: `BEFORE INSERT` triggers with `RAISE(ABORT)`, `CHECK` constraints on added columns,
   and the `mode=ro` vs `immutable=1` distinction — **two seats hit different journal modes on the
   same file.**
4. **GitHub Actions**: check-run naming, and whether job name uniqueness can be enforced by a
   workflow-lint action or must be a custom test.
5. **The `.claude/patterns/*.md` files INITIAL.md cites but which do not exist** — either locate the
   real source (possibly `jonhill90/skills`) or declare them missing so the parallel-group and
   quality-gate conventions can be reconstructed from the example execution plan instead.

### Example Curator — extract examples showing
1. **A refusal that names its actuator** — the shape seat 4's proposed 11th invariant requires.
2. **A mutation-verified test**: a case in `tests/supervisor/` that demonstrably goes red when the
   guarded behaviour is reverted. `verdict-independence.sh`'s `lane_relation` tests and
   `test_bootstrap_session.sh` are the leading candidates.
3. **A positive-controlled absence check** — a test that proves it can see a violation before
   asserting there is none. seat-raw-3 §7 does this in SQL (dropping the gap threshold to 0.5h to
   prove the query fires); that technique should become the template.
4. **The example execution plan's group structure**: colour-coded mermaid graph, per-group validation
   gates, critical path, risk table — Jon named this specifically as the shape he liked.
5. **`restore.sh`'s `refuse()`** and the `--dry-run` plan output — the plan's own dry-run discipline
   is what caught the destructive invocations.

### Gotcha Detective — investigate
1. **The `!`-negated pipeline trap.** A guard was green and dead for 5½ months in the sibling repo
   because `set -e` exempts a `!`-negated command. **Every new bash gate must be checked for this
   specific shape.**
2. **macOS instrument traps.** `pgrep -c` returns empty even with matches; `find -newermt` matched 0
   of 1,159 files; `log show` returns 0 lines without elevation; `lsof` lives at `/usr/sbin/lsof`,
   which is **not** on the LaunchAgent PATH (`poller-recover.sh` documents this at #25). All look
   exactly like clean results.
3. **`window_id` does not survive a tmux server restart** — so invariant 5 (address by `@id`, never
   index) is necessary and insufficient. Any target stored as `@N` is a time bomb.
4. **`tmux kill-server` destroyed the estate three times.** Exact-match kills only, `TMUX_TMPDIR`
   always, and the guard now covers session *creation* too (#185).
5. **The ledger's journal mode is not stable across observations.** One seat found
   `journal_mode=delete` with no sidecars; another found WAL with sidecars appearing and vanishing
   mid-session. A read-only open cannot create the `-shm` it needs. **Determine the mode before
   choosing the access method.**
6. **A test harness can claim the production session name on the default socket** — and the
   production loop will tick it.
7. **`docker exec`/`send-keys` stdin and idle-matcher traps**: `director-route.sh:149` carried a
   private copy of the idle matcher that could never match, and Jon's Telegram replies were silently
   discarded for a week (#350, fixed #352). **Any private copy of a matcher is this defect.**
8. **Deduplication keyed on a name** — `ci_gate.py` is one instance; look for others.
9. **A verification that greps for a substring of the message it just sent** — `heartbeat.sh:197` is
   one instance; the same file gets it right at line 93. Look for others.
10. **Zero-consumer tables.** `events` 703/703 unread, `components` 0 rows but read at
    `core.py:1554/3165/3179`, `pr_authorship` 0 while `pr_external_authorship` has 7. The codebase
    names this defect nine times as its own proverb and shipped it again.

---

## Confidence and Residual Risk

**Confidence in the requirement extraction: high.** Six seats, independently briefed, converging;
eleven load-bearing claims re-verified by me against this tree, with a positive control on the
absence claims.

**Named residual risks:**

1. **Archon was unavailable**, so no cross-project pattern retrieval happened. Mitigated by the
   three repo-local prior artifacts, which are closer to this task than anything Archon would have
   held.
2. **The council's counts are already drifting** (297→304, 166→168 in 24 hours). Anything the plan
   asserts as a number must be re-measured at implementation time.
3. **Three measurement disagreements are unresolved by design** (question contamination 209/305/581;
   corpus contamination 29.6%/40.5%/62.6%/78%; the closure-target mechanism). The plan must carry
   the disagreement, not average it.
4. **`.claude/patterns/*.md` do not exist**, so INITIAL.md's stated conventions for parallel groups
   and quality gates are unverified.
5. **The 51 findings were counted by INITIAL.md, not by me.** My grouping (A1–A13, S1–S10, C1–C9,
   D1–D7, E1–E4, F1–F5, G1–G3 = 51) matches its total, but two items are structurally different
   from the rest and should not be planned as ordinary findings: **the Telegram token exposure**
   (not in the 51 at all) and **A13 `contest-stop.sh`** (a decision, not a defect).
6. **The single largest risk to this work is that it becomes the 358th machinery PR.** Group G is
   the point. Seat 5's measurement — 357 machinery PRs, 0 commits to product main, and the observation
   that the supervisor *"was optimizing for being able to explain itself"* — applies to this PRP as
   much as to anything it replaces.
