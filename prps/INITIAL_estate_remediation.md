# INITIAL: Estate Remediation

## FEATURE

Remediate every finding from the 2026-08-19 council audit of the agent-supervisor estate — all of
it, not a subset. Six independent council seats, each with fresh context and its own lens, audited
the supervisor against Jon's verbatim typed words and against the running system. They produced 51
distinct findings across recovery, enforcement, corpus integrity, notification, dead guards,
architecture and product.

The single root cause the seats converged on, independently:

> **Every actuator in this estate is gated behind a refusal-on-uncertainty, and total death is the
> state of maximum uncertainty. The safety posture is perfectly anti-correlated with the failure
> mode.** 24 detectors, 14 actuators, of which 3 fire and 6 are gated behind `tmux has-session` — the
> precondition that is false in precisely the outage they exist for. Nothing in the estate can create
> a tmux session that does not exist. `bootstrap-session.sh` has zero callers. `crontab -l` is empty.
> The only path from dead to alive is Jon reading his own README.

Second root cause, structural rather than architectural:

> **`~/.claude/settings.json` has no `hooks` key at all.** Every rule Jon repeated 14–53 times was
> left to the agent's own judgement — which fails hardest exactly when it is most confident.

## THE WORK — 51 findings, grouped

### A. Recovery and liveness
1. Nothing can create a session. `bootstrap-session.sh:260` and `restore.sh:201` are the only two
   `new-session` calls; neither is invoked by any script, any of the nine LaunchAgents, or cron.
2. `poller-recover.sh:155` returns `exit 0` when the session is missing, so `watchdog.sh:1073-1082`
   writes a fresh `.poller-recovery-last-success` and zeroes the fail streak — the estate certifies
   itself healthy during a two-hour death. Zero test coverage for this case.
3. `watchdog.sh`'s `no_session` branch is `report … ; exit 0` — no notify, no repair. `no_session` is
   not `escalate`, so the most severe state pages nobody. 106 `no session` ticks across four days.
4. The watchdog abandoned its loop 147 times while work was queued; on ceiling breach the only branch
   is stop-and-page.
5. `restore.sh --session X` is a REDIRECT, not a filter (`restore.sh:121`). Dry-run plans 156 restores
   into a 10-window session. Bare `restore.sh` resurrects five sessions including a test session.
   Both current invocations are destructive; neither may be automated until the flag is split.
6. Issue #347 — `restore.sh` cannot place claude-print lanes (the transport the estate actually runs
   on). Its own acceptance grep passes today against unfixed code because it matches an unrelated
   occurrence of `harness_session_id`.
7. Four of five launchd jobs execute from the shared git working tree, currently on branch
   `fix/director-tick-fanout`, four commits ahead of `origin/main`; `director-loop.sh` differs by 40
   lines between that tree and `live/`. #366's second ask was never performed.
8. `com.jonhill.director-loop` has sat at exit 3 for hours with nothing reading `launchctl list`.
9. Loop scripts fire into sessions that do not exist: `director:@35`, `director:@3`,
   `agent-supervisor:@13` — and report success. `window_id` does not survive a server restart.
