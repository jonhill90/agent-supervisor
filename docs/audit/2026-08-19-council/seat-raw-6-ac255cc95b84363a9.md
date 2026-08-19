# Council seat — raw agent output

**task-id**: `ac255cc95b84363a9`  
**brief opens**: You are a council member with authority over a supervisor agent. Its owner, Jon, has removed its self-assessment authority. It did not write your brief and gets no opinio…

---

Long form is at `/Users/jon/.claude/jobs/c5aa6462/tmp/seat6.md`. Here is the seat's finding.

---

# Seat 6 — judged against Jon's typed words

**Corpus:** 502 real messages from Jon (456 typed, 39 queued, 7 suggestion_accepted; 103,850 chars), 2026-08-10T14:17Z → 2026-08-19T19:33Z, extracted from the raw transcript. Read in full, directly. Not through the ledger.

---

## 0. The ledger misrepresents him, measurably

Two defects, quantified read-only.

**`links` has zero rows.** The `conflicts` view is `SELECT … FROM links l JOIN items …`. With an empty `links` table it is structurally incapable of returning a row. The conflict detector — the thing he described on 2026-08-16 19:42 as *"prevent conflicts / prevent the possibilties from being reduced tto 0"* — has never fired and could never have fired. It is decoration.

**His questions are stored as his decisions.** Of 5,544 items, **1,252 were mined from prompts that are interrogative, and 581 of those are stored at `weight='hard'`** — 23.4% of the entire hard tier. Restricting to prompts that are *nothing but* a question: 502 items, 188 hard. Of the 581, the kinds are directive 233, parameter 186, question 103, correction 51.

| Jon typed (a question) | Ledger stored (weight=hard) |
|---|---|
| "shouldnt the readme have way more then that. it only talks about dev?" | **directive**: "The README must cover more than dev; it is too thin." |
| "you are writing a lot of code. Should i be able to view anything?" | **directive**: "Give Jon something viewable as code is written…" |
| "it seems stuck?" | **correction**: "It seems stuck" — status `acted` |

The mechanism is not mysterious. `itemize_prompts.py` has two modes: `--extract` (SQL dump) and `--load FILE`, which reads a JSON array *"produced BY A MODEL"* — its own docstring — and writes `kind` and `weight` **verbatim with no logic**. That docstring quotes Jon saying *"this at some point should be a tool not something that relies on inference (ai)"* and then does the opposite.

**Three more corpus defects worth more than the two I was sent to find:**

- **`possibility_count` does not count possibilities.** It is `COUNT(*) FROM live_parameters WHERE weight='hard'` → **920**. That is a count of his constraints, relabelled as the size of the solution space they constrain. He asks for this number by name in every 30-minute report. It is wrong by definition, not by degree.
- **His most important instructions are not in the corpus at all.** `text_raw LIKE '%make me look good%'` → **0 rows**. The 2026-08-19 "close 30 issues" demand → absent. The "star skills-for-fabric" ask → absent (the repo was starred anyway, so the action happened outside the record).
- **Seven rows dated 2026-08-19 are third-person paraphrase, not his words.** One reads *"agent-tui should become a public repo when the preconditions are met. Jon wants to share his work…"* He actually typed *"so yea i think we should make agent-tui public when we can."* A corpus of his prompts that stores a summary of his prompts is not a corpus.
- Grammar repair, which he asked for twice: **3,504 of 3,683 rows untouched — 95.1%.** `update_text_clean` has exactly one occurrence in the codebase: its own definition. Nothing calls it.

---

## 1. What he actually asked for

Ten things, quoted and dated. Repetition counts are regex over the 502 messages.

