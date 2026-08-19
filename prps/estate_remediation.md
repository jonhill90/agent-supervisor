name: "PRP: Estate Remediation — the 2026-08-19 council audit, all 51 findings"
description: |
  Synthesis of five research documents (feature-analysis, codebase-patterns, documentation-links,
  examples-to-include, gotchas) into one executable plan. Phase 4 of /generate-prp.

**Generated**: 2026-08-19
**Based On**: `prps/INITIAL_estate_remediation.md`
**Repo root**: `/Users/jon/source/repos/Personal/agent-supervisor/.worktrees/plan/audit-remediation`
**Archon**: NOT AVAILABLE. No Archon call was attempted at any phase. Task tracking degrades to the
existing ledger claim mechanism. Prior-art retrieval was substituted with three repo-local
artifacts, named in "Prior Art" below.
**Research inputs** (read in full, integrated not concatenated):
`prps/estate_remediation/planning/{feature-analysis,codebase-patterns,documentation-links,examples-to-include,gotchas}.md`
**Extracted code**: `prps/estate_remediation/examples/` (6 files + README.md)

---

## Goal

Remediate every finding from the 2026-08-19 council audit of the agent-supervisor estate — all 51,
plus one credential exposure the audit did not count. Six independent seats, each with fresh
context and its own lens, measured the supervisor against Jon's verbatim typed words and against
the running machine, and converged independently on one root cause:

> **Every actuator in this estate is gated behind a refusal-on-uncertainty, and total death is the
> state of maximum uncertainty. The safety posture is perfectly anti-correlated with the failure
> mode.** 24 detectors, 14 actuators, of which 3 fire and 6 are gated behind `tmux has-session` —
> the precondition that is false in precisely the outage they exist for. Nothing in the estate can
> create a tmux session that does not exist.

The second root cause is structural: `~/.claude/settings.json` has **no `hooks` key at all**
(re-verified three times across phases — keys are `alwaysThinkingEnabled, effortLevel,
enabledPlugins, skipDangerousModePermissionPrompt, theme, tui, voiceEnabled`), so every rule Jon
repeated 14–53 times was left to the agent's own judgement, which fails hardest exactly when it is
most confident.

**The one-line framing to carry**: *the estate can describe its own death fluently and cannot act
on it.* Every task below is either the missing actuator, a check that runs outside the agent's
turn, or the removal of an instrument that reports success while blind.

**End State** — measurable, and each is a positive-controlled assertion, never a snapshot count:

1. A killed production session is recreated by a scheduled unattended job, proven by an
   isolated-tmux test that kills and re-ticks **and** by one real observed recovery.
2. `~/.claude/settings.json` has a `hooks` key with four hooks registered by an idempotent
   installer that has an uninstaller, and each hook's *wiring* is asserted by a test that reads the
   real user-global file.
3. No ledger reader in the estate can report a number it did not prove it could read: three-code
   exit contract, `0` clean / `1` violations / `3` could-not-measure, everywhere.
4. Every new gate is mutation-verified with the evidence committed as a `mutation-check:` test
   case, and every "zero violations" assertion carries a `positive-control:` case.
5. The corpus stores Jon's words verbatim, his questions as questions, and nothing from a repo he
   excluded — behind a *restored-and-counted* backup, not a backup file's existence.
6. At least one commit reaches a product `main`. That is the metric the whole audit turns on
   (357 machinery PRs merged : 0 product commits).

## Why

**Current pain points**, each traceable to a seat and re-verified in Phase 1 against this tree:

- **The estate certified itself healthy through a two-hour death.** `poller-recover.sh:155` returns
  `exit 0` when the session is missing, so `watchdog.sh:1073-1082` writes a fresh
  `.poller-recovery-last-success` and zeroes the fail streak. Zero test coverage for this case.
- **The most severe state pages nobody.** `watchdog.sh:1678`'s `no_session` branch is
  `report … ; exit 0`, and `report()`'s own comment at `:537-538` says *"escalate is the only state
  a human needs told about"*. 106 `no session` ticks across four days. The pages Jon *did* receive
  were a side effect of a parse failure in an unrelated lane-scan check.
- **Guards that are green and dead.** `heartbeat.sh:197` verifies its stall nudge by grepping the
  whole pane for a string that is a substring of the message it just typed (`MSG` at `:149`
  contains `` `esc to interrupt` ``) — line 200 is unreachable. `ci_gate.py:_latest_per_name` keys
  on the check-run name and both `fixpass-evidence.yml:34` and `ui-evidence.yml:26` declare their
  job as `gate:`, so the merge gate is a race — demonstrated on PR #394.