10. 297 hardcoded `agent-supervisor` and 166 hardcoded `director` literals; per-project sessions were
    built (#111), worked, and every crash reverted them. Asked 14 times.
11. A test harness claimed the production session name on the default socket and the production loop
    ticked it.
12. `contest-stop.sh` — PR #390 unmerged, not on main, not in `live/`, 0-byte log, and structurally
    unreachable because `director-loop.sh` exits 3 at line 110 before reaching its call at line 232.
13. The `sessions` ledger table (#153) — the registry that should answer "what am I responsible for
    keeping alive" — contains three test scratch sessions and two side projects, and **neither
    production session**.

### B. The STANDARD — ten rules, each needing external enforcement
- **S1** The agent may not go quiet; stopping is an event that must be justified. *(2026-08-19: "the
  loops should not stop until the work is done unless signal is needed for human"; "you just stop.")*
- **S2** Nothing executes from a ref that is not an ancestor of `origin/main`. **Violated now.**
- **S3** A scheduled job that cannot reach its target must page, not succeed. **Violated now.**
- **S4** Jon is never quoted with profanity and never made to look bad. **Three live violations in the
  PUBLIC agent-dotfiles repo: issues #237, #174, and PR #55.** A sweep of 483 issues, 465 PRs and
  1,303 comments found exactly these three. The hook prevents new ones; these must be edited.
- **S5** Deliverables live in git; `~/.local/state` holds state, never code. **Violated now** —
  `phase-report.sh`, 13,594 bytes, the week's most visible deliverable, exists in no repository.
- **S6** A question is never recorded as a decision.
- **S7** The corpus must be provably complete and provably verbatim.
- **S8** The conflict detector must be able to fire, and be proven to.
- **S9** Tested code with zero callers is a defect.
- **S10** Branch and worktree ceilings. **Violated now** — 770 branches, 346 worktrees, 416 tmux
  sockets, `.watchdog-guard-audit-fail-streak` = 30.

### C. Corpus integrity
14. `links` has zero rows, so the `conflicts` view is structurally incapable of returning a row — and
    it was cited as proof of consistency, to Jon's phone.
15. 1,252 items were mined from interrogative prompts; **581 are stored at `weight='hard'`** — 23.4% of
    the entire hard tier. His questions recorded as his decisions.
16. `itemize_prompts.py --load` reads a JSON array "produced BY A MODEL" (its own docstring) and writes
    `kind` and `weight` verbatim with no logic — while that same docstring quotes Jon saying it should
    be a tool, not inference.
17. `possibility_count` is `COUNT(*) FROM live_parameters WHERE weight='hard'` = 920 — a count of his
    constraints, reported under the name of the solution space, in every 30-minute report.
18. His most consequential instructions are absent from the corpus entirely: `make me look good` → 0
    rows; the "close 30 issues" demand → absent.
19. Seven rows dated 2026-08-19 are third-person paraphrase, not his words.
20. 1,057 rows (29%) come from `hill90-app`, a repo he excluded twice.
21. Grammar repair: 3,504 of 3,683 rows untouched (95.1%). `update_text_clean` has exactly one
    occurrence in the codebase — its own definition.
22. ~22% of his messages were never ingested at all (all of 2026-08-19).

### D. Notification and honest instruments
23. `events` — 703 rows, **703/703 never notified, never acked.** Only 209 of 1,536 tasks (13.6%)
    recorded `accepted_at`. This is the same zero-consumer defect the codebase names nine times as its
    own proverb.
24. The 30-minute report suppresses itself when nothing happened — the exact condition he most needs
    told about. It missed the target in 0 of 38 windows and cannot tell 0/30 from 30/30.
25. The notify path has run on a silent fallback for two days (83 of 119 lines `NOTIFY-PATH-STALE`).
26. `watchdog_notify.py:299` hardcodes an `inbox-poll` message for all three subscribers, so every
    heartbeat page ever sent named the wrong subsystem, the wrong file and the wrong threshold.
27. `watchdog_notify.py:336` — the `state: stopped` staleness exemption is unbounded in time and is
    live, permanently suppressing the alarm.
28. Quota meter unreadable 86% of the time and pinned to `confirmed: SAFE`; no stand-down path exists;
    a blind meter does not halt dispatch. On 2026-08-15 this burned $80 of usage credits down to $8.
29. Health reads `OK` with nothing executing — 37 of 83 OKs had `0 pane-working`, because health is
    defined as "the ledger moved" and bookkeeping moves the ledger.

### E. Guards that cannot fire
30. `ci_gate.py:93` — both gate workflows declare their job as `gate:`; de-duplication keys on name
    alone, so the later check run erases the earlier. Demonstrated on PR #394: a real failure was
    discarded because another job succeeded three seconds later. The merge gate is a race.
31. `heartbeat.sh:197` — the stall nudge verifies success by grepping the whole pane for a string that
    is a substring of the message it just typed. It always reports success; line 200 is unreachable.
    The same file fixes this correctly at line 93 and reintroduces it 104 lines later.
32. #325 — closed COMPLETED with no PR and neither ask performed; its "must NOT nudge a healthy pane"
    test is unreachable because all three cases pin `HEARTBEAT_STALE_AFTER=0`.
33. #382 shipped `poller-leak-cleanup.sh` (183 lines, 9 tests) with zero callers — verbatim the
    anti-pattern the repo names in its own test harness.

### F. Architecture and never-attempted
34. **ACP**: decided 2026-08-11, asked 23 times across 9 days. `acp_transport.py` is 302 tested lines
    with zero importers; `acp` lanes = 0, `pi-rpc` lanes = 0, while 162 lanes ran on headless
    `claude -p` — a transport nobody asked for, replacing the persistent tmux lanes he specified.
35. **Chain of command** — never attempted. No `role`, `tier`, `parent_lane` or `reports_to` anywhere.
    `--supervisor-lane`'s only consumer is a string comparison at `cli.py:962`. `dispatch.sh` picks
    lanes by freeness.
36. `--dangerously-skip-permissions` on 132 lanes by default. Never requested.
37. Explicit minutes-long asks queued behind analysis: "set up a cron" produced nothing —
    `crontab -l` empty, newest LaunchAgent mtime three days old. Adversarial review asked 34 times,
    run only under threat.
38. 43 code sites whose terminal action is a string. `a human should look` appears in four scripts and
    is written to a file with no reader.

### G. Product — the point
39. **357 machinery PRs merged, 0 commits to product main.** 713 of 1,536 lifetime tasks cancelled
    (46.4%). 100 tasks stuck in `delivered`.
40. `agent-tui` is still private, against an explicit ask.
41. Phase 4 (the interface) is where lanes should be; supervisor internals are justified only when
    they block Phase 4.

## EXAMPLES

- `prps/multi_project_selector/execution/execution-plan.md` in `jonhill90/skills@5688dfe1` — the
  dependency graph, colour-coded parallel groups, per-group validation gates, critical path and risk
  assessment shape this must follow. Jon: *"the execution plan was really cool. the colors, the
  parallel agents not doing the same work."*
- `.claude/patterns/parallel-subagents.md` — `can_run_in_parallel()` file-conflict check; 3–6 tasks
  per group; all `Task()` calls in a single response.
- `.claude/patterns/quality-gates.md` — 8+/10 scoring, multi-level validation, max 5 iterations.
- The estate's own existing skills: `failing-test-first`, `sanity-check`, `safe-deletion`,
  `verify-the-instrument`, `ask-a-council`, `dispatching-subagents`.

## DOCUMENTATION

- `docs/audit/2026-08-19-council/` — the six seats' raw output. **Primary evidence. Read before
  asserting anything.**
- `AGENTS.md` invariants, particularly invariant 3 (no lane auto-restart) and invariant 8 (the poller
  is a service, not a lane).
- `~/.local/state/agent-dotfiles-supervisor/PHASES.md` — the phase plan that governs priority.
- `~/.local/state/agent-dotfiles-supervisor/NOTEBOOK-jon-directives.md` — standing rules in his words.

## OTHER CONSIDERATIONS

- **Anti-goals, each rejected with evidence by the seat that tested it.** Do NOT add a 25th detector —
  24 exist and every one is correct. Do NOT make alerting louder — 88 Telegram messages were delivered
  during the outage; he was paged every nine minutes for two hours. Do NOT wire `restore.sh` before the
  flag is split — both invocations are destructive by dry-run. Do NOT auto-restart lanes — AGENTS.md
  invariant 3 is correct and must survive. Do NOT treat `poller-recover.sh` returning non-zero as the
  fix — it stops the false success and repairs nothing.
- **Do NOT encode "30 issues per 30 minutes."** That is 1,440/day; measured 4, 10 and 61 on the three
  days before this audit. Encoding an unmeetable number manufactures the theatre he is angry about.
  Report the real rate and let him set the number with that in front of him.
- **Two rules are not enforceable and must be recorded as such, not papered over**: "research before
  asserting" (no hook distinguishes a claim from weights from a claim from a page) and "ask a council
  before concluding" (a hook can prove a call happened, not that the reviewer had a lens it could fail
  on).
- **The ledger is READ ONLY** except for the corpus tasks, which run behind a verified backup and the
  `safe-deletion` skill — they delete 1,057 rows and rewrite 588 more of his own words.
- **Every enforcement mechanism must be mutation-verified**: revert the fix, the gate must go red. A
  gate that cannot fail is the defect this work exists to remove. Note that a `!`-negated pipeline
  never aborts a `bash -eo pipefail` step — that is how a guard was green and dead for 5½ months.
- **Positive-control every absence.** `pgrep -c` returns empty on macOS; `find -newermt` matched 0 of
  1159 files; `log show` returns 0 lines without elevation. All three look exactly like clean results.
- **Never `tmux kill-server`** — it destroyed the estate three times. Exact-match kills only.
- **Archon MCP is not available in this estate.** Task tracking degrades to the existing ledger claim
  mechanism per `.claude/patterns/archon-workflow.md`.
- Jon's standing constraint on cost: *"it gets expensive auditing each other everything. It should be
  high level only."*