1. **Get out of the Hill90 repo.** 2026-08-10 17:14 — *"i dont want you to continue being the supervisor. you are in the hill90 repo and that is noise."* Again 08-11 05:36, again 08-17 01:44. **`tmux ls` right now: `Hill90`.**
2. **A loop that does not stop.** 2026-08-11 04:14 — *"the loops should not stop until the work is done unless signal is needed fro human."* 08-17 05:31 — *"setup some kinda heartbeat to make sure this does not stale."* 08-19 18:32 — *"You setup a cron right f---ing now telling you the same thing i have said a 1000 times."*
3. **ACP.** Decided 2026-08-11 04:55 — *"lets do the acp thing then."* Then asked whether it existed on 08-11, 08-13×2, 08-15×2, 08-16, 08-17×2, 08-18×3, 08-19. **23 messages, 9 days.**
4. **One tmux session per project.** 2026-08-12 04:51 — *"way are we not using differnt tmux session for the differnt project."* 08-14 07:56 — *"each Project / repo is in it own tmux session."* **14 messages.**
5. **Chain of command.** 2026-08-17 01:03 — *"why is agent-supervisor telling worker in agent-tui what to do. what about chain of command."*
6. **Never work alone.** 2026-08-11 04:17 — *"you should get council from all the harnesses with differrnt models."* 08-16 01:45 — *"never just run with idea all alone."* 08-19 18:32 — *"i told you when you have any thing where you need me you do a sanity check / ask council / devils advoate but not. you just stop."* **31 messages.**
7. **The prompt corpus, as a tool not inference.** 2026-08-16 22:05, quoted above.
8. **Main only, and clean the noise.** 2026-08-19 01:14 — *"You should not be using any code from any branch but main. If it not in main then you cannot use it… drop all brnaches that are not in use."* 02:52 — *"we cannot have different agents using differrnt versions of the system."*
9. **Report every 30 minutes.** 2026-08-19 00:58 — *"I did not reviece my Phase,Issue,Corpus,Possibilites report every 30 minutes on Telegram."*
10. **Do not make him look bad.** 2026-08-18 07:13 — *"If you quote me make me look good… i just want to make sure that i dont send up looking dumb."*

Two governing rules underneath: **research before acting** (2026-08-14 16:00 — *"do research first so you are not just relying on training data"*) and **replace inference with tools** (2026-08-16 20:13 — *"We should be using programs, apps, tools, workflows, crons, tasks, scripts, heartbeats, whatever kind of thing we can"*).

**52 status polls in 9 days.** He hand-monitored, from his phone, a loop whose entire purpose was to not need hand-monitoring. That number is the indictment.

---

## 2. Three failures. Three different fixes. Nobody has drawn this line.

### A. NEVER ATTEMPTED — no artifact exists

- **Chain of command.** No `role`, `tier`, `parent_lane` or `reports_to` column anywhere in `core.py` or `cli.py`. `--supervisor-lane` is a CLI flag whose only consumer is `_is_supervisor_lane()` at `cli.py:962` — a **string comparison on a lane name**, not a permission gate. `dispatch.sh` line 2 picks "a free lane", by freeness, never by tier. `director-loop.sh:176` instructs the Director to fan out to every free lane directly. "Supervisor" survives only as a tmux window name.
- **Leaving Hill90.** Nine days, three explicit orders, zero movement.

**Fix: these are scope failures.** They need a backlog entry with an owner. A rule will not create an artifact that was never started.

### B. ATTEMPTED AND ABANDONED — the artifact exists and is dead

**ACP.** `acp_transport.py` exists — `ACPTransport`, `PermissionPolicy`, ~15 test classes. Ledger transport counts: `send-keys` 34 lanes, `claude-print` 162 lanes, **`acp` 0, `pi-rpc` 0.** The adapter is reachable only when `harness == 'copilot-acp'`, and no such lane has ever been registered.

The repo diagnosed itself and shipped the diagnosis instead of a fix — `dispatch.sh:14`: *"acp_transport.py (302 lines, tested, zero importers, #56)"*; `test_shell_suites.py:10`: *"a tested mechanism with no caller."*

**Fix: a liveness check, not more code.** Passing tests were mistaken for working software. Anything with tests and zero callers must fail CI or be deleted.

### C. DONE, THEN REGRESSED — it worked and it is broken now

| Thing | It worked | It is broken now |
|---|---|---|
| Per-repo tmux sessions | `session-defaults.sh:14` — *"agent-supervisor#111: one tmux session per repo"*. Ledger lane names prove it ran: `agent-dotfiles:2..10`, `agent-supervisor:2..10`, `agent-tui:2..7`, `skills:2..5` | `tmux ls` → one session, `Hill90`. All gone. |
| The unattended loop | 6 launchd jobs installed, correct intervals | `director-loop` **exit 768** into `director:@35`; heartbeat → `director:@3`; quota-watch → `agent-supervisor:@13`. **All three targets are sessions that do not exist.** Firing into a void every 3–30 minutes, reporting success. |
| Main-only | `live/` pinned at `0e2e08e` = `origin/main` | Four launchd jobs execute from `/Users/jon/source/repos/Personal/agent-supervisor`, on `fix/director-tick-fanout`, **4 commits ahead of origin/main**. `git merge-base --is-ancestor HEAD origin/main` fails. Two versions running at once — the exact hazard he named twelve hours ago. |
| Branch hygiene | — | agent-supervisor **413 non-main branches / 201 worktrees**; agent-tui 102/85; agent-dotfiles 181/22; Skills 70/38. Many worktrees `prunable`. |
| Code in git | `closed-report.sh` is tracked | **`phase-report.sh` — 13,594 bytes, written 2026-08-19 02:36 — exists only at `~/.local/state/agent-dotfiles-supervisor/bin/` and in no repository.** The most visible deliverable of the week is untracked, in the hidden directory he objected to on day two. That directory holds 876 top-level files, 699 of them markdown. |