- **His questions are recorded as his decisions.** Between 209 and 581 hard-tier items were mined
  from interrogative prompts (the three seats disagree, deliberately — see "Contested
  measurements"). `possibility_count` is `COUNT(*) FROM live_parameters WHERE weight='hard'` = 920:
  a count of his constraints, reported under the name of the solution space they constrain, in
  every 30-minute report.
- **Instruments that are blind and report clean.** `events` has 703 rows, 703/703 never notified
  and never acked. The notify path ran on a silent fallback for two days (83 of 119 lines
  `NOTIFY-PATH-STALE`). The quota meter was unreadable 86% of the time and pinned to
  `confirmed: SAFE`; on 2026-08-15 that burned $80 of credits down to $8.
- **The estate spent itself on itself.** 357 machinery PRs merged, 0 commits to product main; 713
  of 1,536 lifetime tasks cancelled (46.4%).

**Business value**: the point of this work is not a better-instrumented supervisor. It is that the
machine survives its own death without Jon reading his own README, that the rules he repeated
dozens of times stop depending on an agent's judgement, and that the estate's output stops being
about the estate. **The single largest risk to this PRP is that it becomes the 358th machinery PR**
(feature-analysis.md, Residual Risk 6) — which is why Group G is a task and not an epilogue.

## What

### Core features

1. **The actuator that has never existed** (A1/A2): a scheduled session reaper whose trigger is a
   set-difference between the `sessions` ledger table and `tmux ls`.
2. **Ten repeated rules moved out of the agent's judgement** (S1–S10): four Claude Code hooks, a
   launchd wrapper, a launchd exit sweep, and five CI gates.
3. **A corpus that is provably verbatim and provably complete** (C1–C9, S6/S7/S8), repaired behind
   a restored-and-counted backup.
4. **Honest instruments** (D1–D7): every reader proves it can read before it reports; every "zero"
   is positive-controlled; the report always sends and a zero renders differently from a hit.
5. **Dead guards made able to fire** (E1–E4), and every new guard mutation-verified.
6. **The estate pointed back at the product** (G1–G3), with the two genuinely unenforceable rules
   recorded as unenforceable rather than papered over.

### Success criteria

- [ ] A killed `agent-supervisor` session is recreated by a scheduled job with no human action.
- [ ] `sessions` contains both production sessions and zero `at14-scratch-*` rows.
- [ ] `poller-recover.sh` exits non-zero on a missing session **and** `.poller-recovery-last-success`
      is unchanged across such a tick. Both asserted; the case has zero coverage today.
- [ ] `no_session` reaches Jon *as* `no_session`.
- [ ] Every `com.jonhill.*` job's **running** `ProgramArguments[0]`, read from `launchctl print`,
      resolves under `$SUPERVISOR_LIVE`. **Fails four times today — that is the positive control.**
- [ ] Every loop script preflights its target with `has-session -t "=sess:@id"` and exits non-zero
      when the target is gone.
- [ ] `restore.sh --only-session X` emits no plan line whose lane prefix is not `X`; `--session`
      remains the human-only redirect; #347's grep is replaced by a real placement test.
- [ ] `~/.claude/settings.json` has a `hooks` key with four hooks, installed by a script with an
      uninstaller, each with a wiring test against the real file.
- [ ] agent-dotfiles #237, #174 and PR #55 no longer quote Jon with profanity, and the hook blocks a
      synthetic new violation.
- [ ] Every module under `scripts/supervisor/` has ≥1 non-test importer, or is deleted.
- [ ] `links` is non-empty and `conflicts` returns a row for a **planted** conflict — the positive
      control *is* the acceptance, not the row count.
- [ ] Every `prompts.text_raw` is an exact substring of a source `.jsonl`; the named missing
      instructions are present; zero paraphrase rows; zero `hill90-app` rows.
- [ ] `possibility_count` either counts possibilities or is renamed to what it counts.
- [ ] `events` with `notified_at IS NULL` older than one hour is zero — as a CI assertion whose
      instrument is proven readable first.
- [ ] Two consecutive `UNKNOWN` quota readings decay `confirmed` to `UNSAFE` and quiesce dispatch.
- [ ] No two workflows declare the same job name — **fails today**.
- [ ] At least one commit on a product `main`.

### Meta-criteria — these apply to every item above and are not optional

- [ ] **Every gate is mutation-verified with the evidence committed.** Revert the fix → the gate
      goes red, as a `mutation-check:` case in the same suite (`test_lanes.sh:710-830` is the
      template; `test_session_defaults.sh:55` is the naming). A paragraph in a PR body does not
      count.
- [ ] **Every "zero" assertion is positive-controlled** — the check is shown detecting a planted
      violation before it is trusted reporting none, as a `positive-control:` case.
- [ ] **No acceptance criterion hardcodes a snapshot count.** They drift: 297→304 session literals
      and 166→168 director literals inside 24 hours (feature-analysis measurement); 770 branches →
      **414**, 346 worktrees → **202** (gotchas measurement, same week). Assert *zero* or a
      *ceiling*, never a snapshot.

---

## All Needed Context

### Documentation & References

```yaml
# MUST READ — Claude Code hooks (S1, S2, S4, S5)
- url: https://code.claude.com/docs/en/hooks.md
  sections:
    - "settings.json schema" - hooks → event → array of matcher groups → matcher + hooks array
    - "Exit code contract" - which events exit 2 blocks on, and which it does not
    - "Matcher syntax" - literal, case-sensitive, TOOL NAME ONLY
    - "stdin payloads" - stop_hook_active, transcript_path, cwd, tool_input
  why: Five of the ten STANDARD rules are hooks; there is no user-global precedent on this machine.
  critical_gotchas:
    - "PostToolUse CANNOT block. The seat specified PostToolUse for S5; exit 2 there is shown to
       Claude and undoes nothing. S5 MUST be PreToolUse on Write|Edit. Flag as a correction to Jon,
       not a silent substitution."
    - "Matchers match the tool NAME only. S4's `gh (issue|pr) (create|edit|comment)` is not a
       matcher. Use matcher: 'Bash' (+ optional `if: \"Bash(gh *)\"` pre-filter) and grep
       tool_input.command inside the script."
    - "Claude Code overrides a Stop hook after 8 consecutive blocks (CLAUDE_CODE_STOP_HOOK_BLOCK_CAP).
       A hook that ignores stop_hook_active spins to the cap and is then IGNORED — installed and
       inert."
    - "PreToolUse fires in EVERY permission mode including bypassPermissions, so S4/S5 still fire on
       the 132 --dangerously-skip-permissions lanes."
    - "Multiple hooks on one event run in PARALLEL; a deny does not suppress a sibling's side
       effects. Do not write hooks that assume ordering."
    - "Claude Code FAILS OPEN on a missing hook script — this repo lost a guard exactly that way
       (tests/supervisor/test_protect_shared_checkout.sh:8-13)."

- url: https://keith.github.io/xcode-man-pages/launchd.plist.5.html
  sections: ["ProgramArguments", "RunAtLoad", "StartInterval", "StartCalendarInterval", "KeepAlive", "ThrottleInterval"]
  why: A8, A9, S2, S3, S5, S10 all schedule or inspect launchd jobs.
  critical_gotchas:
    - "StartCalendarInterval treats MISSING KEYS AS WILDCARDS — {Hour: 3} fires 60 times, once a
       minute for an hour. Always pin Minute."
    - "KeepAlive{SuccessfulExit:false} on a job that refuses with exit 78 respawns it in a hot loop.
       Never use it on anything wrapped by run-from-main.sh."
    - "StartInterval below 10s is silently throttled (ThrottleInterval default 10)."
    - "launchctl list's status column is the raw waitpid word: 768 = 3<<8 → exit 3;
       19968 = 78<<8 → the deliberate EX_CONFIG refusal. Authority is <sys/wait.h> on this machine
       ($(xcrun --show-sdk-path)/usr/include/sys/wait.h), NOT the man page, which does not document
       positive values above 255."
    - "Editing a plist without bootout/bootstrap leaves the OLD ProgramArguments live. A8's
       acceptance MUST read `launchctl print`, not the file on disk."

- url: https://man.openbsd.org/tmux.1
  sections: ["has-session", "new-session", "list-sessions", "server/socket model", "unique IDs"]
  why: A1, A2, A10, A12, and AGENTS.md invariants 4 and 5.
  critical_gotchas:
    - "`tmux display -t` EXITS 0 ON A NONEXISTENT TARGET and silently answers about the wrong one.
       The seat prescribed it as the S3/A10 preflight; it is the defect A10 exists to fix. Use
       `has-session -t \"=sess:@id\"` (exits 1, 'can't find window: @99') or `list-panes -t`."
    - "has-session PREFIX-MATCHES without '='. `has-session -t mysess` returns 0 against
       'mysession'. Every has-session and kill-session in this estate takes '='."
    - "`new-session -A -d` FAILS rc=1 ('open terminal failed: not a terminal') from a headless job
       whenever the session already exists — i.e. on every healthy tick. And -A does not exact-match:
       it creates a SECOND, decoy session on a prefix name. Use
       `has-session -t \"=$s\" || new-session -d -s \"$s\"`."
    - "@N window IDs are unique 'in the tmux server' only — a restart reallocates from @0, so a
       stored @35 is dangling or, worse, silently someone else's window. Invariant 5 is necessary
       and INSUFFICIENT. (Inferred from the man page's scoping; not measured — labelled as inference
       by documentation-links.md, gap 6.)"

- url: https://sqlite.org/lang_createtrigger.html
  also: [https://sqlite.org/lang_expr.html, https://sqlite.org/lang_altertable.html, https://sqlite.org/uri.html]
  sections: ["BEFORE INSERT / RAISE forms", "GLOB vs LIKE vs REGEXP", "ADD COLUMN restrictions", "mode=ro vs immutable=1"]
  why: S6's trigger, the provenance column, and every ledger read in the PRP.
  critical_gotchas:
    - "Python's sqlite3 defines NO regexp(). CREATE TRIGGER using REGEXP SUCCEEDS, and then EVERY
       INSERT into items — honest ones included — raises OperationalError. core.py is the writer, so
       this bricks ingest. Use GLOB/LIKE, which need no registration and pin the classifier
       literally in the schema."
    - "In GLOB, '?' is a single-char wildcard, so '*?' means 'any non-empty string' and the trigger
       would reject EVERY hard item. Write '*[?]'. (documentation-links.md's own worked example
       carries the bug and flags it; gotchas.md #9 states the correction. Take the correction.)"
    - "RAISE(IGNORE) silently drops the row — precisely this audit's own defect. RAISE(ROLLBACK)
       kills the whole ingest transaction. Use RAISE(ABORT)."
    - "ALTER TABLE ADD COLUMN ... NOT NULL requires a non-NULL DEFAULT. `provenance TEXT NOT NULL
       CHECK (provenance IN ('human','agent'))` cannot be added as written."
    - "immutable=1 is a SILENT LIAR under a live writer — measured returning 1 where the committed
       truth was 2."

- url: https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
  sections: ["-e exemptions", "-o pipefail"]
  why: This is how a guard was green and dead for 5½ months in the sibling repo.
  critical_gotchas:
    - "`-e` explicitly exempts a !-negated command AND 'part of the test in an if statement'.
       Reproduced with the runner's exact invocation:
         bash --noprofile --norc -eo pipefail -c '! false | grep zzz; echo REACHED; exit 0' → exit 0.
       Every bash gate takes the `if …; then echo '::error::…'; exit 1; fi` shape."

- url: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
  why: E1 and every new CI gate.
  critical_gotchas:
    - "job_id uniqueness is scoped to ONE workflow file. Two workflows may both declare `gate:` and
       GitHub's branch-protection UI cannot distinguish them. No first-party linter enforcing
       cross-workflow uniqueness was found — ship a ~15-line stdlib custom test."

- url: https://git-scm.com/docs/git-merge-base
  also: https://git-scm.com/docs/git-worktree
  why: S2's wrapper and S10's reaper.
  critical_gotchas:
    - "merge-base --is-ancestor: 0 = ancestor, 1 = not, and 'errors are signaled by a non-zero
       status that is NOT 1' (measured: bogus SHA → 128). A bare `if ! git merge-base` conflates
       128 with 1."
    - "`git worktree prune` only removes admin files for already-missing directories — safe
       unconditionally. A MOVED worktree needs `git worktree repair`, not prune."
    - "Squash-merged branches read as unmerged. `git branch -d` refuses them (safe); `-D` destroys
       them. NEVER automate -D."

# ESSENTIAL LOCAL FILES — read README.md first
- file: prps/estate_remediation/examples/README.md
  why: Per-example What to Mimic / What to Adapt / What to Skip, plus a seven-item anti-pattern list.
  pattern: Read before writing any code.

- file: prps/estate_remediation/examples/example_1_shell_actuator_house_style.sh
  why: The direct template for the session reaper (T4), run-from-main.sh (T10), reap.sh (T20).
  critical: Header discipline, env-driven session name, validate-before-touch, the refusal that
            names its actuator, --dry-run, adopt-session ledger write, reclaimable mkdir lock.

- file: prps/estate_remediation/examples/example_2_shell_test_isolation_and_positive_control.sh
  why: Every new shell test. Attach section E to the meta-criteria.
  critical: ok/bad/check helpers, assert_isolated_tmux in full, AGENT_SUPERVISOR_STATE_DIR scratch
            ledger, EXIT INT TERM trap with EXACT-MATCH kills, the positive-controlled absence check.

- file: prps/estate_remediation/examples/example_3_claude_code_hooks.sh
  why: T22/T23. settings.json schema for four events, stdin parsing, the exit-code contract, a
       blocking PreToolUse hook (this repo's, verbatim), a Stop hook (Hill90's, verbatim), and the
       six requirements for the ~/.claude/settings.json installer.
  critical: Hill90's stop-gate.sh is the STRUCTURAL template and the POSTURE COUNTEREXAMPLE — it
            fails open on four unreadable-input paths (lines 15/21/26/32). For S1 that is backwards.

- file: prps/estate_remediation/examples/example_4_notify_send_path.py
  why: T17. Pure decision core + thin actuator, SendError, send_via_notify_skill, with D3/D4/D5
       annotated in situ as work items rather than patterns.

- file: prps/estate_remediation/examples/example_5_sqlite_migration_and_trigger.py
  why: T25. _migrate_lanes_table's rebuild-in-place and one_open_pull_per_source_ref's
       BEFORE INSERT/RAISE(ABORT) trigger WITH ITS PRE-FLIGHT DUPLICATE SCAN.
  critical: Its closing three-step procedure is the mutation-verification template — assert red,
            assert legitimate-neighbour green, revert and assert red again, transcript committed.

- file: prps/estate_remediation/examples/example_6_pane_match_correct_vs_broken.sh
  why: T14, and it belongs in the Blueprint itself — it is the cheapest available explanation of
       what class of defect this whole PRP exists to remediate.
  critical: heartbeat.sh:93 (correct, footer) vs :197 (broken, whole scrollback), the fix, the
            mutation test, and the two gotchas that must survive the fix.

- file: scripts/supervisor/poller-recover.sh:1-200
  why: The actuator template end to end; :155 IS A3's defect; :157-161 documents the macOS
       lsof/PATH trap; :38-61 argues the non-CAS race and the lock-reclaim the reaper inherits.

- file: scripts/supervisor/core.py:271-274,320,536-540,1011-1171
  why: The four _migrate_* methods called from __init__, the sessions schema, the BEFORE INSERT
       trigger template, and :1136-1144's refuse-on-pre-existing-violation pattern.
  critical: THERE IS NO migrations/ DIRECTORY, no PRAGMA user_version, no version table. Migrations
            are idempotent-by-construction _migrate_* methods that probe with PRAGMA table_info.

- file: tests/supervisor/test_shell_suites.py:22-23,64-118
  why: A new tests/supervisor/test_*.sh is enforced the moment it lands — no registration step.
  critical: :65-68 asserts the glob is non-empty. That is the estate's own positive-control idiom.

- file: docs/audit/2026-08-19-council/
  why: PRIMARY EVIDENCE — 9 files, 3,829 lines. Read before asserting anything.

- file: AGENTS.md
  why: Invariants 3 (no lane auto-restart — MUST SURVIVE), 4 (never address the default tmux
       socket in a test), 5 (address by window_id), 8 (the poller is a service, not a lane),
       9/10 (lane identity).
```

### Prior art (Archon substitutes)

| Artifact | Relevance | Use it for | Do NOT trust |
|---|---|---|---|
| `docs/plans/prp/estate-remediation/execution/execution-plan.md` (486 lines, `eeae775`) | 10/10 — a prior pass at *this exact task* | The shape: findings consolidated by **file ownership**, the rule *"exactly one task owns each file, for the whole plan"*, colour-coded mermaid groups, per-group gates, critical path | `U29` names `scripts/supervisor/ingest_prompts.py`, **which does not exist** (verified). The ingest surface is `mine_prompts.py` / `itemize_prompts.py`. Assume more dead references |
| `docs/plans/prp/estate-remediation.md`, `docs/plans/sdd/estate-remediation-sdd.md` | 8/10 | The `T1`–`T51` numbering the graph resolves against | Written before the contested-measurement, Telegram-token and `acked_at` findings |
| `AGENTS.md` invariants 1–10 | 10/10 — constraints, not suggestions | See above | — |

**`.claude/patterns/{parallel-subagents,quality-gates,archon-workflow}.md` DO NOT EXIST.**
Confirmed absent from this worktree and from `~/.claude/` by two independent phases. INITIAL.md
cites them. `jonhill90/skills@5688dfe1` was not fetched (could not check). **The parallel-group and
quality-gate conventions in this PRP are reconstructed from the in-tree execution plan, and this
sentence exists so no downstream agent goes looking for a file that is not there.**

### Current codebase tree (relevant parts only — flat by design)

```
scripts/supervisor/            ~80 flat files. NO hooks/, NO lib/, NO migrations/ subdirectory.
  poller-recover.sh            actuator template; :155 = A3's defect
  bootstrap-session.sh         the ONLY set -euo pipefail file (:63); :244-251 refuses on existing
                               session; :296-297 --add-lanes loop starts AFTER the supervisor slot
  restore.sh                   :109 refuse() + 11 call sites; :121 --session is a REDIRECT; :201 new-session
  watchdog.sh                  :487-540 report(); :537-538 the escalate-only rule; :1073-1082 the
                               false-success stamp; :1678 the no_session branch
  heartbeat.sh                 :93 correct footer match; :149 MSG; :197 broken scrollback match;
                               :200 unreachable
  director-loop.sh             exits 3 at :110 before reaching contest-stop.sh at :232
  watchdog_notify.py           :299 hardcoded inbox-poll message; :335-341 unbounded stopped
                               exemption; :568-608 the NOTIFY-PATH-STALE resolver
  core.py                      :271-274 migrations from __init__; :320 _initialize; :536-540 sessions;
                               :279-281 WAL + synchronous=FULL; :1011-1171 the trigger template;
                               :3321 update_text_clean (ZERO production callers); :3358 record_link
                               (ZERO non-test callers)
  ci_gate.py                   :~100-115 _latest_per_name keys on name alone
  session-defaults.sh          lanes_session_or_default — A11's EXISTING seam
  tmux-isolation.sh            :3-16 assert_isolated_tmux
  tmux_verb_guard.py           enforces AGENTS.md invariant 4 — A12 extends THIS
  acp_transport.py             302-317 tested lines, ZERO non-test importers
  poller-leak-cleanup.sh       183 lines, 9 tests, ZERO callers
  itemize_prompts.py           --load reads a model-produced JSON array, writes kind/weight verbatim
  notify.sh                    :73 NOTIFY_ENV; :123-128 refuses rather than falling back
.claude/
  settings.json                ONE PreToolUse/Bash hook
  protect-shared-checkout.sh   51 lines, flat — NOT in .claude/hooks/ (inventing that broke it once)
tests/supervisor/              109 suites, test_*.sh auto-discovered by test_shell_suites.py
tests/supervisor/lib/reap-verified.sh    the only shared test helper
.github/workflows/             validate.yml (job `test`), fixpass-evidence.yml (job `gate`),
                               ui-evidence.yml (job `gate`)   ← E1's collision, confirmed
launchd/com.jonhill.director-loop.plist  the ONLY tracked plist. SIX are live.
```

### Desired codebase tree

```
scripts/supervisor/
+ ledger-snapshot.sh           snapshot_ledger(); the ONLY sanctioned ledger read path
+ ledger_snapshot.py           the Python twin (same contract, same exit codes)
+ scan-corpus-secrets.sh       credential scan over a snapshot
+ register-owned-sessions.sh   A2 backfill via cli.py adopt-session
+ session-reaper.sh            A1 — the actuator that has never existed
+ run-from-main.sh             S2 — installed LAST, after A8
+ launchd-sweep.sh             A9/S3
+ tmux-preflight.sh            shared has-session -t "=sess:@id" preflight (ONE copy, sourced)
+ reap.sh                      S10
+ state-orphan-audit.sh        S5 daily auditor
+ phase-report.sh              S5 — the deliverable moved OUT of ~/.local/state into git
+ quota-standdown.sh           D6
+ check-plists-live.py         A8 — reads launchctl print, uses plutil
+ check_events_consumed.py     D1
+ check_corpus_verbatim.py     S7
+ check_module_callers.py      S9
+ check_workflow_job_names.py  E1 recurrence lint
+ check_session_literals.py    A11 ceiling (grandfathered by count)
+ check_refusal_actuator.py    F5 ceiling (grandfathered by count)
+ check_machinery_ratio.py     G1/G3
+ check_asks.sh                F4 — ASKS.tsv verifier
+ link_comparator.py           S8/C1 — deterministic resolved_to linker
+ corpus-repair.sh             C2/C5–C9, behind a RESTORED-AND-COUNTED backup
+ corpus-backup.sh             the backup + its restore-and-count verification
+ hook-spike.sh                T22 — answers the two UNRESOLVED questions empirically
+ install-claude-hooks.sh      ~/.claude/settings.json installer (idempotent, backs up, validates)
+ uninstall-claude-hooks.sh    the uninstaller — non-optional
.claude/                       (flat — do NOT create .claude/hooks/)
+ check_stop_authorized.sh     S1
+ check_quote_policy.sh        S4
+ no_code_in_state.sh          S5
+ assert_from_main.sh          S2 SessionStart
launchd/
+ com.jonhill.session-reaper.plist
+ com.jonhill.launchd-sweep.plist
+ com.jonhill.reap.plist
+ com.jonhill.state-orphan-audit.plist
+ com.jonhill.supervisor-watchdog.plist   } the five untracked live plists, brought into git
+ com.jonhill.quota-watch.plist           } (this is itself an instance of S5)
+ com.jonhill.supervisor-heartbeat.plist  }
+ com.jonhill.weekly-watch.plist          }
+ com.jonhill.jon-report.plist            }
.github/workflows/
+ events-consumed.yml, corpus-verbatim.yml, links-nonempty.yml, module-callers.yml,
  workflow-job-names.yml, ceilings.yml, machinery-ratio.yml   (each job name UNIQUE; each 4 lines;
  each delegating to a tracked, separately-tested script; each with timeout-minutes)
tests/supervisor/              + one test_<script>.{sh,py} per new script — auto-discovered
docs/decisions/
+ unenforceable-rules.md       the two rules recorded as unenforceable, WITH THE REASON
+ deferrals.md                 F2 and anything else deferred, each with its reason
+ contested-measurements.md    209/305/581 and 29.6/40.5/62.6/78%, method stated with every number
docs/audit/2026-08-19-council/
+ CREDENTIAL-EXPOSURE.md       T1
+ hook-spike-results.md        T22
ASKS.tsv                       F4 — each ask with a one-command verification
```

### Known gotchas & library quirks — lead with 1–3; an implementer who follows the planning docs literally ships something that does not work and reports that it does

```bash
# ═══ CRITICAL 1 — `file:$LEDGER?mode=ro` CANNOT OPEN THE LIVE LEDGER ═══
# Source: gotchas.md Critical 1, measured 2026-08-19. This CORRECTS documentation-links.md §4,
# which prescribes mode=ro + .backup. Both were measured to fail on the real file. Take gotchas.
#
#   sqlite3 "file:$L?mode=ro" 'select count(*) from sessions;'  -> unable to open database file (14)
#   file:$DB?mode=ro&nolock=1                                   -> ALSO 14 (does not help)
#   file:$DB?mode=ro&immutable=1                                -> works, AND SILENTLY LIED:
#                                                                  returned 1 where truth was 2
#   sqlite3 "file:$DB?mode=ro" ".backup snap"                   -> rc=1
#   python3 sqlite3.connect('file:...?mode=ro', uri=True)       -> works, AND CREATES -wal/-shm
#                                                                  (so it is NOT read-only at the
#                                                                   filesystem level)
# A read-only connection to a WAL database must create the -shm and cannot. When a writer happens
# to be live the sidecars exist and the same command works — THAT is why seat-raw-2 and seat-raw-3
# "disagreed about the journal mode". Same file, two sidecar states.

# ❌ WRONG — fails rc=14 right now, empty output, gate goes GREEN
count=$(sqlite3 "file:$LEDGER?mode=ro" 'select count(*) from events where notified_at is null;' 2>/dev/null)

# ✅ RIGHT — scripts/supervisor/ledger-snapshot.sh, used by EVERY reader in this PRP
snapshot_ledger() {
  local src="${1:?ledger path}" dst
  dst="$(mktemp -d "${TMPDIR:-/tmp}/ledger-snap.XXXXXX")/ledger.sqlite3"
  cp -p "$src" "$dst" || return 3
  for suf in -wal -shm; do [ -e "$src$suf" ] && { cp -p "$src$suf" "$dst$suf" || return 3; }; done
  sqlite3 "$dst" 'select 1 from sqlite_master limit 1;' >/dev/null 2>&1 || return 3
  printf '%s\n' "$dst"
}
SNAP="$(snapshot_ledger "$LEDGER")" || {
  log "REFUSED: cannot snapshot ledger -- not reporting a count I could not read"; exit 3; }
# Measured green: copying db + -wal + -shm and opening the COPY returned the correct count (3)
# while a writer was live. A bare `cp` of the main file alone is a torn read.
# The snapshot is ALSO the answer to "the ledger is READ ONLY": the snapshot is what is analysed,
# so the read path can never mutate the original.

# ═══ CRITICAL 2 — A GATE THAT COMPARES AN EMPTY STRING TO A NUMBER EXITS 0 ═══
$ bash -c 'set -uo pipefail; n=""; if [ "$n" -gt 0 ]; then echo FAILGATE; exit 1; fi; echo GREEN'
bash: line 1: [: : integer expected
GREEN                                    # gate exit=0
# `[` errors (exit 2), which is not "true", so the if body is skipped and the script falls through
# to success. `set -e` does NOT save you — the -e exemption covers "part of the test in an if
# statement" verbatim, the SAME CLAUSE as the ! trap that killed the sibling repo's guard for
# 5½ months. This COMPOSES with Critical 1 into the estate's worst outcome: the database cannot be
# opened, so the count is empty, so the gate reports the system clean.

# ✅ RIGHT — THREE exit codes, deliberately. A gate with only 0/1 cannot express "I was blind",
#            which is how this estate got here.
n=$(query) || { echo "::error::query failed -- refusing to report a count"; exit 3; }
case "$n" in ''|*[!0-9]*) echo "::error::non-numeric result [$n] -- instrument blind"; exit 3 ;; esac
if [ "$n" -gt 0 ]; then echo "::error::$n violations"; exit 1; fi
echo "0 violations (instrument verified readable)"
#   0 = clean   1 = violations found   3 = COULD NOT MEASURE

# ═══ CRITICAL 3 — `tmux new-session -A -d` FAILS FROM A HEADLESS JOB ═══
# Source: gotchas.md Critical 2, measured tmux 3.5. CORRECTS documentation-links.md §3, which
# prescribes `-A` as "the whole reaper body". Take gotchas.
new-session -d -s prod                             rc=0   (created)
new-session -A -d -s prod        (exists)          rc=1   open terminal failed: not a terminal
new-session -A -D -d -s prod     (exists)          rc=1   same
has-session -t '=prod' || new-session -d -s prod   rc=0   <-- THE WORKING FORM
new-session -A -d -s mysess      (mysession exists) rc=0, AND CREATED A SECOND SESSION 'mysess'
# So the prescribed reaper returns non-zero on EVERY HEALTHY TICK — a job that pages when nothing
# is wrong, training Jon to filter it (anti-goal 2), and whose exit code cannot be the liveness
# signal. And -A does not exact-match: a typo'd or prefix name silently creates a DECOY session.

# ═══ CRITICAL 4 — bootstrap-session.sh REFUSES on a partial session and cannot repair one ═══
# :244-251  session exists + no --add-lanes  -> exit 1, no repair. Correct for a human; fatal for
#           an unattended reaper that finds a session with 1 of 10 windows.
# :296-297  --add-lanes loop is `idx=$SUPERVISOR_WINDOW; while idx < SUPERVISOR_WINDOW+LANES-1` —
#           it starts AFTER the supervisor slot. A session that lost exactly its supervisor window
#           CANNOT BE REPAIRED BY THIS SCRIPT AT ALL, in either mode.
# :274-287  --add-lanes NEVER calls adopt-session (the comment says so deliberately). So a session
#           the reaper tops up is never registered in `sessions` — and A2 makes that table the
#           reaper's own trigger. THE REAPER WOULD REPAIR A SESSION AND THEN FORGET IT, and re-reap
#           it every tick, forever.
# :299-302  existing windows are "left alone" — no send-keys, so a window whose agent died counts
#           as healthy. has-session returning 0 says NOTHING about whether anything is running.
# ✅ Fix: a three-state classifier (absent | partial | complete), and only ever hand
#    bootstrap-session.sh the case it is built for. Plus a small patch so --add-lanes creates
#    $SUPERVISOR_WINDOW when missing, with a test that removes exactly that window.

# ═══ CRITICAL 5 — ORDERING: S2's branch guard landed before A8 takes the estate OFFLINE ═══
# The shared checkout is on fix/director-tick-fanout; FOUR of six live LaunchAgents execute from it.
# run-from-main.sh refuses (exit 78) on any ref that is not an ancestor of origin/main. The moment
# the wrapper enters those four plists, all four jobs STOP — including the reaper, if wrapped. The
# remediation would ship the outage it exists to prevent.
# ✅ Non-negotiable order:
#    1. advance live/ to a commit that IS an ancestor of origin/main
#    2. repoint all plists at live/ (A8) and bootout/bootstrap each
#    3. verify with `launchctl print`, NOT the plist on disk
#    4. ONLY THEN insert run-from-main.sh
# ✅ And the wrapper must DEGRADE, not refuse, on a failed fetch — a network blip must not disable
#    the only actuator that can rebuild a dead estate:
if ! git -C "$REPO" fetch --quiet origin main; then
  notify "run-from-main: fetch failed; falling back to the last-known origin/main ref"
  # do NOT exit — a stale-but-real origin/main is a better gate than no job at all
fi
git -C "$REPO" merge-base --is-ancestor HEAD origin/main; rc=$?
case $rc in
  0) exec "$@" ;;
  1) notify "REFUSED: $(git -C "$REPO" rev-parse --short HEAD) is not an ancestor of origin/main.
             Nothing ran. Merge it, or repoint this job at live/."; exit 78 ;;
  *) notify "REFUSED: merge-base errored ($rc). Nothing ran."; exit 78 ;;   # 128 != 1
esac
# THE REAPER IS EXEMPT FROM S2 BY DESIGN, and the exemption must be WRITTEN DOWN with its reason:
# a guard that can prevent recovery is worse than an unguarded recovery. If that is unacceptable,
# the reaper lives in live/ and is CHECKED rather than WRAPPED.
# exit 78 shows in launchctl list as raw 19968. The A9 sweep must decode it as a DELIBERATE REFUSAL,
# not a crash, or the refusal channel becomes the alarm channel.

# ═══ CRITICAL 6 — a user-global blocking Stop hook fires on all 162 `claude -p` lanes ═══
# ~/.claude/settings.json is USER-GLOBAL. 162 of 196 lanes run `claude -p`. A Stop hook that exits 2
# blocks the stop and makes Claude keep working — on every one of those lanes, in parallel, to the
# 8-block cap. This estate has already burned $80 of credits to $8 in one day with no stand-down.
#!/usr/bin/env bash
set -uo pipefail                         # house default is -uo, NOT -euo (38 files vs 1)
INPUT=$(cat)
val() { printf '%s' "$INPUT" | python3 -c 'import json,sys;print(json.load(sys.stdin).get(sys.argv[1]) or "")' "$1" 2>/dev/null; }
[ "$(val stop_hook_active)" = "True" ] && exit 0        # 1. honour the cap or be silently overridden
case "$(val cwd)" in                                    # 2. SCOPE — a lane is not the supervisor
  "$SUPERVISOR_REPO"|"$SUPERVISOR_REPO"/*) : ;;
  *) exit 0 ;;
esac
[ -n "$(val transcript_path)" ] || {                    # 3. BLINDNESS IS NOT AUTHORISATION
  echo "STOP REFUSED: hook could not read the transcript; blindness is not authorisation." >&2; exit 2; }
stop_is_authorized || { echo "STOP REFUSED: no \$STATE/handoff/<session>.blocked naming a Jon-only
                              decision, and no Telegram send in 10m." >&2; exit 2; }
exit 0
# Hill90's stop-gate.sh fails OPEN on four unreadable-input paths (lines 15/21/26/32). For S1 that
# is exactly backwards: the rule is "the agent may not go quiet", and "I could not tell" is the
# state in which it goes quiet. FAIL CLOSED on blindness, and scope by cwd so the closed failure
# cannot reach 162 lanes.

# ═══ HIGH — a trigger/hook/gate installed over EXISTING contamination looks clean ═══
# A BEFORE INSERT trigger binds FUTURE inserts only; CREATE TRIGGER succeeds over the contaminated
# rows and reports nothing. Same for every hook (S4's three live public violations survive the hook
# that prevents new ones) and every ceiling auditor. core.py:1085-1097 argues this at length and
# :1136-1144 implements the answer.
# ✅ Every enforcement mechanism ships as a PAIR: the preventer AND a one-shot pre-flight scan that
#    refuses to install until the scan is clean or the rows are grandfathered BY COUNT so the
#    number can only go down.

# ═══ HIGH — SQLite REGEXP bricks every INSERT; '*?' in GLOB matches everything ═══
CREATE TRIGGER items_no_hard_from_question
BEFORE INSERT ON items FOR EACH ROW
WHEN NEW.weight = 'hard' AND NEW.kind IN ('directive','parameter')
 AND ( NEW.source_text GLOB '*[?]'                        -- NOT '*?' — that means "any non-empty"
    OR lower(NEW.source_text) GLOB 'what *'  OR lower(NEW.source_text) GLOB 'why *'
    OR lower(NEW.source_text) GLOB 'how *'   OR lower(NEW.source_text) GLOB 'should *' )
BEGIN SELECT RAISE(ABORT, 'a question may not be recorded as a hard item'); END;
# core.py:1061-1065 records that the RAISE(ABORT) message text is LOAD-BEARING — callers match on
# it. Choose S6's message deliberately and assert it in a test.
# Test BOTH directions FROM A FRESH CONNECTION, not the migration's: a synthetic hard-from-question
# insert must raise, and a legitimate non-interrogative hard insert must succeed.

# ═══ HIGH — PostToolUse cannot block; matchers see only the tool name ═══   (see hooks yaml above)
# ═══ HIGH — Claude Code fails OPEN on a missing hook script ═══
#   Every hook needs the TWO-PART test: (a) read the command out of the REAL ~/.claude/settings.json,
#   resolve it, assert the file exists and is executable; (b) feed synthetic stdin JSON, assert
#   exit 2. Part (a) is the one that matters — AN UNWIRED HOOK IS INDISTINGUISHABLE FROM A COMPLIANT
#   ESTATE. The installer must be idempotent, back up the existing file, validate the JSON BEFORE
#   writing (a corrupted user-global settings.json breaks every Claude session on the machine), and
#   have an uninstaller.

# ═══ HIGH — plistlib CANNOT PARSE 5 OF 6 LIVE PLISTS ═══
#   xml.parsers.expat.ExpatError: not well-formed (invalid token): line 14, column 53
#   XML forbids `--` inside comments; the house comment style uses it. launchctl accepts it; a
#   strict parser does not. `try: plistlib.load() except: continue` reports ONE compliant plist and
#   ZERO violations. Use `plutil -convert xml1 -o -` (or -lint), and TREAT A PARSE FAILURE AS A
#   FAILURE, NEVER A SKIP. Positive control: plistlib parses supervisor-watchdog fine, so the parser
#   works — the five failures are real.
#   ALSO: jon-report's ProgramArguments is `/bin/bash -c "a; b"` — not a single program path.
#   run-from-main.sh must handle that form.

# ═══ MEDIUM — reaping "dead" sockets and "merged" branches can destroy live work ═══
#   A socket file's age says NOTHING about whether its server is alive. Only remove a socket after
#   `tmux -S "$sock" list-sessions` FAILS, never by mtime.
# ═══ MEDIUM — verifying by grepping for the text you just sent ═══
#   heartbeat.sh:149 builds MSG containing `esc to interrupt`; :197 greps the whole pane for it;
#   :200 is unreachable. :93 does it right (footer, not scrollback). director-route.sh:149 carried a
#   PRIVATE COPY of an idle matcher that could never match and discarded Jon's Telegram replies for
#   a week (#350/#352). RULE: one shared matcher, sourced — never a private copy; and never verify
#   against a region that contains your own message.
# ═══ MEDIUM — macOS instruments that look like clean results ═══
#   `pgrep -c` returns empty even with matches. `find -newermt` matched 0 of 1,159 files. `log show`
#   returns 0 lines without elevation. `lsof` is at /usr/sbin/lsof, which is NOT on the LaunchAgent
#   PATH (poller-recover.sh:157-161; the tracked plist's PATH confirms /usr/sbin is absent).
#   EVERY ONE OF THESE RETURNS SUCCESS. Resolve absolute paths in the script.
# ═══ LOW — house conventions that bite ═══
#   `set -uo pipefail` is the house default (38 files vs 1). A reaper with `set -e` ABORTS EXACTLY
#   WHEN EVERYTHING IS DEAD — `tmux list-sessions` with no server running exits 1 (measured).
#   `comm -23 <(empty) <(live)` prints nothing and exits 0, so a reaper whose ledger query failed
#   does nothing and reports success. Assert the ledger side is non-empty before differencing.
#   Parse hook stdin with `python3 -c`, not `jq` — jq is not guaranteed and the estate is
#   stdlib-only. Guard shell profiles with `if [[ $- == *i* ]]` or profile output corrupts hook JSON.
```

### Contested measurements — the plan must NOT pick one silently

| Seat | Classifier | Hard items from questions | % of hard tier |
|---|---|---|---|
| seat-raw-2 (strict) | source prompt literally ends in `?` | **209** | 8.42% |
| seat-raw-2 (broad) | ends in `?` OR opens interrogative | **305** | 12.29% |
| seat-6 / seat-raw-6 | same, wider interrogative word list | **581** | 23.4% |
| seat-raw-8 | live items only, agent-authored excluded | **105** | — |

seat-raw-2 names the false-positive mode explicitly: *"Do (1), and your reason for it is the right
one: …"* is a directive that starts with "do". It recommends **209 as the floor, 305 as the
ceiling**. **The deterministic classifier S6's trigger depends on IS ITSELF the contested artifact.**
The resolution this PRP takes: (a) pin the exact GLOB literal in the migration, (b) publish the
count that literal produces at the moment it lands, (c) never cite 581 or 305 as settled.
Corpus contamination is likewise reported as 29.6% (score ≥2), 40.5%, 62.6% and 78% depending on
method — **state the method with the number, every time.** This is recorded permanently in
`docs/decisions/contested-measurements.md` (T34).

### Resolved contradictions between research documents

| Disagreement | Docs | Taken | Why |
|---|---|---|---|
| Reaper body `new-session -A -d` | documentation-links §3 vs gotchas Critical 3 | **gotchas** — `has-session -t '=n' \|\| new-session -d -s n` | `-A` was *measured* rc=1 from a non-terminal, and prefix-creates decoys. Measurement beats a synopsis reading |
| Ledger read `mode=ro` + `.backup` | documentation-links §4 vs gotchas Critical 1 | **gotchas** — `snapshot_ledger()` | Both were measured to fail on the *live* file; `.backup` only worked while a writer was live |
| `immutable=1` "settles it" | documentation-links §4 vs gotchas Critical 1 | **gotchas — forbid it** | Measured returning 1 where truth was 2. A silent liar is worse than an error |
| S5 mechanism | seat + feature-analysis (`PostToolUse`) vs documentation-links §1 | **`PreToolUse`** | `PostToolUse` fires after the write; exit 2 undoes nothing. Flag to Jon as a correction |
| S3/A10 preflight | seat (`tmux display -t`) vs documentation-links contradiction 1 | **`has-session -t "=sess:@id"`** | `display-message` exits 0 on a nonexistent target — it *is* the defect A10 exists to fix |
| S6 GLOB literal `'*?'` | documentation-links §4 worked example vs gotchas #9 | **`'*[?]'`** | `?` is a single-char wildcard; `'*?'` rejects every hard item. documentation-links flags its own bug in the prose |
| "No hooks example exists in this estate" | feature-analysis vs examples-to-include finding 1 | **examples-to-include** | `~/source/repos/skills-research/Hill90/scripts/hooks/stop-gate.sh` (99 lines) is real, registered, and is S1's structural template *and* posture counterexample. Leaving this uncorrected costs a session |
| Closure target | seat-raw-7 (`CLOSE_TARGET_PER_WINDOW=30`) vs seat 6 + INITIAL.md | **no encoded target** | 30/30min is 1,440/day against a measured best of 61. Report the rate; let Jon set the number with that in front of him |
| Session literal counts 297/166 | INITIAL.md vs feature-analysis (304/168) vs gotchas (branches 770→414) | **none — assert a ceiling** | They drifted inside 24 hours. Count at implementation time |

---

## Implementation Blueprint

### Phase 0: Planning & understanding — BEFORE any code

1. Read `prps/estate_remediation/examples/README.md` end to end.
2. Read `example_6_pane_match_correct_vs_broken.sh`. It is the cheapest available explanation of
   the defect class this PRP remediates, and it is also T14's work item. Understand why
   `heartbeat.sh:93` is right and `:197` is wrong before writing any verification anywhere.
3. Read `docs/audit/2026-08-19-council/` — 9 files, 3,829 lines. **Primary evidence. Read before
   asserting anything.**
4. Read `AGENTS.md` invariants 3, 4, 5, 8, 9, 10.
5. Re-measure, do not inherit: session literal counts, branch count, worktree count, socket count.
6. Run `bash scripts/supervisor/ledger-snapshot.sh` (T1's output) and confirm you can read the
   ledger *before* writing any check that reads it.

### Task list (execute in order; the analyzer derives parallel groups from FILES overlap)

```yaml
Task 1: Credential exposure triage + the shared ledger snapshot reader
RESPONSIBILITY: Make the live Telegram bot token in prompts row mp-5e0dfc607d119fd4 impossible to
  miss, scrub the exported artifact, and ship the ONE sanctioned ledger read path that every later
  task depends on. This is Task 1 because a credential exposure outranks the 51, and because no
  ledger check below can be written until reading the ledger works.
FILES TO CREATE/MODIFY:
  - CREATE scripts/supervisor/ledger-snapshot.sh
  - CREATE scripts/supervisor/ledger_snapshot.py
  - CREATE scripts/supervisor/scan-corpus-secrets.sh
  - CREATE tests/supervisor/test_ledger_snapshot.sh
  - CREATE tests/supervisor/test_scan_corpus_secrets.sh
  - CREATE docs/audit/2026-08-19-council/CREDENTIAL-EXPOSURE.md
PATTERN TO FOLLOW: gotchas.md Critical 1's snapshot_ledger() verbatim; poller-recover.sh:1-148 for
  header/env/log() shape B; example_1 for the refusal that names its actuator.
SPECIFIC STEPS:
  1. Implement snapshot_ledger(): copy main + -wal + -shm to a mktemp dir, open the COPY, prove
     sqlite_master is readable, echo the path. Return 3 on any failure.
  2. Give both the .sh and .py the identical three-code contract: 0 clean / 1 violations /
     3 could-not-measure. Document it in the header exit-code block (state.sh:61-65 style).
  3. scan-corpus-secrets.sh: over a SNAPSHOT, grep prompts.text_raw for bot-token, API-key and
     private-key shapes. Report row ids, NEVER the secret value, to stdout.
  4. Write CREDENTIAL-EXPOSURE.md: the row id, the date (2026-08-11 05:50), that rotation is JON'S
     ACTION and this PRP's job is only to make it impossible to miss and to scrub the artifact, and
     that redacting the row does NOT un-expose an already-exported corpus.
  5. Scrub the exported corpus artifact. Do not touch the ledger row — that is a corpus write and
     belongs behind T27's backup.
VALIDATION:
  - positive-control: point the reader at a deliberately unreadable path; assert exit 3, not 0.
  - positive-control: plant a synthetic token in a scratch DB; assert the scanner finds it.
  - mutation-check: remove the -wal copy line; assert the reader still refuses rather than reporting
    a torn count.
  - bash scripts/supervisor/ledger-snapshot.sh "$LEDGER" prints a path and exits 0 on this machine.

Task 2: Register the owned sessions (A2)
RESPONSIBILITY: Make ownership the reaper's trigger. The sessions table holds at14-scratch-safe,
  at14-scratch-nogit, at14-scratch-busy, agent-tui, skills — three test scratch rows and two side
  projects, and NEITHER production session.
FILES TO CREATE/MODIFY:
  - CREATE scripts/supervisor/register-owned-sessions.sh
  - CREATE tests/supervisor/test_register_owned_sessions.sh
PATTERN TO FOLLOW: cli.py adopt-session — bootstrap-session.sh already calls it on every session it
  creates (test_bootstrap_session.sh:24-29), so A2's registration seam EXISTS; this is a backfill,
  not a new writer.
SPECIFIC STEPS:
  1. INSERT agent-supervisor and director via `cli.py adopt-session`, idempotently.
  2. DELETE the three at14-scratch-* rows — but INSPECT FIRST. The safe-deletion gate applies: a
     DELETE with no WHERE-guard on a table whose PK is a free-text name is one typo from removing a
     production row. Print each row before removing it; require an explicit --confirm.
  3. Leave agent-tui and skills alone; they are side projects, not scratch, and removing them is a
     scope decision this task does not own.
VALIDATION:
  - Against a scratch ledger (AGENT_SUPERVISOR_STATE_DIR), assert both production sessions present
    and zero at14-scratch-* rows.
  - positive-control: run the deletion against a scratch row named at14-scratch-DECOY and assert it
    is found and reported before removal.
  - Re-running the script is a no-op (idempotence assertion).

Task 3: Make bootstrap-session.sh repairable (gotchas Critical 4)
RESPONSIBILITY: Close the unrepairable state the reaper would otherwise inherit: --add-lanes never
  creates $SUPERVISOR_WINDOW and never calls adopt-session, so a session that lost exactly its
  supervisor window cannot be repaired at all, and a topped-up session is never registered and gets
  re-reaped forever.
FILES TO CREATE/MODIFY:
  - MODIFY scripts/supervisor/bootstrap-session.sh
  - MODIFY tests/supervisor/test_bootstrap_session.sh
PATTERN TO FOLLOW: its own :114-155 validate-before-mutate block; :219-229's documented `=` exact
  match from the real #137 bug.
SPECIFIC STEPS:
  1. Fix the :296-297 loop so --add-lanes also creates $SUPERVISOR_WINDOW when it is missing.
  2. Make --add-lanes call `cli.py adopt-session` (or make the reaper's explicit call unnecessary);
     whichever, the session must end up registered.
  3. Keep the exit-1 refusal for the human path, and make its message name what acts instead.
  4. Do NOT change the set -euo pipefail on :63 — this is the one file that has it deliberately.
VALIDATION:
  - New case: remove exactly the supervisor window, run --add-lanes, assert recovery.
  - New case: --add-lanes on a partial session leaves a `sessions` row behind.
  - mutation-check: revert the loop bound; assert the supervisor-window case goes red.
  - Existing dry-run assertion (:82-86, "created no session") still passes.

Task 4: The session reaper — the actuator that has never existed (A1)
RESPONSIBILITY: A scheduled, unattended path that creates a tmux session that does not exist.
  bootstrap-session.sh:260 and restore.sh:201 are the only two new-session calls in the estate and
  neither is invoked by any script, any LaunchAgent, or cron (crontab -l empty).
FILES TO CREATE/MODIFY:
  - CREATE scripts/supervisor/session-reaper.sh
  - CREATE tests/supervisor/test_session_reaper.sh
  - CREATE launchd/com.jonhill.session-reaper.plist
PATTERN TO FOLLOW: example_1_shell_actuator_house_style.sh; poller-recover.sh end to end — this is
  the same problem one level up the tmux object hierarchy, and its header already argues the race.
SPECIFIC STEPS:
  1. `set -uo pipefail` — NOT -e. `tmux list-sessions` with no server running exits 1, which is
     precisely the total-death case; -e would abort exactly when everything is dead.
  2. Read owned sessions from a SNAPSHOT (T1). Assert the ledger side is NON-EMPTY before
     differencing — `comm -23 <(empty) <(live)` prints nothing and exits 0.
  3. classify_session() → absent | partial | complete. Hand bootstrap-session.sh only the case it
     is built for (Critical 4). On `partial`, top up AND explicitly adopt, and if the adopt fails,
     notify: "topped up but NOT recorded in sessions -- it will be re-reaped every tick".
  4. Create with `has-session -t "=$s" || new-session -d -s "$s"`. NEVER `-A`.
  5. Reconcile stale lane claims after a rebuild: `cli.py lane-free --lane … --reason "session
     rebuilt by reaper; prior claim cannot survive a server restart"`. DO NOT restart lanes —
     AGENTS.md invariant 3 survives. The session is rebuilt; the lanes are MARKED, not resumed, and
     each freed lane's task is reported as needing redispatch, NAMING THE COMMAND.
  6. Reclaimable mkdir lock (poller-recover.sh:171-200). The reclaim is the load-bearing half.
  7. Verify AFTER acting: `has-session -t "=$s"` or notify "reported success but still absent".
  8. Plist: StartInterval, RunAtLoad true, ProcessType Background, absolute PATH (do not rely on
     the LaunchAgent PATH), NO KeepAlive.
  9. Write the S2 exemption down in the header, with its reason.
VALIDATION:
  - positive-control: create the session, tick, assert exit 0 AND that nothing was created. A reaper
    tested only on the absent case is the one that pages every three minutes forever.
  - Kill with `kill-session -t "=name"` (NEVER kill-server), tick, assert creation.
  - positive-control: point at an unreadable ledger; assert exit 3 and NO tmux mutation.
  - mutation-check: swap the guard back to `new-session -A -d`; assert the healthy-tick case goes red.
  - Test runs under TMUX_TMPDIR + assert_isolated_tmux, finishes inside test_shell_suites.py's 300s.

Task 5: poller-recover.sh must stop stamping success on a death (A3, first half)
RESPONSIBILITY: :155 returns exit 0 when the session is missing. Necessary and NOT SUFFICIENT — it
  stops the false success and repairs nothing (INITIAL.md anti-goal 5). Say so in the header.
FILES TO CREATE/MODIFY:
  - MODIFY scripts/supervisor/poller-recover.sh
  - MODIFY tests/supervisor/test_poller_recover.sh
PATTERN TO FOLLOW: its own exit-code contract block; example_1's refusal-that-names-its-actuator.
SPECIFIC STEPS:
  1. :155 → non-zero, with a message naming session-reaper.sh as what acts instead.
  2. Keep the 3-code discipline: distinguish "no session" from "could not tell".
VALIDATION:
  - New case (ZERO coverage today): missing session → non-zero exit.
  - mutation-check: restore `exit 0`; assert the case goes red.

Task 6: watchdog.sh — no_session pages, the ceiling hands off, health stops lying (A3b, A4, A5, D7)
RESPONSIBILITY: Four findings land in one file; file ownership, not logic, is the binding constraint.
FILES TO CREATE/MODIFY:
  - MODIFY scripts/supervisor/watchdog.sh
  - CREATE tests/supervisor/test_watchdog_no_session.sh
  - CREATE tests/supervisor/test_watchdog_ceiling_handoff.sh
  - MODIFY tests/supervisor/test_watchdog_staleness.sh
PATTERN TO FOLLOW: report() at :491-540 — atomic $STATUS.$$ then mv -f, mkdir -p first, fixed key
  set. Note the :522-526 trap: an `if`, not `[ ... ] && printf`, as the LAST command of a group.
SPECIFIC STEPS:
  1. A3b: do NOT write .poller-recovery-last-success and do NOT zero the fail streak
     (:1073-1082) on a tick whose state was no_session.
  2. A4: :1678's no_session branch must notify. :537-538's "escalate is the only state a human needs
     told about" is the line to change — no_session is not escalate, which is why 106 ticks paged
     nobody. The page must say no_session, not arrive as a side effect of a lane-scan parse failure.
  3. A5: on ceiling breach (147 × "3 restarts in 3600s; leaving the loop down deliberately", with
     triggers naming the cost — "idle with 154 actionable item(s)"), REBUILD THE SESSION via
     session-reaper.sh, THEN page. Hand off, do not stop.
  4. D7: health is defined as "the ledger moved" and bookkeeping moves the ledger — 37 of 83 OKs had
     0 pane-working. Add pane-working to the OK predicate. Carry the seat's own correction: it never
     printed OK with BOTH pane-working and in-flight at zero, so the check is not fully hollow.
VALIDATION:
  - positive-control: drive a no_session tick; assert a notify fires AND the success stamp file's
    mtime is unchanged.
  - mutation-check: revert the stamp guard; assert the test goes red.
  - Ceiling test asserts reaper invocation precedes the page.

Task 7: Split restore.sh --session, and fix #347 properly (A6, A7)
RESPONSIBILITY: --session is a REDIRECT, not a filter (:121 overwrites target_session per row).
  Dry-run plans 156 restores into a 10-window session; bare restore.sh resurrects five sessions
  including test session ad241repro-22535. BOTH CURRENT INVOCATIONS ARE DESTRUCTIVE BY MEASURED
  DRY-RUN. Nothing may automate restore until this lands (INITIAL.md anti-goal 3).
FILES TO CREATE/MODIFY:
  - MODIFY scripts/supervisor/restore.sh
  - CREATE tests/supervisor/test_restore_only_session.sh
  - MODIFY tests/supervisor/test_restore.sh
PATTERN TO FOLLOW: bootstrap-session.sh:96-155 — usage() re-reads the header, ${2:?...}, and EVERY
  validation before ANY mutation. restore.sh:109's refuse() and its 11 call sites for the voice.
SPECIFIC STEPS:
  1. Add --only-session as a FILTER. Keep --session as the human-only redirect, documented as such.
  2. The dry-run must exit before any new-session (:201).
  3. A7: make restore.sh able to place claude-print lanes — the transport 162 of 196 lanes actually
     run on.
  4. REPLACE #347's acceptance grep. `grep -qE "claude.print|harness_session_id|detached"` PASSES
     TODAY AGAINST UNFIXED CODE because harness_session_id appears for unrelated reasons. Replace it
     with a real placement test.
VALIDATION:
  - --only-session X emits no plan line whose lane prefix is not X.
  - positive-control: the replacement test must FAIL against the pre-fix restore.sh — demonstrate it.
  - mutation-check: restore the old grep; assert the suite no longer detects the unfixed code, and
    record that transcript as the evidence the old acceptance was vacuous.
  - Dry-run creates no session (mirror test_bootstrap_session.sh:82-86).

Task 8: Advance live/ and repoint every launchd job at it (A8) — MUST precede Task 10
RESPONSIBILITY: Four of six live jobs execute from the shared git working tree on
  fix/director-tick-fanout, 4 commits ahead of origin/main; director-loop.sh differs by 40 lines
  between that tree and live/. #366's second ask was never performed. One job executes code out of
  ~/.local/state/.../bin/ — that plist is A8 and S5 in the same file.
FILES TO CREATE/MODIFY:
  - MODIFY launchd/com.jonhill.director-loop.plist
  - CREATE launchd/com.jonhill.supervisor-watchdog.plist
  - CREATE launchd/com.jonhill.quota-watch.plist
  - CREATE launchd/com.jonhill.supervisor-heartbeat.plist
  - CREATE launchd/com.jonhill.weekly-watch.plist
  - CREATE launchd/com.jonhill.jon-report.plist
  - CREATE scripts/supervisor/check-plists-live.py
  - CREATE tests/supervisor/test_check_plists_live.py
PATTERN TO FOLLOW: launchd/com.jonhill.director-loop.plist's structure; documentation-links §2's
  bootout/bootstrap/kickstart/print sequence.
SPECIFIC STEPS:
  1. Advance live/ to a commit that IS an ancestor of origin/main.
  2. Bring all five untracked live plists into git (this is itself an instance of S5).
  3. Repoint every ProgramArguments at $SUPERVISOR_LIVE's expanded path — launchd does not expand
     variables in ProgramArguments, so the checker compares against the expanded default.
  4. `launchctl bootout gui/$UID/<label>` then `bootstrap`, then `kickstart -k`. Editing in place
     leaves the OLD ProgramArguments live.
  5. check-plists-live.py reads `launchctl print`, NOT the file, and uses `plutil -convert xml1 -o -`
     for any file parse. A parse failure is a FAILURE, never a skip.
  6. Pin Minute in any StartCalendarInterval. No KeepAlive on anything that can exit 78.
VALIDATION:
  - The checker FAILS FOUR TIMES against today's state — run it before the fix and commit that
    output. That is the positive control.
  - positive-control: plant a plist whose comment contains `--`; assert the checker reports it
    rather than skipping it (plistlib parses supervisor-watchdog fine, so the parser works).
  - After the fix: zero violations, read from launchctl print.

Task 9: The launchd exit sweep (A9, S3 first half)
RESPONSIBILITY: com.jonhill.director-loop has sat at LastExitStatus=768 (exit 3) for hours with
  nothing reading launchctl list.
FILES TO CREATE/MODIFY:
  - CREATE scripts/supervisor/launchd-sweep.sh
  - CREATE tests/supervisor/test_launchd_sweep.sh
  - CREATE launchd/com.jonhill.launchd-sweep.plist
PATTERN TO FOLLOW: documentation-links §2's awk parser; poller-recover.sh's header/log/exit contract.
SPECIFIC STEPS:
  1. Decode the raw waitpid word: `s>>8` is the exit code; negative is a signal. 768 → exit 3.
  2. DECODE 19968 (78<<8) AS A DELIBERATE EX_CONFIG REFUSAL, not a crash — or the refusal channel
     becomes the alarm channel.
  3. Page on two consecutive non-zero, not on one. Episode state, one page per episode
     (watchdog_notify.py's _load_episode/_save_episode shape).
  4. StartInterval 300. Not below 10 (silently throttled).
VALIDATION:
  - positive-control: plant a plist that exits 3; assert the sweep reports it BEFORE trusting a
    clean sweep.
  - positive-control: plant one that exits 78; assert it is reported as a refusal, not a crash.
  - mutation-check: remove the >>8 decode; assert 768 is misreported and the test goes red.

Task 10: run-from-main.sh (S2) — MUST come AFTER Task 8
RESPONSIBILITY: Nothing executes from a ref that is not an ancestor of origin/main. VIOLATED NOW.
  Landing this before A8 takes four of six LaunchAgents offline immediately (gotchas Critical 5).
FILES TO CREATE/MODIFY:
  - CREATE scripts/supervisor/run-from-main.sh
  - CREATE tests/supervisor/test_run_from_main.sh
  - MODIFY launchd/com.jonhill.director-loop.plist
  - MODIFY launchd/com.jonhill.supervisor-watchdog.plist
  - MODIFY launchd/com.jonhill.quota-watch.plist
  - MODIFY launchd/com.jonhill.supervisor-heartbeat.plist
  - MODIFY launchd/com.jonhill.weekly-watch.plist
  - MODIFY launchd/com.jonhill.jon-report.plist
PATTERN TO FOLLOW: gotchas Critical 5's wrapper verbatim.
SPECIFIC STEPS:
  1. `set -uo pipefail` — NOT -e; the script must read $? itself.
  2. On a failed `git fetch`: NOTIFY AND CONTINUE against the last-known origin/main. DO NOT exit 78.
     A network blip must not disable the only actuator that can rebuild a dead estate — that is
     verbatim the root cause this audit found.
  3. Three-way case on merge-base's rc: 0 exec, 1 refuse-and-name-the-remedy, anything else (128)
     refuse with a DIFFERENT message. A bare `if ! git merge-base` conflates them.
  4. Handle jon-report's `/bin/bash -c "a; b"` ProgramArguments form.
  5. The session reaper is EXEMPT. Write the exemption and its reason into both headers.
VALIDATION:
  - Three unit cases: ancestor → exec; non-ancestor → 78 with the remedy named; bogus ref → 78 with
    the error distinguished.
  - positive-control: simulate a fetch failure; assert the job STILL RUNS and a notify was emitted.
  - mutation-check: change the fetch-failure branch back to `exit 78`; assert the test goes red.
  - After install: `launchctl print` shows the wrapper as ProgramArguments[0] on the five wrapped
    jobs and NOT on the reaper.

Task 11: Loop-script target preflight, and the contest-stop.sh decision (A10, A13, S3 second half)
RESPONSIBILITY: director:@35, director:@3, agent-supervisor:@13 are sessions/windows that do not
  exist; the jobs fire into a void and report success. @N does not survive a server restart.
  contest-stop.sh is structurally unreachable — director-loop.sh exits 3 at :110 before the call
  at :232.
FILES TO CREATE/MODIFY:
  - CREATE scripts/supervisor/tmux-preflight.sh
  - CREATE tests/supervisor/test_tmux_preflight.sh
  - MODIFY scripts/supervisor/director-loop.sh
  - CREATE tests/supervisor/test_director_loop_preflight.sh
  - CREATE docs/decisions/contest-stop-disposition.md
PATTERN TO FOLLOW: poller-window.sh — ONE shared literal, sourced. Never a private copy (that is
  director-route.sh:149's defect, which discarded Jon's Telegram replies for a week).
SPECIFIC STEPS:
  1. tmux-preflight.sh: `has-session -t "=<sess>:<@id>"` or `list-panes -t`. NEVER `display-message`,
     which exits 0 on a nonexistent target and silently answers about the wrong one.
  2. Always the `=` prefix. Without it has-session prefix-matches a different session.
  3. Any target persisted as @N must be RE-RESOLVED BY NAME before use.
  4. Exit non-zero when the target is gone — a scheduled job that cannot reach its target must page,
     not succeed.
  5. A13 is a DECISION, not a fix: PR #390 unmerged, not on main, not in live/, 0-byte log, call site
     unreachable. Merge / delete / leave are three legitimate outcomes. Write the three options with
     their consequences; RESERVE THE CHOICE TO JON. Do not default.
VALIDATION:
  - positive-control: preflight a deliberately bogus target; assert non-zero. THE NAIVE FORM PASSES,
    so this control is what proves the fix.
  - positive-control: `has-session -t mysess` against a session named `mysession` must be rejected.
  - mutation-check: swap in `display-message -t`; assert the bogus-target case goes green (i.e. the
    test goes red), proving the guard is load-bearing.

Task 12: Session names from config, with a ceiling that can only go down (A11)
RESPONSIBILITY: 304 agent-supervisor and 168 director literals in scripts/supervisor/*.sh (measured
  today; the council said 297/166 — drifted in 24 hours). Per-project sessions were built (#111),
  worked, and every crash reverted them. Asked 14 times.
FILES TO CREATE/MODIFY:
  - MODIFY scripts/supervisor/session-defaults.sh
  - MODIFY tests/supervisor/test_session_defaults.sh
  - CREATE scripts/supervisor/check_session_literals.py
  - CREATE tests/supervisor/test_check_session_literals.py
  - CREATE .github/workflows/session-literals.yml
PATTERN TO FOLLOW: lanes_session_or_default is A11's EXISTING seam, already used at
  poller-recover.sh:128 and bootstrap-session.sh:68, already tested with two mutation checks.
SPECIFIC STEPS:
  1. Extend session-defaults.sh with the director equivalent, keeping ONE name per concept
     (poller-recover.sh:107-112 states the rule).
  2. check_session_literals.py counts literals and compares against a committed baseline file. THE
     BASELINE IS A CEILING THAT MAY ONLY DECREASE — grandfathering by count, seat 4's shape.
  3. DO NOT rewrite all 304 sites in this task. Each other task migrates the literals in the files
     it already owns; the ceiling makes the number monotonic. This is deliberate: a task touching
     every .sh file would collide with every other task and could not run in parallel with anything.
  4. Job name in the workflow must be unique (NOT `gate`).
VALIDATION:
  - positive-control: add a literal; assert the ceiling gate goes red.
  - mutation-check: make the baseline comparison `>=` instead of `<=`; assert the test goes red.
  - Extend the existing two mutation checks rather than writing a new suite.

Task 13: Test isolation must cover session NAMING, not just the socket (A12)
RESPONSIBILITY: A test harness claimed the production session name on the default socket and the
  production loop ticked it. Invariant 4 already extends the guard to session CREATION since #185;
  this is the same class with a different verb.
FILES TO CREATE/MODIFY:
  - MODIFY scripts/supervisor/tmux_verb_guard.py
  - MODIFY tests/supervisor/test_tmux_verb_guard.py
  - MODIFY scripts/supervisor/tmux-isolation.sh
PATTERN TO FOLLOW: assert_isolated_tmux (tmux-isolation.sh:3-16) and the
  `S="bootstrap-test-$$"` PID-scoped naming convention — currently a convention, NOT enforced.
SPECIFIC STEPS:
  1. Extend the existing guard rather than adding a new one.
  2. Reject a production session NAME from a test context, in addition to the existing socket guard.
  3. Keep cleanup()'s re-assertion of isolation inside the trap (test_bootstrap_session.sh:55) — a
     trap firing after an env change must not be able to address the real server.
VALIDATION:
  - positive-control: a synthetic test that claims `agent-supervisor` is rejected.
  - mutation-check: revert the name guard; assert the case goes red.

Task 14: heartbeat.sh — a verification that cannot match the text it just typed (E2, E3)
RESPONSIBILITY: :197 greps the whole pane for a string that is a substring of MSG at :149, so it
  ALWAYS reports success and :200 is unreachable. The same file gets it right at :93, 104 lines
  earlier. And #325 was closed COMPLETED with no PR and neither ask performed; its "must NOT nudge
  a healthy pane" test is unreachable because all three cases pin HEARTBEAT_STALE_AFTER=0.
FILES TO CREATE/MODIFY:
  - MODIFY scripts/supervisor/heartbeat.sh
  - MODIFY tests/supervisor/test_heartbeat.sh
  - CREATE tests/supervisor/test_heartbeat_healthy_pane.sh
PATTERN TO FOLLOW: example_6_pane_match_correct_vs_broken.sh — the correct :93 form and the fix,
  side by side, WITH the mutation test already written.
SPECIFIC STEPS:
  1. Verify against the FOOTER, not the scrollback — never a region containing your own message.
  2. Make :200 reachable and assert it.
  3. Rewrite #325's healthy-pane case with a NON-ZERO HEARTBEAT_STALE_AFTER so it can actually fail.
VALIDATION:
  - positive-control: a healthy pane must NOT be nudged, with a non-zero stale threshold.
  - mutation-check: restore the scrollback grep; assert the suite goes red. (It does not today —
    that is the finding.)

Task 15: The merge gate is a race (E1)
RESPONSIBILITY: ci_gate.py:_latest_per_name keys latest_by_name[name]; fixpass-evidence.yml:34 and
  ui-evidence.yml:26 both declare `gate:`. Demonstrated on PR #394: a real ui-evidence failure was
  discarded because fixpass succeeded three seconds later.
FILES TO CREATE/MODIFY:
  - MODIFY scripts/supervisor/ci_gate.py
  - MODIFY tests/supervisor/test_ci_gate.py
  - MODIFY .github/workflows/ui-evidence.yml
  - CREATE scripts/supervisor/check_workflow_job_names.py
  - CREATE tests/supervisor/test_check_workflow_job_names.py
  - CREATE .github/workflows/workflow-job-names.yml
PATTERN TO FOLLOW: the house gate shape — four-line workflow delegating to a tracked,
  separately-tested script; permissions least-privilege; timeout-minutes; unique job name.
SPECIFIC STEPS:
  1. Key de-duplication on (workflow, name) or the check-run id, not the name alone.
  2. Rename ui-evidence.yml's job — a one-line fix.
  3. Ship the recurrence lint: ~15 lines of stdlib Python over .github/workflows/*.yml. NO
     first-party Actions linter enforcing cross-workflow job-name uniqueness was found.
  4. The lint's own workflow job must not be named `gate`.
VALIDATION:
  - The lint FAILS TODAY against the two `gate:` declarations. Commit that run.
  - positive-control: re-introduce a duplicate name; assert red.
  - Reproduce PR #394's shape in a unit test: two same-named runs, one failing, and assert the
    failure is no longer discarded. mutation-check: revert the key; assert red.

Task 16: Tested code with zero callers is a defect (S9, E4 first half, F1's gate)
RESPONSIBILITY: acp_transport.py is 302-317 tested lines with ZERO non-test importers;
  poller-leak-cleanup.sh is 183 lines and 9 tests with ZERO callers — verbatim the anti-pattern
  test_shell_suites.py:10-12 names in the repo's own test harness.
FILES TO CREATE/MODIFY:
  - CREATE scripts/supervisor/check_module_callers.py
  - CREATE tests/supervisor/test_check_module_callers.py
  - CREATE .github/workflows/module-callers.yml
  - CREATE docs/decisions/acp-disposition.md
PATTERN TO FOLLOW: the delegated-gate shape; the grandfather-by-count ceiling from T12.
SPECIFIC STEPS:
  1. Every module under scripts/supervisor/ has ≥1 non-test importer/caller, or is on a shrinking
     grandfather list.
  2. F1 IS JON'S DECISION: he asked for ACP 23–26 times, so deleting it is not the plan's call, and
     wiring it is a design change. WHAT THIS PLAN CAN DECIDE is the gate that forbids the third
     option — leaving it parked. Write acp-disposition.md with wire/delete as the two options and
     the gate as the forcing function.
  3. Positive-control the absence check: the module list must be non-empty before any "zero
     orphans" claim (test_shell_suites.py:65-68's idiom).
VALIDATION:
  - The gate FAILS TODAY on acp_transport.py and poller-leak-cleanup.sh. Commit that run.
  - positive-control: add a synthetic orphan module; assert red.
  - mutation-check: make the importer scan include tests/; assert the gate goes green wrongly and
    the mutation test catches it.

Task 17: watchdog_notify.py — the page names the wrong subsystem, and one exemption is permanent
  (D3, D4, D5)
RESPONSIBILITY: :299 hardcodes an inbox-poll message for ALL THREE subscribers, so every heartbeat
  page ever sent named the wrong subsystem, the wrong file and the wrong threshold (600s in a
  message about a check whose real threshold is 210s). :335-341's `state: stopped` staleness
  exemption has NO AGE TERM and is live — inbox-poll.status has read `stopped` since 17:15,
  permanently suppressing the alarm. And the notify path ran on a silent fallback for two days
  (83 of 119 lines NOTIFY-PATH-STALE) — a broken config indistinguishable from a working one.
FILES TO CREATE/MODIFY:
  - MODIFY scripts/supervisor/watchdog_notify.py
  - MODIFY tests/supervisor/test_watchdog_notify.py
  - CREATE tests/supervisor/test_watchdog_notify_subsystem.py
PATTERN TO FOLLOW: example_4_notify_send_path.py — the pure decision core / thin actuator split,
  with D3/D4/D5 annotated in situ. The classifier returns a FACT; the threshold is a DECISION-TIME
  PARAMETER (:310-320 states this deliberately). Adding a subscriber = adding the quadruple.
SPECIFIC STEPS:
  1. D4: subsystem, status file and threshold become PARAMETERS of build_heartbeat_message, exactly
     as threshold_seconds already is.
  2. D5: bound the `stopped` exemption in time.
  3. D3: fix resolve_notify_script (:579). A stale notifier path must EXIT NON-ZERO and page via the
     surviving channel — never fall back silently. notify.sh:123-128 already models the refusal
     shape (it refuses rather than falling back to the production bot when QA credentials are
     missing). FIX THE PATH; DO NOT BUILD A CHANNEL — delivery is proven (88 messages during the
     outage).
VALIDATION:
  - Assert the paged threshold MATCHES THE CALLER'S for all three subscribers.
  - positive-control: a `stopped` status older than the bound must page.
  - positive-control: point the resolver at a missing notify.sh; assert non-zero, not a silent
    fallback.
  - mutation-check: restore the hardcoded message; assert red.

Task 18: events must be consumed (D1)
RESPONSIBILITY: 703 rows, 703/703 never notified, 703/703 never acked, oldest 2026-08-12. Only 209
  of 1,536 tasks (13.6%) recorded accepted_at. This is the same zero-consumer defect the codebase
  names NINE TIMES as its own proverb, and shipped again.
FILES TO CREATE/MODIFY:
  - CREATE scripts/supervisor/check_events_consumed.py
  - CREATE tests/supervisor/test_check_events_consumed.py
  - CREATE .github/workflows/events-consumed.yml
PATTERN TO FOLLOW: T1's snapshot + three-code contract; the delegated-gate shape.
SPECIFIC STEPS:
  1. Read via ledger_snapshot.py. NEVER `file:...?mode=ro` directly.
  2. Assert zero events with notified_at IS NULL older than one hour.
  3. Emit exit 3 — never 0 — when the ledger cannot be read.
VALIDATION:
  - positive-control: unreadable ledger → exit 3, and the workflow shows the gate as errored, not
    passed. THIS IS THE COMPOSITION OF CRITICALS 1 AND 2 AND IT IS THE WHOLE POINT.
  - positive-control: plant an unnotified 2-hour-old event in a scratch DB; assert exit 1.
  - mutation-check: replace the numeric validation with a bare `[ "$n" -gt 0 ]`; assert the blind
    case now passes and the test catches it.

Task 19: The report always sends, and every ask has a one-command verification (D2, F4, S5 part)
RESPONSIBILITY: The 30-minute report SUPPRESSES ITSELF WHEN NOTHING HAPPENED — the exact condition
  he most needs told about ("nothing closed in the window and every repo read cleanly -- not
  sending"). It missed the target in 0 of 38 windows and cannot tell 0/30 from 30/30; five
  consecutive reports read an identical "122 open, 65 closed today". Separately, phase-report.sh —
  13,594 bytes, the week's most visible deliverable — exists in NO REPOSITORY.
FILES TO CREATE/MODIFY:
  - CREATE scripts/supervisor/phase-report.sh
  - MODIFY scripts/supervisor/closed-report.sh
  - CREATE ASKS.tsv
  - CREATE scripts/supervisor/check_asks.sh
  - CREATE tests/supervisor/test_check_asks.sh
  - CREATE tests/supervisor/test_closed_report_always_sends.sh
  - CREATE tests/supervisor/test_phase_report.sh
PATTERN TO FOLLOW: log() shape A for launchd-invoked scripts; the refusal voice from restore.sh:109.
SPECIFIC STEPS:
  1. Always send. A zero must RENDER DIFFERENTLY from a hit — that is the requirement, not "send
     more".
  2. DO NOT ENCODE "30 issues per 30 minutes". That is 1,440/day against a measured best of 61 on
     the three days before the audit. Report the MEASURED RATE and let Jon set the number with that
     in front of him. THE PLAN SUPPLIES THE INSTRUMENT, NOT THE TARGET. (seat-raw-7 proposed
     CLOSE_TARGET_PER_WINDOW=30 with a leading MISS: 0/30; seat 6 and INITIAL.md forbid it. Taken:
     seat 6.)
  3. Reconcile with anti-goal 2 explicitly, in the header: MORE FREQUENT TRUTHFUL REPORTS, NOT MORE
     ALARMS. 88 Telegram messages were delivered during the outage; he was paged every nine minutes
     for two hours. Louder trains him to filter.
  4. Move phase-report.sh into git (S5's actual remediation, not just its gate).
  5. ASKS.tsv: each ask with a ONE-COMMAND VERIFICATION, rendered as a MANDATORY report section.
     Anything unmet >24h escalates. ("Set up a cron" produced nothing — crontab -l empty, newest
     LaunchAgent mtime three days old. Adversarial review was asked 34 times and run only under
     threat.)
VALIDATION:
  - positive-control: a window with zero closures must produce a SENT report whose zero is visually
    distinct.
  - grep the report source for the literal `30` as a target: must be absent.
  - check_asks.sh runs every verification command and fails on any unmet ask older than 24h;
    positive-control it with a synthetic unmet ask.
  - mutation-check: restore the suppression branch; assert red.

Task 20: reap.sh and the branch/worktree ceilings (S10, E4 second half)
RESPONSIBILITY: 770 branches / 346 worktrees / 416 sockets at audit; 414 / 202 / 416 measured days
  later. .watchdog-guard-audit-fail-streak = 30. And poller-leak-cleanup.sh needs a caller or a
  deletion.
FILES TO CREATE/MODIFY:
  - CREATE scripts/supervisor/reap.sh
  - CREATE tests/supervisor/test_reap.sh
  - CREATE launchd/com.jonhill.reap.plist
  - MODIFY scripts/supervisor/poller-leak-cleanup.sh
  - CREATE .github/workflows/ceilings.yml
  - CREATE scripts/supervisor/check_ceilings.sh
  - CREATE tests/supervisor/test_check_ceilings.sh
PATTERN TO FOLLOW: example_1's --dry-run discipline — the dry-run is what caught A6.
SPECIFIC STEPS:
  1. `git worktree prune -n -v` FIRST, then prune. Never `git branch -D`. `-d` refuses squash-merged
     branches (safe) and refuses a checked-out branch (a feature, with 202 worktrees pinning them).
     A MOVED worktree needs `git worktree repair`, not prune.
  2. Only remove a socket after `tmux -S "$sock" list-sessions` FAILS. Never by mtime.
  3. Thresholds 25 branches / 10 worktrees are PARAMETERS WITH DEFAULTS, marked as the council's
     numbers, not Jon's — the seat says twice that he should overrule them freely.
  4. Give poller-leak-cleanup.sh a caller here (satisfying E4 and S9 together), or delete it. State
     which and why.
  5. Pin Minute in StartCalendarInterval. NO KeepAlive.
VALIDATION:
  - positive-control: create a stale worktree admin entry in a scratch repo; assert prune reports it.
  - positive-control: create a socket whose server is alive; assert reap.sh does NOT remove it.
  - mutation-check: change `-d` to `-D`; assert the test goes red (this is the irreversible one).
  - The ceiling gate fails today. Commit that run.

Task 21: The daily "no code in state" auditor (S5 auditor half)
RESPONSIBILITY: ~/.local/state/agent-dotfiles-supervisor holds 876 top-level files, 699 markdown,
  and executes code from .../bin/. Deliverables live in git; state holds state, never code.
FILES TO CREATE/MODIFY:
  - CREATE scripts/supervisor/state-orphan-audit.sh
  - CREATE tests/supervisor/test_state_orphan_audit.sh
  - CREATE launchd/com.jonhill.state-orphan-audit.plist
PATTERN TO FOLLOW: the actuator template; the three-code exit contract.
SPECIFIC STEPS:
  1. `find ~/.local/state -name '*.sh' -o -name '*.py'` cross-checked against `git ls-files`.
  2. POSITIVE-CONTROL THE FIND. `find -newermt` matched 0 of 1,159 files in the audit and looked
     exactly like a clean result. Assert the find returns a non-empty candidate set before reporting
     zero orphans.
  3. Pin Minute in StartCalendarInterval.
VALIDATION:
  - positive-control: plant an untracked .sh under a scratch state dir; assert it is reported.
  - positive-control: point at an empty directory; assert exit 3 (cannot measure), NOT exit 0.
  - mutation-check: remove the non-empty assertion; assert the blind case passes and the test
    catches it.

Task 22: THE HOOK SPIKE — two unresolved questions, answered empirically, BEFORE any hook installs
RESPONSIBILITY: Two questions are genuinely unresolved and NEITHER IS DOCUMENTED. Guessing either
  one wrong installs a guard that looks installed and is not, on 162 lanes. DO NOT GUESS.
  (a) Does `${CLAUDE_PROJECT_DIR}` expand in a USER-GLOBAL ~/.claude/settings.json? It is
      project-scoped and does not exist for a user-global hook (codebase-patterns, File
      Organization, "no existing pattern resolves this"). If it does not expand, the hook command
      must be an absolute path into a repo checkout — which collides head-on with S2 and A8's live/
      rule, and that collision must be resolved before T23 writes the installer.
  (b) Does a MISSING or UNREADABLE Stop hook script fail open or closed? This repo lost a guard to
      fail-open once already (test_protect_shared_checkout.sh:8-13). gotchas.md states plainly it
      COULD NOT CHECK whether `claude -p` honours a user-global Stop hook at all.
FILES TO CREATE/MODIFY:
  - CREATE scripts/supervisor/hook-spike.sh
  - CREATE docs/audit/2026-08-19-council/hook-spike-results.md
PATTERN TO FOLLOW: "verify the instrument before you believe the verdict" — this whole task is that
  rule applied to a mechanism nobody in the estate has run.
SPECIFIC STEPS:
  1. Install a NO-OP marker hook in a BACKED-UP copy of ~/.claude/settings.json; run ONE `claude -p`
     lane; observe whether the marker fired. COSTED DRY RUN ON ONE LANE — not 162.
  2. Test ${CLAUDE_PROJECT_DIR} expansion from the user-global file directly.
  3. Test a deliberately missing hook path; record open vs closed.
  4. Record all three answers with the exact commands and outputs. Restore the backup.
  5. If (a) says the variable does not expand, T23's installer writes absolute paths AND T23 must
     carry the S2/live/ reconciliation explicitly.
VALIDATION:
  - hook-spike-results.md contains a command and its OUTPUT for each question. A conclusion without
    output does not count.
  - ~/.claude/settings.json is byte-identical to its pre-spike backup afterwards.

Task 23: The four hooks and their installer (S1, S2 SessionStart, S4 preventer, S5 preventer)
RESPONSIBILITY: ~/.claude/settings.json has no `hooks` key. It is a SHARED SURFACE and its edits
  cannot be parallelised — one task owns all four. DEPENDS ON TASK 22.
FILES TO CREATE/MODIFY:
  - CREATE .claude/check_stop_authorized.sh
  - CREATE .claude/check_quote_policy.sh
  - CREATE .claude/no_code_in_state.sh
  - CREATE .claude/assert_from_main.sh
  - CREATE scripts/supervisor/install-claude-hooks.sh
  - CREATE scripts/supervisor/uninstall-claude-hooks.sh
  - CREATE tests/supervisor/test_hook_wiring.sh
  - CREATE tests/supervisor/test_check_stop_authorized.sh
  - CREATE tests/supervisor/test_check_quote_policy.sh
  - CREATE tests/supervisor/test_no_code_in_state.sh
  - CREATE tests/supervisor/test_assert_from_main.sh
PATTERN TO FOLLOW: example_3_claude_code_hooks.sh; .claude/protect-shared-checkout.sh (this repo's
  only hook — FLAT, not in .claude/hooks/; inventing that subdirectory is what broke the last one);
  test_protect_shared_checkout.sh's TWO-PART test shape.
SPECIFIC STEPS:
  1. Parse stdin with `python3 -c`, NOT jq. Two hook families on this machine disagree (this repo
     uses python3, Hill90 uses jq); the estate's stdlib-only rule decides it. Say so in the headers.
  2. S1 (Stop): honour stop_hook_active FIRST; scope by cwd to the supervisor repo; FAIL CLOSED on
     blindness. Hill90's stop-gate.sh is the structural template AND the posture counterexample —
     it fails open on four unreadable-input paths, which for "the agent may not go quiet" is exactly
     backwards.
  3. S4: matcher "Bash" (+ `if: "Bash(gh *)"`), and matcher "Write|Edit". The command inspection
     happens INSIDE the script against tool_input.command — a matcher can only see the tool name.
     Deterministic profanity + attributed-quote grep. exit 2 blocks.
  4. S5: PreToolUse on Write|Edit, NOT PostToolUse. PostToolUse fires after the write and undoes
     nothing. Reject ~/.local/state/** paths starting `#!` or ending .sh/.py.
  5. S2: SessionStart hook. Note exit 2 does NOT block on SessionStart — its stdout is plain text
     injected into context. It informs; run-from-main.sh enforces.
  6. Every block message NAMES WHAT ACTS INSTEAD (protect-shared-checkout.sh:39-50's shape —
     "Use a worktree instead: git worktree add …"). That is the 11th invariant already in the estate.
  7. Installer: idempotent, backs up the existing file, VALIDATES THE JSON BEFORE WRITING (a
     corrupted user-global settings.json breaks every Claude session on the machine), and ships an
     uninstaller. Not a manual edit.
  8. Guard against profile output corrupting hook JSON.
VALIDATION:
  - THE WIRING HALF IS NON-NEGOTIABLE: read the command out of the REAL ~/.claude/settings.json,
    resolve it, assert the file exists and is executable. AN UNWIRED HOOK IS INDISTINGUISHABLE FROM
    A COMPLIANT ESTATE.
  - S1 drive-table: stop_hook_active=true → 0; lane cwd → 0; empty transcript → 2.
  - positive-control: synthetic profane attributed quote → exit 2; a clean one → exit 0.
  - positive-control: a Write to ~/.local/state/x.sh → exit 2; a Write to $REPO/x.sh → exit 0.
  - COSTED DRY RUN ON ONE LANE before installing globally (Task 22's result gates this).
  - mutation-check: point settings.json at a nonexistent script; assert the wiring test goes red.
  - Uninstaller restores the pre-install file byte-for-byte.

Task 24: The three live public S4 violations
RESPONSIBILITY: THE ONLY ITEM IN THIS PRP WHOSE DAMAGE CANNOT BE UNDONE. agent-dotfiles issues #237,
  #174 and PR #55 — in a PUBLIC repo — quote Jon with profanity. A sweep of 483 issues, 465 PRs and
  1,303 comments found exactly these three and zero in the other repos. The hook (T23) prevents new
  ones; THESE MUST BE EDITED.
FILES TO CREATE/MODIFY:
  - CREATE docs/decisions/s4-public-remediation.md
PATTERN TO FOLLOW: the irreversible-actions gate — Jon's explicit go, original text preserved in a
  private note FIRST.
SPECIFIC STEPS:
  1. Write the runbook: the three artifact URLs, the exact edit, and the preserve-first step.
  2. THE EDIT ITSELF REQUIRES JON'S EXPLICIT AUTHORISATION. Do not perform it from this PRP.
  3. Record that edit history is visible on GitHub, so the remediation reduces prominence, not
     existence.
VALIDATION:
  - The doc names all three artifacts and the private-preservation location.
  - After Jon's go: re-run T23's quote scanner against the three artifacts; assert clean.

Task 25: Ledger schema — the interrogative trigger, provenance, possibility_count, and the two dead
  writers (S6 mechanism, C2 mechanism, C4, C8 wiring, plus acked_at and resolved_to)
RESPONSIBILITY: One task owns core.py, because five schema concerns land in it and file ownership is
  the binding constraint on parallelism.
FILES TO CREATE/MODIFY:
  - MODIFY scripts/supervisor/core.py
  - MODIFY tests/supervisor/test_core.py
  - CREATE tests/supervisor/test_core_interrogative_trigger.py
PATTERN TO FOLLOW: example_5_sqlite_migration_and_trigger.py; core.py's own
  _migrate_source_tasks_pull_uniqueness — the failpoint= seam, the PRAGMA table_info probe, the
  table rebuild, BEGIN IMMEDIATE + rollback, and :1136-1144's REFUSE-ON-PRE-EXISTING-VIOLATION.
  THERE IS NO migrations/ DIRECTORY. A new migration is a new _migrate_* method plus a line in
  __init__ around :271-274.
SPECIFIC STEPS:
  1. S6 trigger: GLOB only, NEVER REGEXP (Python's sqlite3 has none; the trigger would brick every
     INSERT including honest ones, and core.py is the writer). Write `'*[?]'`, never `'*?'`.
     RAISE(ABORT), never IGNORE (silently drops — this audit's own defect) and never ROLLBACK.
  2. A PRE-FLIGHT CONTAMINATION SCAN IS MANDATORY. A trigger binds FUTURE inserts only; CREATE
     TRIGGER succeeds over the contaminated rows and reports nothing. Refuse to install until the
     scan is clean or the rows are grandfathered BY COUNT so the number can only go down.
  3. PUBLISH THE COUNT THE PINNED LITERAL PRODUCES AT LANDING. Do not cite 209, 305 or 581 as
     settled — the disagreement IS a disagreement about this literal.
  4. provenance: `ALTER TABLE prompts ADD COLUMN provenance TEXT NOT NULL DEFAULT 'unknown'
     CHECK (provenance IN ('human','agent','unknown'))`. NOT NULL requires a DEFAULT. 'unknown' is
     the honest value — it distinguishes "not yet backfilled" from "human", and defaulting to
     'human' would assert the very thing C6 says is false. Tightening later needs the 12-step
     rebuild, which core.py:767-803 already models.
  5. C4: possibility_count is COUNT(*) FROM live_parameters WHERE weight='hard' = 920 — a count of
     his constraints under the name of the solution space. EITHER MAKE IT COUNT POSSIBILITIES OR
     RENAME IT TO WHAT IT COUNTS. Note it always returns exactly one row, unlike conflicts.
  6. Wire update_text_clean (:3321) — one definition, one test call, ZERO production callers.
  7. Wire record_link (:3358) for T29's comparator — zero non-test callers today.
  8. acked_at is non-NULL on 1 of 5,544 rows; 386 of 387 acknowledged rows have no timestamp, so no
     item's lifecycle can be dated. 81 of 920 hard live parameters have resolved_to IS NULL — a
     parameter that resolves to nothing, inside the number reported to Jon. Both are [INFERRED],
     not in INITIAL.md's 51; fix the write path so new rows are dated and non-null.
  9. The RAISE(ABORT) message text is LOAD-BEARING (:1061-1065 — callers match on it). Choose it
     deliberately and assert it.
VALIDATION:
  - positive-control: synthetic hard-from-question insert RAISES, FROM A FRESH CONNECTION, not the
    migration's.
  - positive-control: a legitimate non-interrogative hard insert SUCCEEDS from that same fresh
    connection. (Without this, the GLOB '*?' bug ships silently.)
  - positive-control: the pre-flight scan refuses over planted contamination.
  - mutation-check: swap GLOB for REGEXP; assert every INSERT fails and the test catches it.
  - mutation-check: swap '*[?]' for '*?'; assert the legitimate-insert case goes red.
  - failpoint= crash-safety cases mirroring the existing migrations'.

Task 26: itemize_prompts.py — the model may propose body, never kind or weight (C3, S6 second half)
RESPONSIBILITY: --load reads a JSON array "produced BY A MODEL" (its own docstring) and writes kind
  and weight VERBATIM WITH NO LOGIC — while that same docstring quotes Jon saying it should be a
  tool, not inference.
FILES TO CREATE/MODIFY:
  - MODIFY scripts/supervisor/itemize_prompts.py
  - MODIFY tests/supervisor/test_itemize_prompts.py
PATTERN TO FOLLOW: the same pinned classifier as T25's trigger — ONE literal, shared, never a
  private copy (director-route.sh:149 is what a private copy costs).
SPECIFIC STEPS:
  1. kind and weight become DETERMINISTIC, computed by the same pinned classifier the trigger uses.
  2. The model may only propose `body`.
  3. NOTE: the prior execution plan's U29 assigns this work to scripts/supervisor/ingest_prompts.py,
     WHICH DOES NOT EXIST. The ingest surface is mine_prompts.py / itemize_prompts.py.
VALIDATION:
  - positive-control: a model payload asserting weight='hard' on an interrogative body must produce
    a non-hard row, or be refused by the trigger. Assert which.
  - mutation-check: restore the verbatim passthrough; assert red.

Task 27: The corpus repair — the only WRITE to a read-only database (C2, C5, C6, C7, C8, C9)
RESPONSIBILITY: THE LEDGER IS READ ONLY EXCEPT HERE. This deletes 1,057 rows and rewrites ~588 of
  Jon's own words. His most consequential instructions are ABSENT (`make me look good` → 0 rows;
  the "close 30 issues" demand → absent; the star-skills-for-fabric ask → absent, though the repo
  was starred anyway, so the action happened outside the record). Seven rows dated 2026-08-19 are
  third-person paraphrase. 1,057 rows (29%) come from hill90-app, a repo he excluded TWICE. Grammar
  repair is 4.9% done. ~22% of his messages were NEVER INGESTED — ingestion stopped ~2026-08-18T03:00
  and never resumed; ALL 63 messages of 2026-08-19 are absent, including every escalation.
FILES TO CREATE/MODIFY:
  - CREATE scripts/supervisor/corpus-backup.sh
  - CREATE scripts/supervisor/corpus-repair.sh
  - MODIFY scripts/supervisor/mine_prompts.py
  - CREATE tests/supervisor/test_corpus_backup.sh
  - CREATE tests/supervisor/test_corpus_repair.sh
  - CREATE docs/decisions/corpus-repair-authorisation.md
PATTERN TO FOLLOW: the safe-deletion skill's gate — look at the target before removing it; and
  example_1's --dry-run.
SPECIFIC STEPS:
  1. corpus-backup.sh: back up, THEN RESTORE THE BACKUP INTO A TEMP DB AND COUNT. Do not trust the
     file's existence. This runs and passes before any write.
  2. Re-ingest is the approach, not in-place edit: ~22% were never ingested, 1,057 must go, 7 are
     paraphrase, and there was no provenance column — an in-place repair CANNOT produce a provably
     verbatim corpus (S7), which is the stated acceptance. [ASSUMPTION, confidence medium, named as
     such because INITIAL.md describes deletes and rewrites, not a rebuild.]
  3. NEVER OVERWRITE text_raw. core.py says it is never altered after insert, and it is the evidence
     other claims are settled against. Write to a new column/table.
  4. Re-weight the interrogative-sourced hard items using the SAME pinned classifier. Publish the
     count. Many have been ACTED ON (140 of the 305) — that is a fact to record, not to reverse.
  5. Restart ingestion and backfill 2026-08-18T03:00 → now.
  6. Wire update_text_clean (T25 exposes it) so grammar repair moves materially above 4.9%.
  7. Scrub the credential row identified in T1.
  8. THE EXECUTION IS JON'S AUTHORISATION, not this plan's. Build the procedure, the verified backup
     and the verification; the doc records what will be deleted and rewritten and asks.
VALIDATION:
  - The backup is RESTORED AND COUNTED, and that count is asserted, before any write.
  - --dry-run prints every intended delete and rewrite and mutates nothing.
  - positive-control: run the repair against a scratch copy; assert row deltas exactly.
  - mutation-check: remove the restore-and-count step; assert the suite goes red.

Task 28: The corpus is provably verbatim and provably complete (S7)
FILES TO CREATE/MODIFY:
  - CREATE scripts/supervisor/check_corpus_verbatim.py
  - CREATE tests/supervisor/test_check_corpus_verbatim.py
  - CREATE .github/workflows/corpus-verbatim.yml
PATTERN TO FOLLOW: T1's snapshot; the delegated-gate shape; three-code exit contract.
SPECIFIC STEPS:
  1. Every real user message has a byte-for-byte prompts.text_raw; every text_raw is an EXACT
     SUBSTRING of some source .jsonl.
  2. Assert the three named missing instructions are present.
  3. Assert zero paraphrase rows and zero hill90-app rows.
  4. Unique job name; timeout-minutes.
VALIDATION:
  - positive-control: plant a paraphrase row in a scratch DB; assert exit 1.
  - positive-control: unreadable ledger → exit 3.
  - The gate FAILS TODAY. Commit that run; it is the before-picture for T27.

Task 29: Make the conflict detector able to fire, and prove it (S8, C1)
RESPONSIBILITY: `links` has ZERO rows, so the `conflicts` view is STRUCTURALLY INCAPABLE of
  returning a row — both joins are INNER; no LEFT JOIN, no UNION, no aggregate. It has never fired
  and could never have fired, AND IT WAS CITED AS PROOF OF CONSISTENCY, TO JON'S PHONE. Its only
  writer, record_link() at core.py:3358-3367, has zero non-test callers.
FILES TO CREATE/MODIFY:
  - CREATE scripts/supervisor/link_comparator.py
  - CREATE tests/supervisor/test_link_comparator.py
  - CREATE .github/workflows/links-nonempty.yml
PATTERN TO FOLLOW: deterministic comparator over resolved_to keys — replace the never-run LLM
  linker. Delegated-gate shape.
SPECIFIC STEPS:
  1. Deterministic comparator; call record_link (wired in T25).
  2. Gate: if count(items) > 500 and count(links) = 0, FAIL.
  3. THE POSITIVE CONTROL IS THE ACCEPTANCE, NOT THE ROW COUNT. Plant a known conflict; assert
     `conflicts` returns it.
VALIDATION:
  - positive-control: planted conflict → conflicts returns a row. Without this, a non-empty links
    table proves nothing about whether the view can fire.
  - positive-control: unreadable ledger → exit 3, never a green "0 conflicts".
  - mutation-check: empty the links table; assert the gate goes red.

Task 30: A blind quota meter must HALT dispatch, not license it (D6)
RESPONSIBILITY: Unreadable 86% of the time (80 of 93 consultations), `confirmed: SAFE` retained
  through UNKNOWN. No stand-down path exists at all — `grep -ciE 'stand-down|rate limit|usage limit'
  watchdog.log` = 0. On 2026-08-15 this burned $80 of usage credits down to $8.
FILES TO CREATE/MODIFY:
  - MODIFY scripts/supervisor/quota-watch.sh
  - CREATE scripts/supervisor/quota-standdown.sh
  - CREATE tests/supervisor/test_quota_standdown.sh
  - MODIFY tests/supervisor/test_quota_watch_blind_alarm.sh
PATTERN TO FOLLOW: the three-code exit contract — UNKNOWN is exit 3, not a SAFE reading.
SPECIFIC STEPS:
  1. Two consecutive UNKNOWN readings decay `confirmed` to UNSAFE.
  2. UNSAFE writes a quiesce flag that dispatch consumes (T31 reads it).
  3. Never retain a stale SAFE through an UNKNOWN.
VALIDATION:
  - Unit test drives UNKNOWN → UNSAFE → lanes-quiesced.
  - positive-control: make the meter unreadable; assert stand-down, NOT a retained SAFE.
  - mutation-check: restore the SAFE retention; assert red.

Task 31: dispatch — permissions, quiesce, and the ACP question (F1 consumer, F3)
RESPONSIBILITY: --dangerously-skip-permissions on 132 lanes BY DEFAULT, never requested; it is the
  supervisor's own default (open issue #379). And 162 of 196 lanes ran on headless `claude -p` — a
  transport nobody asked for, replacing the persistent tmux lanes he specified. He asked for ACP
  23–26 times across 9 days and reverse-engineered this himself on day ten.
FILES TO CREATE/MODIFY:
  - MODIFY scripts/supervisor/dispatch.sh
  - MODIFY scripts/supervisor/dispatch-claude-print.sh
  - MODIFY tests/supervisor/test_dispatch.sh
  - CREATE tests/supervisor/test_dispatch_quiesce.sh
SPECIFIC STEPS:
  1. Consume T30's quiesce flag: a blind meter halts dispatch.
  2. F3 IS JON'S DECISION — flipping the --dangerously-skip-permissions default changes the blast
     radius of every dispatch IN BOTH DIRECTIONS. Make it a documented, single-source flag with the
     current value preserved, and surface the choice. Do not flip it unilaterally.
  3. F1's disposition is T16's doc plus Jon's call. This task only stops the transport choice from
     being invisible: log which transport each lane used, so "162 on claude -p" is readable without
     an audit.
VALIDATION:
  - positive-control: set the quiesce flag; assert dispatch refuses AND NAMES WHAT CLEARS IT.
  - mutation-check: remove the quiesce read; assert red.

Task 32: A refusal must name what acts instead (F5, and AGENTS.md's 11th invariant)
RESPONSIBILITY: 43 code sites whose terminal action is a string. `a human should look` appears in
  FOUR scripts and is written to a file with no reader — watchdog.log, 18,900+ lines, zero readers.
FILES TO CREATE/MODIFY:
  - MODIFY AGENTS.md
  - CREATE scripts/supervisor/check_refusal_actuator.py
  - CREATE tests/supervisor/test_check_refusal_actuator.py
  - CREATE .github/workflows/refusal-actuator.yml
PATTERN TO FOLLOW: restore.sh:109's refuse() voice; protect-shared-checkout.sh:39-50's
  "Use a worktree instead: …" — the 11th-invariant shape ALREADY IN THE ESTATE.
SPECIFIC STEPS:
  1. Add invariant 11: *a refusal must name what acts instead, and NO REFUSAL MAY SIT BETWEEN TOTAL
     DEATH AND THE ACTUATOR THAT FIXES IT.*
  2. Grandfather the 43 existing sites BY COUNT so the number can only go down. Re-count at
     implementation time; do not hardcode 43.
  3. Document the four mechanisms in THIS PLAN that re-create the anti-pattern and their explicit
     exemptions: run-from-main.sh gating the reaper; `set -e` in the reaper; the S1 Stop hook failing
     open; the ledger snapshot failing and the reaper defaulting to "nothing to do".
VALIDATION:
  - positive-control: add a synthetic bare refusal; assert the ceiling goes red.
  - mutation-check: make the baseline comparison permissive; assert red.

Task 33: Point the estate back at the product (G1, G3)
RESPONSIBILITY: 357 machinery PRs merged, 0 commits to product main. 713 of 1,536 lifetime tasks
  cancelled (46.4%); 100 stuck in `delivered`. Hill90 main still sits at c34a6c45, dated 2026-08-09
  — BEFORE the engagement began. Phase 4 (the interface) is where lanes should be; supervisor
  internals are justified only when they demonstrably block Phase 4, AND THE BLOCK MUST BE NAMED.
FILES TO CREATE/MODIFY:
  - CREATE scripts/supervisor/check_machinery_ratio.py
  - CREATE tests/supervisor/test_check_machinery_ratio.py
  - CREATE .github/workflows/machinery-ratio.yml
  - CREATE docs/decisions/product-first.md
SPECIFIC STEPS:
  1. Measure and REPORT the machinery:product commit ratio. Report the rate; do not encode a target
     (same discipline as T19).
  2. product-first.md: a supervisor-internals PR must NAME the Phase 4 item it unblocks.
  3. Land at least one commit on a product main — that is the criterion the whole audit turns on.
VALIDATION:
  - The gate reads 357:0 today. Commit that.
  - positive-control: unreadable git history → exit 3, not a green ratio.

Task 34: The record of what is deferred, contested, unenforceable and Jon's (F2 DEFERRED, G2, plus
  the meta-record)
RESPONSIBILITY: An omission reads as an oversight to the next reader. Everything not built must be
  named as not built, WITH ITS REASON.
FILES TO CREATE/MODIFY:
  - CREATE docs/decisions/unenforceable-rules.md
  - CREATE docs/decisions/deferrals.md
  - CREATE docs/decisions/contested-measurements.md
  - CREATE docs/decisions/jon-decides.md
SPECIFIC STEPS:
  1. unenforceable-rules.md — TWO rules, recorded as unenforceable rather than papered over:
     "research before asserting" (no hook distinguishes a claim from weights from a claim from a
     page) and "ask a council before concluding" (a hook can prove a call happened, NOT that the
     reviewer had a lens it could fail on — that one is PARTIAL, not zero, and must be described
     that way). DO NOT CLAIM COVERAGE FOR EITHER.
  2. deferrals.md — **F2, chain of command, IS DEFERRED.** Reason: never attempted; no `role`,
     `tier`, `parent_lane` or `reports_to` exists anywhere; --supervisor-lane's only consumer is a
     string comparison at cli.py:962; dispatch.sh picks lanes by freeness; "supervisor" survives
     only as a tmux window name. Building a hierarchy is a DESIGN decision requiring Jon, and Group
     G says the estate must stop spending itself on itself. It is named here as deferred, with the
     evidence, not dropped. Also record A13 (contest-stop.sh) as a decision awaiting Jon and G2
     (agent-tui visibility) as reserved to him in the corpus itself.
  3. contested-measurements.md — 209/305/581 with each classifier, and 29.6/40.5/62.6/78% with each
     method. STATE THE METHOD WITH THE NUMBER, EVERY TIME.
  4. jon-decides.md — the eight items this plan must not decide: the issue-closure number; the 25/10
     ceilings; the corpus deletion authorisation; agent-tui visibility; what ships if the budget is
     exhausted (seat 6 names S1–S5 as the enforcement budget); whether ACP is wired or deleted;
     the --dangerously-skip-permissions default; contest-stop.sh's disposition.
VALIDATION:
  - Cross-check: every one of the 51 findings appears in exactly one task's RESPONSIBILITY or in
    deferrals.md with a reason. Nothing silently dropped.

Task 35: The evidence vocabulary (meta-criteria enforcement)
RESPONSIBILITY: `grep -rn 'mutation-check:\|positive-control:' tests/` must be the committed
  evidence the meta-criteria demand. NEITHER STRING EXISTS IN THE TREE TODAY (grepped: zero
  matches). The technique exists; the vocabulary does not, so future greps find nothing.
FILES TO CREATE/MODIFY:
  - CREATE tests/supervisor/test_evidence_labels.py
PATTERN TO FOLLOW: test_shell_suites.py:65-68's non-empty-glob assertion — the estate's own
  positive-control idiom, in Python.
SPECIFIC STEPS:
  1. Assert every new gate script has at least one `mutation-check:` case and at least one
     `positive-control:` case in its suite.
  2. Assert the label glob is NON-EMPTY before asserting anything about it.
VALIDATION:
  - positive-control: point the scan at an empty directory; assert failure, not a vacuous pass.
  - mutation-check: remove a label from one suite; assert red.
```

### Implementation pseudocode — the three shapes every task reuses

```bash
# ── Shape 1: any ledger reader (T1, T4, T18, T28, T29, and every auditor) ─────────────
# Pattern from: gotchas.md Critical 1 + 2, composed.
main() {
  SNAP="$(snapshot_ledger "$LEDGER")" || {
    log "REFUSED: cannot snapshot ledger -- not reporting a count I could not read.
         Fix: check $LEDGER exists and its directory is writable, then re-run."   # names the actuator
    exit 3; }                                                    # 3 = could not measure, NEVER 0
  n=$(sqlite3 "$SNAP" "$QUERY") || { echo "::error::query failed"; exit 3; }
  case "$n" in ''|*[!0-9]*) echo "::error::non-numeric [$n] -- instrument blind"; exit 3 ;; esac
  if [ "$n" -gt 0 ]; then echo "::error::$n violations"; exit 1; fi
  echo "0 violations (instrument verified readable)"; exit 0
}

# ── Shape 2: the reaper body (T4) ─────────────────────────────────────────────────────
# Pattern from: example_1 + gotchas Criticals 3 and 4. set -uo, NOT -e.
for s in $(owned_sessions_from_snapshot); do            # asserted non-empty first (gotcha 23)
  case "$(classify_session "$s")" in                    # absent | partial | complete
    complete) continue ;;
    absent)   bootstrap-session.sh --session "$s" --lanes "$LANES" ;;
    partial)  bootstrap-session.sh --session "$s" --lanes "$LANES" --add-lanes
              cli.py adopt-session --session "$s" --source session-reaper.sh \
                || notify "reaper: '$s' topped up but NOT recorded -- it will be re-reaped every tick" ;;
  esac
  tmux has-session -t "=$s" 2>/dev/null \
    || { notify "REAPER reported success but '$s' still absent"; exit 1; }
  for lane in $(claimed_lanes_for "$s"); do             # invariant 3 survives: MARK, do not resume
    cli.py lane-free --lane "$lane" --reason "session rebuilt by reaper; prior claim cannot survive
                                              a server restart"
    report_needs_redispatch "$lane"                     # names the command, never orphans silently
  done
done

# ── Shape 3: any new CI gate (T12, T15, T16, T18, T20, T28, T29, T32, T33) ────────────
# Workflow is FOUR LINES and delegates. Never inline a run: assertion — that re-opens the
# !-negated-pipeline trap AND removes the check from `unittest discover`.
jobs:
  corpus-verbatim:                     # UNIQUE across ALL workflow files. Never `gate`.
    timeout-minutes: 10                # every new job gets one
    steps: [checkout@v5, setup-python@v6 (3.12),
            run: python3 scripts/supervisor/check_corpus_verbatim.py]
# and the script itself uses Shape 1's three-code contract.
```

### Integration points

```yaml
LEDGER (SQLite, ~/.local/state/agent-dotfiles-supervisor/ledger.sqlite3):
  - migration: new _migrate_* methods on core.py + a line in __init__ (~:271-274). NO migrations/ dir.
  - trigger:   items_no_hard_from_question, BEFORE INSERT, GLOB only, RAISE(ABORT), preceded by a
               mandatory pre-flight contamination scan.
  - column:    prompts.provenance TEXT NOT NULL DEFAULT 'unknown' CHECK (IN human/agent/unknown)
  - rows:      sessions += agent-supervisor, director;  sessions -= at14-scratch-* (inspect first)
  - access:    ledger-snapshot.sh / ledger_snapshot.py ONLY. Never file:...?mode=ro. Never immutable=1.

LAUNCHD (~/Library/LaunchAgents/com.jonhill.*):
  - order:     advance live/ -> repoint (A8) -> launchctl print verify -> THEN wrap (S2)
  - new jobs:  session-reaper (RunAtLoad true), launchd-sweep (StartInterval 300),
               reap + state-orphan-audit (StartCalendarInterval WITH Minute PINNED)
  - never:     KeepAlive on anything that can exit 78; StartInterval < 10
  - reload:    bootout -> bootstrap -> kickstart -k;  verify with `launchctl print`, not the file

HOOKS (~/.claude/settings.json — USER-GLOBAL, outside every repo):
  - gated by:  Task 22's spike. Do not write the installer before its two answers exist.
  - installer: idempotent, backs up, validates JSON before writing, has an uninstaller
  - events:    Stop (S1) / PreToolUse Bash+Write|Edit (S4) / PreToolUse Write|Edit (S5, NOT Post) /
               SessionStart (S2, informational — exit 2 does not block there)

CI (.github/workflows/):
  - 7 new workflows, each 4 lines, each delegating, each with a UNIQUE job name and timeout-minutes
  - ui-evidence.yml's `gate` job renamed (E1)

NOTIFY:
  - fix the path (watchdog_notify.py:568-608), do NOT build a channel. Delivery is proven.
```

---

## Validation Loop

### Level 1: Syntax & style

```bash
# Shell — every new and modified script
for f in scripts/supervisor/*.sh .claude/*.sh; do bash -n "$f" || echo "SYNTAX FAIL: $f"; done
command -v shellcheck >/dev/null && shellcheck -S warning scripts/supervisor/*.sh .claude/*.sh

# Python — stdlib only; DO NOT introduce a dependency
python3 -m py_compile scripts/supervisor/*.py tests/supervisor/*.py

# plists — plutil, NOT plistlib (it cannot parse 5 of 6; `--` in an XML comment)
for p in launchd/*.plist ~/Library/LaunchAgents/com.jonhill.*.plist; do plutil -lint "$p"; done

# The user-global settings file — a corrupt one breaks every Claude session on this machine
python3 -c 'import json,sys;json.load(open(sys.argv[1]))' ~/.claude/settings.json && echo "JSON ok"

# House-style conformance
grep -Ln 'set -uo pipefail' scripts/supervisor/*.sh    # expect only bootstrap-session.sh (-euo, deliberate)
grep -rn '^\s*!' .github/workflows/*.yml scripts/supervisor/*.sh   # expect ZERO — the 5½-month trap
grep -rn 'new-session -A' scripts/supervisor/            # expect ZERO — Critical 3
grep -rn 'mode=ro' scripts/supervisor/ | grep -v ledger_snapshot   # expect ZERO — Critical 1
grep -rn 'immutable=1' scripts/supervisor/               # expect ZERO — it lies under a writer
grep -rn "has-session -t [^=\"']" scripts/supervisor/    # expect ZERO — the '=' prefix is mandatory
grep -rn 'display-message.*-t' scripts/supervisor/       # expect ZERO as a preflight — it exits 0
grep -rn "GLOB '\*?'" scripts/supervisor/                # expect ZERO — must be '*[?]'
grep -rn 'REGEXP' scripts/supervisor/core.py             # expect ZERO — bricks every INSERT
grep -rn 'kill-server' scripts/ tests/                   # expect ZERO — it destroyed the estate 3x
grep -rn 'branch -D' scripts/supervisor/reap.sh          # expect ZERO — never automate -D
```

### Level 2: Unit and shell suites

```bash
# The whole suite. 109 shell suites exist today; test_*.sh is auto-discovered — NO registration step.
python3 -m unittest discover -s tests -v

# Individual new suites, run directly while iterating:
bash tests/supervisor/test_ledger_snapshot.sh
bash tests/supervisor/test_session_reaper.sh
bash tests/supervisor/test_hook_wiring.sh
bash tests/supervisor/test_restore_only_session.sh
python3 -m unittest tests.supervisor.test_core_interrogative_trigger -v
python3 -m unittest tests.supervisor.test_check_plists_live -v

# Every tmux-touching suite MUST run isolated and MUST finish inside test_shell_suites.py's 300s:
#   unset TMUX; export TMUX_TMPDIR=$(mktemp -d); assert_isolated_tmux || exit 1
#   ... ; tmux -L testsock kill-session -t "=$S"   # exact match; NEVER kill-server
# Ledger-touching suites MUST redirect: export AGENT_SUPERVISOR_STATE_DIR=$(mktemp -d)
```

### Level 3: Integration — the real system, not a stub

```bash
# ── 3a. The reaper actually recreates a real session (A1's whole point) ───────────────
export TMUX_TMPDIR=$(mktemp -d /tmp/reaper-int.XXXXXX)
tmux -L int new-session -d -s prodlike
bash scripts/supervisor/session-reaper.sh --session prodlike; echo "healthy tick rc=$?"   # want 0
tmux -L int has-session -t '=prodlike' && echo "still exactly one session"                # want yes
tmux -L int kill-session -t '=prodlike'                                                   # EXACT match
bash scripts/supervisor/session-reaper.sh --session prodlike; echo "absent tick rc=$?"    # want 0
tmux -L int has-session -t '=prodlike' && echo "RECREATED"                                # the claim
rm -rf "$TMUX_TMPDIR"                     # never `tmux kill-server`

# ── 3b. launchd actually runs what we think it runs (A8's acceptance) ────────────────
launchctl bootout gui/$UID/com.jonhill.session-reaper 2>/dev/null || true
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.jonhill.session-reaper.plist
launchctl kickstart -k gui/$UID/com.jonhill.session-reaper
launchctl print gui/$UID/com.jonhill.session-reaper | grep -E 'state|last exit|path'
python3 scripts/supervisor/check-plists-live.py     # reads launchctl print, NOT the file on disk
launchctl list | awk 'NR>1 && $2 != "0" && $2 != "-" {
  s=$2+0; if (s<0) printf "%s: signal %d\n",$3,-s;
  else if (s==19968) printf "%s: DELIBERATE REFUSAL (exit 78)\n",$3;
  else printf "%s: exit %d (raw %d)\n",$3,int(s/256),s }'

# ── 3c. The hooks actually fire, on ONE lane, costed, before going global ────────────
bash scripts/supervisor/hook-spike.sh --one-lane --dry-run     # Task 22 gates everything below
bash scripts/supervisor/install-claude-hooks.sh --backup
bash tests/supervisor/test_hook_wiring.sh                      # reads the REAL ~/.claude/settings.json
printf '{"tool_input":{"command":"gh issue create -b \"he said <profanity>\""},"cwd":"'"$PWD"'"}' \
  | .claude/check_quote_policy.sh; echo "want 2, got $?"
printf '{"stop_hook_active":true,"cwd":"'"$PWD"'"}' | .claude/check_stop_authorized.sh
  echo "want 0 (cap honoured), got $?"
printf '{"cwd":"'"$PWD"'"}' | .claude/check_stop_authorized.sh
  echo "want 2 (blind != authorised), got $?"
bash scripts/supervisor/uninstall-claude-hooks.sh && diff ~/.claude/settings.json ~/.claude/settings.json.bak

# ── 3d. The ledger reads work against the REAL file, and refuse when they cannot ─────
bash scripts/supervisor/ledger-snapshot.sh "$LEDGER" && echo "snapshot ok"
bash scripts/supervisor/ledger-snapshot.sh /nonexistent/ledger.sqlite3; echo "want 3, got $?"
python3 scripts/supervisor/check_events_consumed.py; echo "rc=$? (0 clean / 1 violations / 3 blind)"

# ── 3e. The gates that must be RED today — capture the before-picture ────────────────
python3 scripts/supervisor/check_workflow_job_names.py ; echo "want 1 (two 'gate' jobs)"
python3 scripts/supervisor/check_module_callers.py     ; echo "want 1 (acp_transport, poller-leak)"
python3 scripts/supervisor/check-plists-live.py        ; echo "want 1 (four off live/)"
python3 scripts/supervisor/check_corpus_verbatim.py    ; echo "want 1"
python3 scripts/supervisor/check_machinery_ratio.py    ; echo "reports 357:0"
# Commit these outputs. A gate that has never been observed red has not been observed to be a gate.
```

### Level 4: Mutation and positive-control checks — the meta-criteria, enforced

```bash
# The committed evidence the meta-criteria demand. NEITHER LABEL EXISTS IN THE TREE TODAY.
grep -rn 'mutation-check:'    tests/ | wc -l     # must be >= one per new gate
grep -rn 'positive-control:'  tests/ | wc -l     # must be >= one per "zero violations" assertion
python3 -m unittest tests.supervisor.test_evidence_labels -v

# The procedure, per example_5's closing three steps — for EVERY gate, no exceptions:
#   1. assert RED against the unfixed state
#   2. assert GREEN against a legitimate neighbour (so the gate is not merely always-red)
#   3. revert the fix, assert RED again, COMMIT THE TRANSCRIPT
# The mutant is a COPY IN A TEMP DIR, never an edit to the tracked file (test_lanes.sh:18-22 records
# why: mutation checks used to grep for the literal they were breaking, coupling each check to exact
# source text).

# The false-green checklist. A GATE MUST FAIL THIS LIST BEFORE IT COUNTS:
#  [ ] ledger unreadable -> empty count -> [ "" -gt 0 ] errors -> exit 0
#  [ ] plistlib parse error skipped -> 1 of 6 files examined -> "zero violations"
#  [ ] tmux display -t on a dead target -> exit 0
#  [ ] `! cmd`, or a bare guard inside `if`, under bash -eo pipefail -> never aborts
#  [ ] trigger/hook installed over existing contamination -> succeeds, changes nothing
#  [ ] has-session without '=' -> passes against a DIFFERENT session
#  [ ] pgrep -c / find -newermt / log show -> empty IS the clean result
#  [ ] a grep that matches the message the script just sent -> always green
#  [ ] comm with an empty left side -> nothing to do, exit 0
#  [ ] a hook whose script path does not resolve -> fails open, silently

# Reproduce the 5½-month trap once, as the template for every bash gate's mutation evidence:
bash --noprofile --norc -eo pipefail -c '! false | grep zzz; echo REACHED; exit 0'   # -> REACHED, 0
bash --noprofile --norc -eo pipefail -c 'false | grep -q zzz; echo NOT-REACHED'      # -> silent,  1
```

---

## Final validation checklist

- [ ] All 51 findings appear in exactly one task's RESPONSIBILITY, or in `docs/decisions/deferrals.md`
      with a stated reason. Cross-checked, not assumed.
- [ ] `python3 -m unittest discover -s tests -v` passes.
- [ ] Every new gate has a committed RED observation from before its fix.
- [ ] Every new gate has a `mutation-check:` case; every "zero" assertion has a `positive-control:`.
- [ ] Every ledger reader uses `snapshot_ledger` and the 0/1/3 contract. Zero direct `mode=ro` reads.
- [ ] Zero `new-session -A`, zero `display-message` preflights, zero `has-session` without `=`,
      zero `kill-server`, zero `branch -D`, zero `REGEXP` in `core.py`, zero `'*?'` GLOBs.
- [ ] `launchctl print` (not the plist file) shows every job under `$SUPERVISOR_LIVE`.
- [ ] `run-from-main.sh` was installed AFTER A8, and the reaper's exemption is written down.
- [ ] `hook-spike-results.md` exists with commands AND outputs, and predates the installer.
- [ ] The hook wiring test reads the REAL `~/.claude/settings.json`; the uninstaller restores it.
- [ ] The corpus backup was RESTORED AND COUNTED before any corpus write.
- [ ] `text_raw` was never overwritten.
- [ ] The S6 classifier's count at landing is published, and 209/305/581 are all recorded with their
      classifiers.
- [ ] No acceptance criterion hardcodes a snapshot count.
- [ ] At least one commit on a product `main`.
- [ ] The two unenforceable rules are recorded as unenforceable, and coverage is NOT claimed.

---

## Anti-patterns to avoid — each was tested and rejected by the seat that measured it

- ❌ **Do NOT add a 25th detector.** 24 exist and every one is correct. A 25th produces a system even
  more articulate about its own death.
- ❌ **Do NOT make alerting louder.** 88 Telegram messages were delivered during the outage; he was
  paged every nine minutes for two hours. Louder trains him to filter. T19's "always send" is
  *more frequent truthful reports, not more alarms*, and that reconciliation must be in the header.
- ❌ **Do NOT wire `restore.sh` before the flag is split.** Both current invocations are destructive
  by *measured dry-run* — 156 restores into a 10-window session, or five resurrected sessions
  including a test one.
- ❌ **Do NOT auto-restart lanes.** AGENTS.md invariant 3 is correct and must survive. The boundary
  the estate drew matters: invariant 8 says the poller is a service, not a lane — the refusal to
  invent *lane* continuity was silently over-extended to the *session container*, which has no
  continuity to fake. **The session is the thing to rebuild; the lane is not.**
- ❌ **Do NOT treat `poller-recover.sh` returning non-zero as the fix.** It stops the false success
  and repairs nothing. Necessary, insufficient, and dangerous if mistaken for a fix.
- ❌ **Do NOT encode "30 issues per 30 minutes."** 1,440/day against a measured best of 61.
  Encoding an unmeetable number manufactures the theatre he is angry about.
- ❌ **Do NOT claim the two unenforceable rules are covered.** "Research before asserting" is
  unenforceable (no hook distinguishes a claim from weights from a claim from a page); "ask a
  council before concluding" is only *partially* enforceable (a hook can prove a call happened, not
  that the reviewer had a lens it could fail on). Record both, honestly, with the distinction.
- ❌ **Do NOT run `tmux kill-server`.** It destroyed the estate three times. Exact-match kills only.
- ❌ **Do NOT audit everything against everything.** Jon's standing cost constraint: *"it gets
  expensive auditing each other everything. It should be high level only."*
- ❌ **Do NOT inline an assertion in a `run:` block.** It re-opens the `!`-negated-pipeline trap and
  removes the check from `unittest discover`. This repo is currently immune *only because* all three
  workflows delegate.
- ❌ **Do NOT create `.claude/hooks/`, `scripts/supervisor/lib/`, or `migrations/`.** The layout is
  flat by design; inventing a `hooks/` subdirectory is exactly what silently broke the last hook.
- ❌ **Do NOT introduce a dependency, a test framework, or a third locking mechanism.** stdlib
  Python, hand-rolled `ok`/`bad`/`check`, and `mkdir` locks (macOS ships no `flock(1)`).
- ❌ **Do NOT let a guard sit between total death and the actuator that fixes it.** Four mechanisms
  in this very plan re-create the audit's root cause and each needs a written exemption:
  `run-from-main.sh` gating the reaper; `set -e` in the reaper; the S1 Stop hook failing open; and
  the ledger snapshot failing into "nothing to do".

---

## Success metrics

| Metric | Today | Target | How it is proven |
|---|---|---|---|
| Paths from dead to alive without Jon | 0 | ≥1, scheduled | Isolated-tmux kill/tick test **and** one real observed recovery |
| Rules enforced outside the agent's turn | 0 | 4 hooks + 5 CI gates + 2 launchd auditors | Wiring test against the real `~/.claude/settings.json`; committed red-then-green runs |
| Ledger readers that can report a number they could not read | all | 0 | `grep` for `mode=ro` outside the snapshot helper returns nothing |
| Gates observed going red | 0 recorded | every new gate | `grep -rn 'mutation-check:' tests/` |
| "Zero" assertions with a positive control | 0 recorded | every one | `grep -rn 'positive-control:' tests/` |
| `no_session` ticks that page | 0 of 106 | all | T6's positive control |
| `events` unnotified > 1h | 703 | 0 | T18's gate, with exit 3 on blindness |
| Modules with zero callers | ≥2 | 0 or a shrinking grandfather list | T16's gate |
| Workflows sharing a job name | 2 | 0 | T15's lint |
| Commits to product `main` | 0 (against 357 machinery PRs) | ≥1 | T33 |

---

## PRP Quality Self-Assessment

**Score: 9/10** — confidence in one-pass implementation success.

**Reasoning**:
- ✅ **Comprehensive context**: all five research documents read in full and integrated, not
  concatenated. Nine inter-document contradictions are resolved explicitly in a table with the
  reason for each choice, rather than silently averaged.
- ✅ **Clear task breakdown**: 35 tasks, each with an exact and complete file list, ordered so the
  three hard dependencies survive — A6 before any restore automation, A2/A8 before the reaper and
  the branch guard, and the hook spike before the hook installer. File ownership is the binding
  constraint and it is respected: `core.py`, `watchdog.sh`, `heartbeat.sh`, `restore.sh` and
  `~/.claude/settings.json` each have exactly one owning task.
- ✅ **Proven patterns**: six extracted examples referenced by filename at their points of use, plus
  `file:line` citations into the real tree for every load-bearing claim.
- ✅ **Validation strategy**: four levels, all executable, with the false-green checklist a gate must
  fail before it counts, and the 5½-month `!`-trap reproduced in two lines as the mutation template.
- ✅ **Error handling**: the three-code exit contract (0/1/3) is imposed on every reader and gate,
  which is the direct structural answer to the audit's own root cause.
- ✅ **Scope honesty**: all 51 findings are traceable to a task; F2 is named as deferred with its
  reason rather than dropped; the credential exposure outside the 51 is Task 1; the two unenforceable
  rules and the contested measurements get permanent committed records.

**Deduction reasoning (−1)**:
1. **The corpus rebuild rests on a medium-confidence assumption.** Feature-analysis assumption 5
   (re-ingest rather than in-place edit) is flagged medium because INITIAL.md describes deletes and
   rewrites, not a rebuild. T27 is the largest single task and its shape could change on contact.
2. **Every corpus number is relayed, not re-measured.** Gotchas states plainly it could not open the
   ledger, so 581, 703, 1,057 and 920 come from the seats. T1 makes them measurable; until it runs,
   they are second-hand.
3. **Two questions are genuinely unanswered** — `${CLAUDE_PROJECT_DIR}` expansion in a user-global
   settings file, and whether `claude -p` honours a user-global Stop hook at all. T22 exists to
   answer them empirically, but its outcome could reshape T23.
4. **The S2-before-A8 outage is a prediction, not an observation.** Gotchas says so. The ordering is
   correct on the reasoning, and should be dry-run before anyone believes it.
5. **A11 is deliberately partial.** 304/168 literals are not rewritten in one task, because a task
   touching every `.sh` file could run in parallel with nothing. A monotonic ceiling is the honest
   substitute, and it is slower than a sweep.

**Mitigations**: T1 runs first and makes every relayed number measurable. T22 gates T23 rather than
guessing. The A8→S2 ordering is stated three separate times in this document (gotchas section,
Task 8's title, Task 10's title) because getting it backwards takes four of six LaunchAgents offline.
Every deduction above is named in `docs/decisions/deferrals.md` or `contested-measurements.md`
(Task 34) so the next reader inherits the uncertainty rather than the confidence.
