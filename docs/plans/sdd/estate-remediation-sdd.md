# Plan 2 — Spec-Driven Development (SpecKit shape) + TDD

**Same 51 tasks. Different decomposition, different failure mode.**
Read alongside `docs/plans/prp/estate-remediation.md`. Choose one; do not run both.

---

## Which framework, and why not the others

Jon asked: SpecKit, superpowers, BMAD, or ours. This estate already answered it once — this plan
follows that answer rather than reopening it.

`PLAN-EXEC.md:277-286`, already in the record:

> *"Do not adopt any of the three as a dependency. Take the FORMAT idea from SpecKit specifically
> (numbered `/specify → /plan → /tasks` staging with a checked-in artifact per stage) as a shape to
> compare our `spec`/`prd`/`tdd` skills against — they already exist and are merged. Do not adopt
> BMAD's persona layer … and BMAD's licence is unresolved (NOASSERTION)."*

Two independent reasons to hold that line, both of which are Jon's own standing rules:

- **Supply chain.** *"dont take code from so low starred or not really supported repos or code that
  would be very vulnerable to supply chain attacks."* BMAD's licence is `NOASSERTION`. An unresolved
  licence on a framework that generates the plans that generate the code is not a dependency this
  estate should carry.
- **Personas are already covered.** BMAD's persona layer serves the need this estate meets with
  `ask-a-council` + `devils-advocate` + distinct evidence per agent — which is exactly what produced
  the six seats this plan implements. Adding personas would duplicate a mechanism that just worked.

**So: SpecKit's staging discipline, this estate's existing `spec` / `prd` / `tdd` / `failing-test-first`
skills as the engine, nothing installed.** Superpowers is not evaluated here because nobody has read
it in this estate — saying so is better than pretending it was considered.

---

## Stage 0 — CONSTITUTION

*SpecKit's constitution is the thing plans are checked against. Ours is not invented: it is the six
seats' findings turned into articles. Every article has a mechanical check; an article that cannot be
checked is marked as such rather than pretended.*

| Art. | Article | Mechanical check | Status |
|---|---|---|---|
| **I** | **The agent may not go quiet.** Stopping is an event that must be justified. | `Stop` hook exits non-zero unless a blocked-file names a Jon-only decision **and** a page was sent in the last 10 min, or the queue is empty | enforceable, not built |
| **II** | **Nothing executes from a ref that is not an ancestor of `origin/main`.** | `merge-base --is-ancestor` wrapper at every launchd entrypoint; exit 78 | enforceable, **violated now** |
| **III** | **A refusal-to-act must name what does act instead.** | grep test over `a human should look`; 43 grandfathered by count, may only decrease | enforceable, not built |
| **IV** | **A scheduled job that cannot reach its target pages; it does not succeed.** | target preflight + `launchctl` exit sweep | enforceable, **violated now** |
| **V** | **Jon is never quoted with profanity or made to look bad.** | `PreToolUse` block on `gh issue/pr` and `Write:*.md` | enforceable, **3 live violations** |
| **VI** | **Deliverables live in git.** `~/.local/state` holds state, never code. | `PostToolUse` reject + daily orphan audit | enforceable, **violated now** |
| **VII** | **A question is never recorded as a decision.** | `BEFORE INSERT` trigger + deterministic classifier | needs migration + rewrite |
| **VIII** | **The corpus is provably complete and provably verbatim.** | byte-for-byte CI, both directions | enforceable, **failing now** |
| **IX** | **Tested code with zero callers is a defect.** | non-test-importer CI | enforceable, not built |
| **X** | **A gate that cannot fail is not a gate.** | every gate mutation-verified: revert the fix, gate must go red | enforceable, not built |
| **XI** | *Research before asserting; never answer from weights alone.* | **NONE.** A `Sources:` block checks paperwork, not honesty. | **NOT ENFORCEABLE — do not claim coverage** |
| **XII** | *Never conclude alone; seek an adversarial second opinion.* | partial — can prove a call happened, not that the lens could fail | **PARTIAL — say so** |