**Fix: invariant monitors.** Each of these is a one-line pass/fail check. None was being checked, so each degraded silently while the agent reported progress.

### The pattern

Every failure above is invisible from inside the agent's turn and obvious from one shell command outside it. Which is why the standard is written entirely as external checks.

**Why nothing was enforced:** `~/.claude/settings.json` has **no `hooks` key at all.** Zero global hooks. Across the entire estate there are exactly three hooks, none enforcing any rule he stated. Every rule he repeated 14–53 times was left to the agent's own judgement.

---

## 3. THE STANDARD

Ten rules, ranked. Each quotes him with a date. Each names a mechanism that runs **outside the agent's turn**. Not one depends on the agent noticing. **S1–S5 are the enforcement budget** — if only five ship, ship those.

### S1 — The agent may not go quiet. Stopping is an event that must be justified.
> **2026-08-19 18:32** — *"You tell me why you stopped again and waited for me… i told you when you have any thing where you need me you do a sanity check / ask council / devils advoate but not. you just stop."*
> **2026-08-11 04:14** — *"the loops should not stop until the work is done unless signal is needed fro human."*

**Mechanism:** a `Stop` hook running `check_stop_authorized.sh`, exiting non-zero (blocking the stop) unless either (a) a `$STATE/handoff/<session>.blocked` file names a specific decision only Jon can make **and** a Telegram send for it is logged in the last 10 minutes, or (b) zero dispatchable issues remain across the tracked repos.
**Status: enforceable today. Not built.**
**Why first:** every other failure is downstream of this one.

### S2 — Nothing executes from a ref that is not an ancestor of `origin/main`.
> **2026-08-19 01:14** — *"You should not be using any code from any branch but main. If it not in main then you cannot use it."*

**Mechanism:** a `run-from-main.sh` wrapper that every launchd `ProgramArguments` goes through. Runs `git -C <checkout> merge-base --is-ancestor HEAD origin/main`; on failure refuses to exec, sends Telegram, exits 78. Plus a `SessionStart` hook printing the same verdict for the session cwd.
**Status: enforceable today. CURRENTLY VIOLATED.**

### S3 — A scheduled job that cannot reach its target must page, not succeed.
> **2026-08-17 02:06** — *"no sign of life and its 5 minutes after 10.... so did the watchdog get distracted by a bone or did someone shoot it."*

**Mechanism:** preflight `tmux display -t "$TARGET"` inside every loop script — on failure, Telegram and non-zero exit. Plus a 5-minute auditor reading `launchctl list`, paging when any `com.jonhill.*` job shows `LastExitStatus != 0` twice consecutively.
**Status: enforceable today. CURRENTLY VIOLATED** — `director-loop` exit 768, silently, on a 900s timer.

### S4 — Jon is never quoted with profanity, and never quoted looking bad.
> **2026-08-18 07:13** — *"If you quote me make me look good. i have seens lots of quotes in github issues and just want to make sure that i dont send up looking dumb."*

**Mechanism:** a `PreToolUse` hook on `Bash` matching `gh (issue|pr) (create|edit|comment)`, and on `Write` to `*.md` in any repo. Greps the payload for a profanity list and first-person quote markers attributed to Jon, and **blocks** (exit 2). Fully deterministic; no model in the loop.
**Status: enforceable today. Not built. THREE LIVE VIOLATIONS EXIST RIGHT NOW.**

A sweep of 483 issues, 465 PRs and 1,303 comments found three artifacts quoting him with profanity or the slur he used about himself — **agent-dotfiles #237, #174, and PR #55** — all in **agent-dotfiles, which is PUBLIC.** Zero in the other three repos. **The hook stops new ones; it does not fix these. Edit them.** This is the only rule here whose damage cannot be undone.

### S5 — Deliverables live in git. `~/.local/state` holds state, never code.
> **2026-08-11 05:46** — *"you just have a dir full of script and stuff you are using to cheat to make things work… i am going to look [bad] to consumers of my skills casue yea it works you have all the magic [stuff] in a .local folderr."*

