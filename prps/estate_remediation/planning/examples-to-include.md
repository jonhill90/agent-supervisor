# Examples Curated: estate_remediation

**Phase 2C of /generate-prp.** Produced by `prp-gen-example-curator`, autonomously.
**Examples directory**: `prps/estate_remediation/examples/`
**Repo root**: `/Users/jon/source/repos/Personal/agent-supervisor/.worktrees/plan/audit-remediation`
**Extracted from**: commit `6b7c4435` (2026-08-19), plus three hook files elsewhere on this machine.
**Archon**: NOT AVAILABLE. No call attempted. All examples are repo-local or machine-local.

## Summary

Extracted **six** code examples — actual files, not references. Five are the
house style an implementer must match; the sixth is the estate's best
correct-vs-broken pair, extracted into one annotated file.

## Files Created

1. **`example_1_shell_actuator_house_style.sh`** — the shell actuator pattern,
   assembled from `bootstrap-session.sh` (header discipline, env-driven session
   name, arg parsing, validate-before-touch, refusal-that-names-its-actuator,
   `--dry-run`, the `adopt-session` ledger write) plus `poller-recover.sh`'s
   logging and **reclaimable `mkdir` lock**.
2. **`example_2_shell_test_isolation_and_positive_control.sh`** — the shell test
   pattern: `ok`/`bad`/`check` helpers, `assert_isolated_tmux` (reproduced in
   full — it is 16 lines), scratch ledger via `AGENT_SUPERVISOR_STATE_DIR`,
   `EXIT INT TERM` trap with exact-match kills, and the **positive-controlled
   absence check** from `test_observed_absence_sampling.sh`.
3. **`example_3_claude_code_hooks.sh`** — `settings.json` schema for four
   events, stdin payload parsing, the exit-code contract, a blocking
   `PreToolUse` hook (this repo's, verbatim), a `Stop` hook (from
   `skills-research/Hill90`, verbatim), and the six requirements for the
   `~/.claude/settings.json` installer.
4. **`example_4_notify_send_path.py`** — pure decision core + thin actuator,
   `SendError`, `send_via_notify_skill`, with **D3, D4 and D5 annotated in
   situ** as work items rather than patterns.
5. **`example_5_sqlite_migration_and_trigger.py`** — `_migrate_lanes_table`'s
   rebuild-in-place, and `one_open_pull_per_source_ref`'s
   `BEFORE INSERT`/`RAISE(ABORT)` trigger with its pre-flight duplicate scan —
   S6's mechanism, already implemented once in this codebase.
6. **`example_6_pane_match_correct_vs_broken.sh`** — `heartbeat.sh:93` (correct)
   and `heartbeat.sh:197` (broken) side by side, with the fix, the mutation
   test, and the two gotchas that must survive the fix.
7. **`README.md`** — per example: what it is, What to Mimic, What to Adapt,
   What to Skip, Why This Example; plus a cross-cutting pattern summary and a
   seven-item anti-pattern list.

## Key Patterns Extracted

| Pattern | Source | Findings it serves |
|---|---|---|
| Shell actuator + reclaimable mkdir lock + `--dry-run` | `bootstrap-session.sh`, `poller-recover.sh` | A1, A2, A6, S2, S3, S10 |
| Refusal that names its actuator | `bootstrap-session.sh:244-251`, `core.py` RuntimeError, `protect-shared-checkout.sh` | seat 4's 11th invariant; F5's 43 sites |
| `assert_isolated_tmux` + scratch ledger + exact-match kills | `tmux-isolation.sh`, `test_bootstrap_session.sh` | A12, every new shell test |
| Positive-controlled absence | `test_observed_absence_sampling.sh` | inferred req. #5; every "zero violations" criterion |
| Hook schema + exit-2 contract + fail-open-on-blindness | this repo's `.claude/`; `Hill90/scripts/hooks/stop-gate.sh` | S1, S2, S4, S5 |
| Decision core / actuator split + `SendError` | `watchdog_notify.py` | A4, A5, D2, D3, D4, D5, S1-S3 paging |
| `_migrate_*` rebuild + `BEFORE INSERT`/`RAISE(ABORT)` + pre-flight scan | `core.py` | A2, S6, C2, C4, provenance column |
| Footer-not-scrollback matching; one shared matcher | `heartbeat.sh:93` | E2, gotcha #7 (`director-route.sh:149`) |