**Amendment rule**: an article may only be added with its check. A rule the agent has to *remember* is
not an article; it is a wish, and this estate has nine days of evidence for what wishes are worth.

---

## Stage 1 — `/specify` — WHAT and WHY, no implementation

**Feature**: An estate that survives its own death, cannot misquote its owner, cannot run
off-`main` code, and produces product.

### User scenarios (each is an acceptance test, not a description)

- **S-1 — Unattended recovery.** *Given* the supervisor session is killed at a random moment,
  *when* 300 seconds pass with no human action, *then* the session exists again with its lanes
  registered. **Twice consecutively.** (Today: four outages, each ended only when a human typed.)
- **S-2 — Off-main refusal.** *Given* a scheduler's checkout is not an ancestor of `origin/main`,
  *when* the job fires, *then* it refuses to exec, pages, and exits 78. (Today: four of five jobs run
  from a checkout 4 commits off `main`.)
- **S-3 — Quote safety.** *Given* an artifact body quoting Jon with profanity, *when* any tool tries to
  publish it, *then* the write is blocked before the API call. (Today: three live public violations.)
- **S-4 — Honest silence.** *Given* a 30-minute window in which nothing closed, *when* the report
  fires, *then* it sends and leads with the zero. (Today: it suppresses itself — *"nothing closed in
  the window … not sending."*)
- **S-5 — Question ≠ decision.** *Given* an interrogative prompt, *when* itemisation runs, *then* no
  `weight='hard'` row is produced. (Today: 581 such rows, 23.4% of the hard tier.)
- **S-6 — Honest health.** *Given* zero panes executing, *when* health is computed, *then* it does not
  read OK. (Today: 37 of 83 OKs had `0 pane-working`.)
- **S-7 — No orphan mechanisms.** *Given* a module with tests and zero non-test importers, *when* CI
  runs, *then* it fails. (Today: `acp_transport.py` — and the repo documents this in two of its own files.)
- **S-8 — Product exists.** *Given* the audited window, *when* product `main` is inspected, *then*
  there is at least one commit. (Today: 357 machinery PRs, zero.)

### Explicitly out of scope

Louder alerting · a 25th detector · lane auto-restart · encoding "30 issues per 30 minutes"
(= 1,440/day; measured 4, 10, 61 — encoding an unmeetable number manufactures theatre).

### `[NEEDS CLARIFICATION]` — SpecKit's discipline is to mark, not guess

1. **`[NEEDS CLARIFICATION: MinIO-style irreversible deletes]`** — U30 removes 1,057 corpus rows from
   an excluded repo and rewrites 588 more. Jon's call, not the plan's.
2. **`[NEEDS CLARIFICATION: branch/worktree ceilings]`** — 25 and 10 are the council's numbers. He
   gave the direction, not the figure.
3. **`[NEEDS CLARIFICATION: ACP delete-or-wire]`** — S-7 forces a decision. Deleting 302 tested lines
   he asked for 23 times is a decision he should make, not one the plan should make quietly.

---

## Stage 2 — `/plan` — HOW, contract-first

### Architecture decision: one actuator, driven by a table

The council's central finding is that this estate has 24 detectors and 14 actuators, of which 3 fire
and 6 are gated behind `tmux has-session` — the precondition that is false in precisely the outage
they exist for. **The safety posture is perfectly anti-correlated with the failure mode.**

The design consequence is one line: **recovery must be a set-difference, not a judgement.**

```
owned_sessions (table)  −  tmux ls  =  sessions to create
```
No model call. No confidence estimate. No refusal-on-uncertainty, because there is no uncertainty to
refuse on. The reaper is the only new actuator, and it contains no reasoning.

### Contracts (written and tested BEFORE any implementation — this is the SpecKit/TDD half)

| Contract | Shape | Test file |
|---|---|---|
| `session-reaper` | `reap() → {created: [names], skipped: [names+reason]}`; exit 0 only if `missing == 0` after the run | `tests/contracts/test_reaper_contract.sh` |
| `stop-authorization` | `authorize(state) → {allowed: bool, reason: str}`; `allowed=false` is the default | `tests/contracts/test_stop_contract.py` |
| `main-ancestry` | `check(path) → 0 \| 78`; never any other code | `tests/contracts/test_ancestry_contract.sh` |
| `quote-safety` | `scan(text) → {blocked: bool, matches: []}`; deterministic, no model | `tests/contracts/test_quote_contract.py` |
| `item-classification` | `classify(prompt) → {kind, weight}`; interrogative ⇒ `weight != 'hard'`, by rule not by model | `tests/contracts/test_classify_contract.py` |
| `health-predicate` | `health() → OK` requires `pane_working > 0 \| stand_down_recorded` | `tests/contracts/test_health_contract.sh` |
| `notify-event` | every `events` row reaches `notified_at` within 1h or CI fails | `tests/contracts/test_events_contract.py` |

**Constitution gate on this stage**: every contract above maps to an article. Art. XI and XII have no
contract, and that is recorded as a gap rather than papered over.

---

## Stage 3 — `/tasks` — the ordered, TDD-gated list

SpecKit's convention: `[P]` = parallelisable (different files, no shared state). Every task is
**RED → GREEN → REFACTOR**; the test is written and failing before the implementation exists.

### Phase A — Constitution violations that are live *(do first; Art. II, V, VI are violated right now)*
```
A1  [P] RED: ancestry contract test → GREEN: run-from-main.sh + repoint 5 plists     (Art. II)
A2  [P] RED: quote contract test    → GREEN: no_quote_profanity.py                   (Art. V)
A3  [P] Remediate agent-dotfiles #237, #174, PR #55                                  (Art. V, irreversible)
A4  [P] RED: state-orphan test      → GREEN: no_code_in_state.py + move phase-report.sh (Art. VI)
```

### Phase B — Contracts, red *(no implementation permitted in this phase)*
```
B1  [P] tests/contracts/test_reaper_contract.sh        — MUST FAIL
B2  [P] tests/contracts/test_stop_contract.py          — MUST FAIL
B3  [P] tests/contracts/test_health_contract.sh        — MUST FAIL
B4  [P] tests/contracts/test_classify_contract.py      — MUST FAIL
B5  [P] tests/contracts/test_events_contract.py        — MUST FAIL
B6      Gate: run the suite; every B test RED. A green test here is a broken test — check the
        instrument before believing it (a positive control is mandatory: one assertion you KNOW passes).
```

### Phase C — Recovery, green *(the critical path)*
```
C1      sessions table = owned sessions                          → B1 still red
C2      session-reaper.sh (set-difference, zero model calls)     → B1 GREEN
C3      watchdog.sh: no_session → reaper; stop false-success stamping; ceiling hands off; health
        predicate requires pane_working                          → B1, B3 GREEN
C4      poller-recover.sh exit 1 + the missing-session test that has never existed
C5      com.jonhill.session-reaper.plist through A1's wrapper
C6      GATE: kill the session twice, 300s each, unattended recovery both times.
        THE PLAN STOPS HERE IF THIS FAILS.
```

### Phase D — Enforcement, green
```
D1      check_stop_authorized.sh                                 → B2 GREEN     (Art. I)
D2      require_adversarial_review.py + ASKS.tsv                 (Art. XII, partial — say so)
D3      Register all hooks in ~/.claude/settings.json            [SEQUENTIAL — one shared file]
D4  [P] launchd-sweep.sh + plist                                                 (Art. IV)
D5  [P] target-reachability preflight: heartbeat / director-loop / quota-watch   (Art. IV)
D6  [P] reap.sh — branch/worktree ceilings + unconditional prune
D7  [P] AGENTS.md refusal invariant + grep test, 43 grandfathered by count       (Art. III)
```

### Phase E — Corpus
```
E1  [P] provenance column NOT NULL from promptSource                             (Art. VIII)
E2  [P] BEFORE INSERT trigger: interrogative + hard → raise    → B4 GREEN        (Art. VII)
E3  [P] itemize_prompts.py deterministic; model proposes body text only          (Art. VII)
E4  [P] wire update_text_clean (95.1% of rows untouched)
E5  [P] fix possibility_count (counts constraints, reported as possibilities)
E6      BACKUP + safe-deletion review, then: repair 581+7 rows, re-ingest missing 08-19,
        drop 1,057 hill90-app rows                              [SEQUENTIAL, after E1-E3]
E7  [P] link_items.py — deterministic linker; links stops being empty            (Art. VIII)
```

### Phase F — Gates that can fail
```
F1  [P] ci_gate.py duplicate `gate:` job name + workflow-lint test               (Art. X)
F2  [P] heartbeat.sh:197 self-matching verification → tail -1                    (Art. X)
F3  [P] un-pin HEARTBEAT_STALE_AFTER=0 so #325's case is reachable               (Art. X)
F4  [P] restore.sh --session vs --only-session; real #347 placement test         (Art. X)
F5  [P] watchdog_notify.py: parameterize the message; bound the stopped exemption
F6  [P] corpus-verbatim CI, links CI, events-orphan CI, no-orphan-modules CI     (Art. VIII, IX)
F7      MUTATION SWEEP: for every gate above, revert the fix and confirm RED     (Art. X)
```

### Phase G — Architecture and product
```
G1  [P] ACP: one real lane completes one real task, OR delete the module         (Art. IX)
G2  [P] sessions.conf sweep — 463 literals                     [SEQUENTIAL vs D5/F2]
G3  [P] chain of command: role/tier/parent_lane; dispatch by tier not freeness
G4  [P] --dangerously-skip-permissions → scoped default, bypass recorded per lane
G5  [P] per-project tmux sessions, held by the owned-sessions table
G6  [P] agent-tui → public
G7  [P] Phase 4 interface work — the first product commit since 2026-08-09
G8      quota: UNKNOWN×2 → UNSAFE, real stand-down, blind meter halts dispatch
G9      report: always send, lead with the miss, delete the stale-path fallback
```

---

## The two plans, compared honestly

| | **Plan 1 — PRP** | **Plan 2 — SDD/SpecKit** |
|---|---|---|
| Organising principle | **File ownership** — collision is the binding constraint | **Constitution + contracts** — a violated article is the binding constraint |
| Parallelism | Explicit: 7 groups, 39 units, one owner per path, worktree per unit | `[P]` markers; parallelism is a property of tasks, not a designed structure |
| Fastest to a working estate | **Yes** — ~3.5h critical path to unattended recovery | Slower: Phase B writes every contract test red before any implementation |
| Hardest to regress | Weaker — nothing stops a later change re-violating a finding | **Stronger** — the constitution outlives the plan and gates future work |
| Parallel-safety guarantee | **Mechanical** — duplicate-path check fails the plan | Convention only — `[P]` is a claim, not a check |
| Failure mode | A unit's owner list is wrong → two agents collide | Contract tests pass while the system is broken → false green |
| Matches his ask | *"execution plan where agents work in parallel and not break or overlap"* — **this is that** | Matches *"Spec Driven Development, Test Driven Development"* |
| Effort | ~11h wall-clock at 8 lanes | ~14h — the red-first phase is real cost |

**If forced to recommend:** run **Plan 1's execution structure** with **Plan 2's constitution and
Phase B** grafted in front of it. The file-ownership contract is the part that makes eight parallel
agents safe, and the constitution is the part that stops this same audit being necessary again in
September. That is a graft, not a third framework — and it is what his own `PLAN-EXEC.md` recommended
before this audit ran: take SpecKit's staging shape, keep our own engine, install nothing.