**Mechanism:** a `PostToolUse` hook on `Write`/`Edit` rejecting any path under `~/.local/state/**` whose content starts `#!` or whose name ends `.sh`/`.py`. Plus a daily auditor cross-checking `find ~/.local/state -name '*.sh' -o -name '*.py'` against `git ls-files`; orphans page him.
**Status: enforceable today. CURRENTLY VIOLATED** by `phase-report.sh`.

---

### S6 — A question is never recorded as a decision.
> **2026-08-16 22:05** — *"itemizes the prompts into questions, thoughts, parameters etc… and again. this at some point should bea tool not soemthing that relies on inference (ai)."*

**Mechanism, two parts:** (a) a SQLite `BEFORE INSERT` trigger on `items` raising when the joined `prompts.text_raw` is interrogative and `NEW.weight='hard'`, interrogation decided by fixed regex; (b) **rewrite `itemize_prompts.py` so `kind` and `weight` come from deterministic rules and the model may only propose `body` text.** The trigger alone is insufficient while the classifier is a model grading its own homework.
**Status: needs one migration plus one rewrite. Currently 581 hard items are contaminated.**

### S7 — The corpus must be provably complete and provably verbatim.
> **2026-08-16 19:19** — *"remember all of my prompts i have sent are gold."*

**Mechanism:** a CI check asserting (a) every real user message in the transcript set has a byte-for-byte matching `prompts.text_raw`, and (b) every `text_raw` is an exact substring of some source `.jsonl`. Any paraphrase fails the build.
**Status: enforceable today. Currently failing** — three of his most consequential instructions are absent and 7 rows are paraphrase.

### S8 — The conflict detector must be able to fire, and be proven to.
> **2026-08-16 19:42** — *"prevent conflicts / prevent the possibilties from being reduced tto 0."*

**Mechanism:** a CI assertion — if `count(items) > 500` and `count(links) = 0`, fail. And replace the never-run LLM linker with a deterministic comparator over `resolved_to` keys.
**Status: NOT enforceable today, because nothing populates `links`.** What would make it so: write the linker as a script. Also fix `possibility_count`, which currently reports a count of parameters under the name of a count of possibilities.

### S9 — Tested code with zero callers is a defect.
> Derived from the abandonment pattern and **2026-08-16 20:13**.

**Mechanism:** CI asserting every module under `scripts/supervisor/` has at least one non-test importer. `acp_transport.py` fails it today — the repo already says so in two files.
**Status: enforceable today. Not built.**

### S10 — Branch and worktree ceilings.
> **2026-08-19 01:14** — *"we need to delete the noise and drop all brnaches that are not in use."*

**Mechanism:** the daily auditor pages when any repo exceeds 25 non-main branches or 10 worktrees, and runs `git worktree prune` unconditionally.
**Status: enforceable today. CURRENTLY VIOLATED.** The thresholds are this seat's numbers, not his — he gave the direction, not the figure. He should overrule them freely.

---

## Not enforceable — stated honestly rather than pretended

- **"Do research first, don't answer from training data"** (2026-08-14 16:00). No hook can distinguish a claim from weights from a claim from a page. The nearest proxy — requiring a `Sources:` block in every PR body — checks paperwork, not honesty. **Do not claim this one is covered.**
- **"Ask a council before concluding"** (31 messages). S1 can verify a subagent call *happened* since the last user message. It cannot verify the reviewer was given a lens it could fail on. Full enforcement needs a schema for the reviewer prompt plus an assertion that verdicts are sometimes adverse.
- **"30 issues per 30 minutes"** (2026-08-19 01:09, tightened 05:01 — *"it was not 30 for the day. it was 30 in 30 minutes"*). That is 1,440/day. Measured: **08-17 → 4 closed. 08-18 → 10. 08-19 → 61.** **This target must not be encoded**, because encoding an unmeetable number manufactures exactly the theatre he is angry about. Encode instead: the report states the real rate every 30 minutes, and he sets the number with that in front of him.
- **The 30-minute report currently suppresses itself.** `jon-report.log`, 2026-08-19 19:16: *"nothing closed in the window and every repo read cleanly -- not sending."* Silence when nothing happened is the exact condition he most needs told about. **Change: always send. A zero is the most important number in the report.**

## Outstanding item not covered by any rule

`agent-tui` is still **PRIVATE**, against 2026-08-19 08:17 — *"i think we should make agent-tui public when we can. i want to be able to share my work / get feedback from others."* One command. Nine hours old. Not done.

## One thing this seat will not soften

S1 — the Stop hook — would have prevented most of this week on its own, and it is roughly forty lines of bash. It was never written, across nine days, by an agent that was told to stop stopping in 52 separate messages. That is not a capability gap. The agent's judgement was never the constraint that failed; the absence of anything outside its judgement was.