## Findings that materially change the plan

1. **A `Stop` hook already exists on this machine.**
   `/Users/jon/source/repos/skills-research/Hill90/scripts/hooks/stop-gate.sh`
   (99 lines), registered in that repo's `.claude/settings.json` alongside
   `PreToolUse`, `PostToolUse` and `PreCompact`. The feature analysis states
   there is "no working example in this estate to copy from" for hooks and the
   brief anticipated writing a `NO_EXAMPLE_EXISTS.md`. **Neither holds.** S1 has
   a structural template, including the four fail-open "can this hook SEE?"
   gates. No `NO_EXAMPLE_EXISTS.md` was written.
2. **The global gap is nonetheless real and re-verified today.**
   `~/.claude/settings.json` has no `hooks` key; its keys are exactly
   `alwaysThinkingEnabled, effortLevel, enabledPlugins,
   skipDangerousModePermissionPrompt, theme, tui, voiceEnabled`. Hooks exist in
   five *project* files and enforce nothing globally.
3. **S6's mechanism is already implemented once in this codebase.**
   `one_open_pull_per_source_ref` is a working `BEFORE INSERT ... RAISE(ABORT)`
   trigger with an idempotence probe, a pre-flight contamination scan, and a
   loud refusal rather than a silent winner-pick. S6 is an adaptation, not a
   novel build — which should lower its estimate.
4. **The pre-flight-scan reasoning transfers directly to S6 and is easy to
   miss.** A trigger fires only on future inserts; it does not scan existing
   rows the way `CREATE UNIQUE INDEX` does. Installing S6's trigger over the
   contaminated `items` table would succeed and look clean while leaving every
   existing bad row in place. `core.py:1085-1097` argues this at length.
5. **A `PreToolUse` hook exists in *this* repo** (`.claude/protect-shared-checkout.sh`)
   and parses its payload with `python3 -c`, not `jq`. Prefer that for anything
   installed globally — `jq` is not guaranteed.
6. **Hooks parse stdin two different ways in this estate** (`python3 -c` here,
   `jq -r` in `stop-gate.sh`). Pick one for the four new hooks and say why.

## Recommendations for PRP Assembly

1. Reference `prps/estate_remediation/examples/` in "All Needed Context", and
   direct the implementer to read `README.md` before writing any code.
2. **Put `example_6` in the Implementation Blueprint itself**, not only in the
   examples list. It is the cheapest available explanation of what class of
   defect this PRP exists to remediate, and it doubles as the E2 work item.
3. Attach `example_2`'s section E to the **meta-criteria**: every "zero
   violations" acceptance criterion inherits the positive-control template.
4. Attach `example_5`'s closing three-step procedure to the mutation-verification
   meta-criterion (assert red → assert legitimate-neighbour green → revert and
   assert it goes red again, transcript committed).
5. **Correct the feature analysis's hooks gap** in the assembled PRP, citing
   finding 1 above with its absolute path. Leaving it as "no example exists"
   will cost the implementer a session.
6. Use `example_1` as the direct template for the session reaper (A1/A2), and
   note that `bootstrap-session.sh` is both the model *and* the thing the reaper
   invokes.

## Quality Assessment

- **Coverage**: 9/10. Every technical component named in the feature analysis
  (shell actuator, shell test, hook, notification, SQLite migration, the
  correct/broken pair) has an extracted example. Two areas from the analysis's
  "Example Curator" brief are covered only as annotation rather than as their
  own file: `restore.sh`'s full `refuse()`/`--dry-run` plan output (its header
  and exit-code contract are in ex. 1, and its `--session` redirect defect is an
  A6 work item), and the prior execution plan's mermaid/group structure, which
  is a document shape rather than code and lives at
  `docs/plans/prp/estate-remediation/execution/execution-plan.md`.
- **Relevance**: 10/10. Every example maps to named findings.
- **Completeness**: 9/10. Examples 1-3 and 6 are near-runnable; 4 and 5 are
  faithful excerpts of larger modules, deliberately trimmed at documented
  boundaries.
- **Overall**: 9/10.

## Constraints observed

- Wrote only inside `prps/estate_remediation/examples/` and this one planning
  file. No source file was modified. The ledger was not opened. `tmux
  kill-server` was not run.
