# Council seat — raw agent output

**task-id**: `a0cff2f6a330a50b2`  
**brief opens**: READ ONLY. Never write to this database. Open it read-only (sqlite3 'file:PATH?mode=ro' or `sqlite3 -readonly`).  DB: /Users/jon/.local/state/agent-dotfiles-supervisor/le…

---

## Access method

`sqlite3 'file:...?mode=ro'` alone failed (`unable to open database file` — the sandbox blocks the lock/journal sidecar files). I verified the DB was safe to open immutably first, then used that. No write ever occurred.

```
$ sqlite3 "file:/Users/jon/.local/state/agent-dotfiles-supervisor/ledger.sqlite3?mode=ro&immutable=1" \
    "pragma journal_mode; pragma integrity_check;"
delete
ok
$ ls ledger.sqlite3-wal ledger.sqlite3-shm
ls: No such file or directory (both)
```

No WAL, `journal_mode=delete`, integrity ok — so `immutable=1` reads the complete, consistent database. All queries below ran against that URI.

---

## 1. Full schema (verbatim, `.schema`)

```sql
CREATE TABLE source_tasks (
                    id TEXT PRIMARY KEY,
                    source_kind TEXT NOT NULL CHECK (source_kind IN ('issue', 'pull')),
                    source_url TEXT NOT NULL,
                    source_ref TEXT NOT NULL,
                    summary TEXT NOT NULL,
                    source_state TEXT NOT NULL,
                    status TEXT NOT NULL CHECK (
                        status IN ('created', 'delivered', 'accepted', 'running',
                                   'complete', 'failed', 'cancelled')
                    ),
                    evidence_json TEXT NOT NULL,
                    status_marker TEXT,
                    updated_at INTEGER NOT NULL
                );
CREATE TABLE events (
                    key TEXT PRIMARY KEY,
                    type TEXT NOT NULL,
                    task_id TEXT REFERENCES tasks(id),
                    status TEXT NOT NULL CHECK (status IN ('pending', 'notified', 'acked')),
                    payload_path TEXT,
                    created_at INTEGER NOT NULL,
                    notified_at INTEGER,
                    retry_at INTEGER,
                    acked_at INTEGER
                );
CREATE TABLE components (
                    name TEXT PRIMARY KEY,
                    healthy INTEGER NOT NULL,
                    error TEXT,
                    snapshot_sha256 TEXT,
                    updated_at INTEGER NOT NULL
                );
CREATE TABLE pr_verdicts (
                    repo TEXT NOT NULL,
                    number INTEGER NOT NULL,
                    verdict TEXT NOT NULL CHECK (verdict IN ('approved', 'rejected')),
                    head_sha TEXT NOT NULL,
                    reviewer TEXT NOT NULL,
                    note TEXT,
                    updated_at INTEGER NOT NULL,
                    PRIMARY KEY (repo, number)
                );
CREATE TABLE IF NOT EXISTS "tasks" (
                            id TEXT PRIMARY KEY,
                            lane TEXT NOT NULL REFERENCES lanes(lane),
                            pane_nonce TEXT NOT NULL,
                            summary TEXT NOT NULL,
                            status TEXT NOT NULL CHECK (
                                status IN ('created', 'delivery_pending', 'delivered', 'accepted',
                                           'running', 'complete', 'failed', 'cancelled')
                            ),
                            result_path TEXT,
                            result_sha256 TEXT,
                            created_at INTEGER NOT NULL,
                            updated_at INTEGER NOT NULL,
                            delivery_attempted_at INTEGER,
                            delivered_at INTEGER,
                            accepted_at INTEGER,
                            completed_at INTEGER,
                            worktree_path TEXT NOT NULL DEFAULT ''
                        );
CREATE UNIQUE INDEX one_open_task_per_lane
                            ON tasks(lane)
                            WHERE status NOT IN ('complete', 'failed', 'cancelled')
                        ;
CREATE TABLE sessions (
                    session TEXT PRIMARY KEY,
                    supervised_at INTEGER NOT NULL,
                    source TEXT NOT NULL DEFAULT 'bootstrap-session.sh'
                );
CREATE TRIGGER one_open_pull_per_source_ref
                        BEFORE INSERT ON source_tasks
                        WHEN NEW.source_kind = 'pull' AND EXISTS (
                            SELECT 1 FROM source_tasks
                            JOIN tasks ON tasks.id = source_tasks.id
                            WHERE source_tasks.source_kind = 'pull'
                              AND source_tasks.source_ref = NEW.source_ref
                              AND source_tasks.id != NEW.id
                              AND tasks.status NOT IN ('complete', 'failed', 'cancelled')
                        )
                        BEGIN
                            SELECT RAISE(ABORT, 'UNIQUE constraint failed: source_tasks.source_ref');
                        END;
CREATE TABLE IF NOT EXISTS "lanes" (
                            lane TEXT PRIMARY KEY,
                            pane_id TEXT NOT NULL,
                            nonce TEXT NOT NULL,
                            harness TEXT NOT NULL CHECK (harness IN ('codex', 'claude', 'copilot', 'copilot-acp', 'pi')),
                            repo TEXT NOT NULL,
                            server_id TEXT NOT NULL,
                            session_id TEXT NOT NULL,
                            command TEXT NOT NULL,
                            -- agent-supervisor#65: NOT NULL here rejected
                            -- every pre-existing row with no resolved
                            -- session id -- every codex lane, since codex has
                            -- no resolver -- and that is legitimate data, not
                            -- a gap. See the matching column in `_initialize`.
                            harness_session_id TEXT DEFAULT '',
                            harness_project_dir TEXT DEFAULT '',
                            transport TEXT NOT NULL DEFAULT 'send-keys' CHECK (transport IN ('send-keys', 'acp', 'pi-rpc', 'claude-print')),
                            updated_at INTEGER NOT NULL
                        );
CREATE TABLE prompts (
                    id TEXT PRIMARY KEY,
                    at INTEGER NOT NULL,
                    text_raw TEXT NOT NULL,
                    text_clean TEXT,
                    -- Load-bearing, not decoration: a prompt alone is
                    -- ambiguous ("Live." means nothing without knowing it
                    -- answered "live terminal or refreshed preview?"). This
                    -- records what was being decided at the time so a row
                    -- is never misread later for lack of it.
                    context TEXT NOT NULL,
                    session TEXT,
                    source_file TEXT
                , project TEXT);
CREATE TABLE items (
                    id TEXT PRIMARY KEY,
                    prompt_id TEXT NOT NULL REFERENCES prompts(id),
                    kind TEXT NOT NULL CHECK (
                        kind IN ('parameter', 'question', 'directive', 'thought', 'correction')
                    ),
                    body TEXT NOT NULL,
                    weight TEXT NOT NULL CHECK (weight IN ('hard', 'preference', 'retracted')),
                    status TEXT NOT NULL DEFAULT 'open' CHECK (
                        status IN ('open', 'acknowledged', 'acted', 'resolved', 'dropped')
                    ),
                    -- `dropped(reason)` in the brief: the reason lives here,
                    -- alongside the status it explains, rather than folded
                    -- into the status string itself -- the same shape as
                    -- `pr_verdicts.note` and `source_tasks.status_marker`
                    -- elsewhere in this ledger. NULL unless status='dropped'.
                    status_reason TEXT,
                    -- The parameter this prompt actually produced, e.g.
                    -- 'render=LIVE'. Turns "what did he mean" from literary
                    -- interpretation into a lookup -- the entire point.
                    resolved_to TEXT,
                    acked_at INTEGER
                );
CREATE TABLE links (
                    item_id TEXT NOT NULL REFERENCES items(id),
                    other_item_id TEXT NOT NULL REFERENCES items(id),
                    relation TEXT NOT NULL CHECK (
                        relation IN ('conflicts_with', 'supersedes', 'depends_on')
                    ),
                    PRIMARY KEY (item_id, other_item_id, relation)
                );
CREATE VIEW unacknowledged AS
                    SELECT * FROM items WHERE status = 'open'
/* unacknowledged(id,prompt_id,kind,body,weight,status,status_reason,resolved_to,acked_at) */;
CREATE VIEW live_parameters AS
                    SELECT * FROM items WHERE kind = 'parameter' AND weight != 'retracted'
/* live_parameters(id,prompt_id,kind,body,weight,status,status_reason,resolved_to,acked_at) */;
CREATE VIEW conflicts AS
                    SELECT
                        l.item_id,
                        l.other_item_id,
                        a.prompt_id AS item_prompt_id,
                        a.kind AS item_kind,
                        a.status AS item_status,
                        b.prompt_id AS other_prompt_id,
                        b.kind AS other_kind,
                        b.status AS other_status
                    FROM links l
                    JOIN items a ON a.id = l.item_id
                    JOIN items b ON b.id = l.other_item_id
                    WHERE l.relation = 'conflicts_with'
/* conflicts(item_id,other_item_id,item_prompt_id,item_kind,item_status,other_prompt_id,other_kind,other_status) */;
CREATE VIEW open_questions AS
                    SELECT * FROM items WHERE kind = 'question' AND status = 'open'
/* open_questions(id,prompt_id,kind,body,weight,status,status_reason,resolved_to,acked_at) */;
CREATE VIEW possibility_count AS
                    SELECT COUNT(*) AS count FROM live_parameters WHERE weight = 'hard'
/* possibility_count(count) */;
CREATE TABLE pr_authorship (
                    repo TEXT NOT NULL,
                    pr_number TEXT NOT NULL,
                    task_id TEXT NOT NULL REFERENCES tasks(id),
                    recorded_at INTEGER NOT NULL,
                    PRIMARY KEY (repo, pr_number)
                );
CREATE TABLE pr_external_authorship (
                    repo TEXT NOT NULL,
                    pr_number TEXT NOT NULL,
                    note TEXT,
                    recorded_at INTEGER NOT NULL,
                    PRIMARY KEY (repo, pr_number)
                );
CREATE TABLE pr_no_lane_contributor (
                    repo TEXT NOT NULL,
                    number INTEGER NOT NULL,
                    note TEXT NOT NULL,
                    recorded_by TEXT NOT NULL,
                    recorded_at INTEGER NOT NULL,
                    PRIMARY KEY (repo, number)
                );
```

Inventory: **13 tables, 5 views, 1 unique index (`one_open_task_per_lane`), 1 trigger (`one_open_pull_per_source_ref`)**. There are no other user-defined indexes.

## 2. Row counts — every table and view

`SELECT COUNT(*) FROM "<name>";` for each:

| Object | Type | Rows |
|---|---|---|
| items | table | **5544** |
| prompts | table | **3683** |
| tasks | table | 1536 |
| source_tasks | table | 873 |
| events | table | 703 |
| lanes | table | 196 |
| pr_external_authorship | table | 7 |
| sessions | table | 5 |
| pr_verdicts | table | 1 |
| **links** | table | **0** |
| **components** | table | **0** |
| **pr_authorship** | table | **0** |
| **pr_no_lane_contributor** | table | **0** |
| live_parameters | view | 1059 |
| unacknowledged | view | 433 |
| open_questions | view | 69 |
| **conflicts** | view | **0** |
| possibility_count | view | 1 row, value = **920** |

## 3. `links` = 0 rows → `conflicts` can never return a row

Confirmed: `SELECT COUNT(*) FROM links;` → `0`. `SELECT COUNT(*) FROM conflicts;` → `0`.

The view SQL, quoted:

```sql
CREATE VIEW conflicts AS
    SELECT l.item_id, l.other_item_id,
           a.prompt_id AS item_prompt_id, a.kind AS item_kind, a.status AS item_status,
           b.prompt_id AS other_prompt_id, b.kind AS other_kind, b.status AS other_status
    FROM links l
    JOIN items a ON a.id = l.item_id
    JOIN items b ON b.id = l.other_item_id
    WHERE l.relation = 'conflicts_with'
```

Mechanically: the `FROM` clause is `links l`, and both `JOIN`s are **inner** joins. An inner join's result cardinality is bounded above by the product of its inputs; with `|links| = 0`, the driving relation produces zero tuples, so the first `JOIN items a` produces zero, the second produces zero, and `WHERE` filters a zero-row set. There is no `LEFT JOIN`, no `UNION`, and no aggregate that could manufacture a row from an empty input (unlike `possibility_count`, whose bare `COUNT(*)` always yields exactly one row). **The view is structurally incapable of returning a row until `links` is non-empty.**

This is not a transient state. `links` is written only by `record_link()` at `/Users/jon/source/repos/Personal/agent-supervisor/scripts/supervisor/core.py:3358-3367`, and nothing outside the test suite calls it:

```
$ grep -rn "record_link" --include="*.py" --include="*.sh" . | grep -v "/tests/"
(no output)
```

The itemiser explicitly declines to populate it — `/Users/jon/source/repos/Personal/agent-supervisor/scripts/supervisor/itemize_prompts.py:37-41`:

> `links` (conflicts_with/supersedes/depends_on) are NOT produced here. agent-supervisor#303's brief is explicit: "Do NOT make `conflicts` infer anything. It reports recorded links only." A link is recorded separately, by whoever (human or a later, deliberate pass) actually decided two items relate.

So `conflicts` is a designed-in no-op with no production writer. **The corpus's entire conflict-detection capability is dead**, which matters because Jon's own stated design goal (recorded in `items`) is that his parameters "should not cause conflicts."

## 4. `items` columns and distributions

`PRAGMA table_info(items);` — 9 columns: `id` (TEXT PK), `prompt_id` (TEXT NOT NULL), `kind` (TEXT NOT NULL), `body` (TEXT NOT NULL), `weight` (TEXT NOT NULL), `status` (TEXT NOT NULL DEFAULT 'open'), `status_reason` (TEXT), `resolved_to` (TEXT), `acked_at` (INTEGER).

There is **no `type` column and no `source` column** on `items`. The three enumerated columns are `kind`, `weight`, `status`; provenance is `prompt_id` → `prompts.id` only.

**weight**: hard 2482 · retracted 2337 · preference 725
**kind**: thought 2496 · directive 1379 · parameter 1059 · question 448 · correction 162
**status**: dropped 2368 · acted 1774 · resolved 582 · open 433 · acknowledged 387

**kind × weight**:

| kind | hard | preference | retracted |
|---|---|---|---|
| correction | 157 | 5 | 0 |
| directive | 1255 | 112 | 12 |
| parameter | 920 | 139 | 0 |
| question | 122 | 325 | 1 |
| thought | 28 | 144 | 2324 |

Note `question` + `hard` = **122** — 122 items are simultaneously typed as open questions and weighted as binding constraints.

## 5. THE KEY MEASUREMENT

**The column you asked about does not exist on `items`.** There is no source-prompt-text column and no transcript uuid/line reference on `items`. What exists instead: `items.prompt_id` is a `REFERENCES prompts(id)` foreign key, and `prompts` holds the source text in `text_raw` (NOT NULL) plus `text_clean` (nullable), `context`, `session`, `source_file`, `project`.

Two things about that provenance you should know before reading the numbers:

- `text_clean` is **NULL in 3502 of 3683 rows** (95%). Only `text_raw` is usable.
- `source_file` shows 3673 prompts come from Claude Code transcript `.jsonl` files (verbatim Jon text) and 10 from `idea.sh` (`session='idea-capture'`), whose `text_raw` is **third-person agent-written summary**, not Jon's words at all (e.g. `"Jon wants those surfaced over time so he can deliberately adopt the good ones"`). Those 10 are already not verbatim prompts.

Classifier (exactly as specified — ends in `?` OR begins with an interrogative), run in SQL:

```sql
WITH norm AS (
  SELECT id, trim(replace(replace(replace(text_raw, char(13),' '), char(10),' '), char(9),' ')) AS t
  FROM prompts
),
fw AS (
  SELECT id, t,
         lower(trim(CASE WHEN instr(t,' ')>0 THEN substr(t,1,instr(t,' ')-1) ELSE t END,
                    '?,.:;!''"()[]{}*-')) AS first_word,
         lower(t) AS lt
  FROM norm
),
q AS (
  SELECT id, t, first_word,
         CASE WHEN t LIKE '%?' THEN 1 ELSE 0 END AS ends_q,
         CASE WHEN first_word IN ('what','why','how','when','where','which','who',
                                  'should','can','could','would','do','does','did',
                                  'is','are','was','were','have','has','will','any')
                   OR lt LIKE 'am i %' OR lt LIKE 'am i?%' OR lt = 'am i'
              THEN 1 ELSE 0 END AS starts_q
  FROM fw
)
```

Prompt-level: 3683 total · 375 end in `?` · 238 start interrogative · **492 classified as questions**.

The measurement:

```sql
SELECT (SELECT COUNT(*) FROM items) AS total_items,
       (SELECT COUNT(*) FROM items WHERE weight='hard') AS hard_items,
       COUNT(*) AS hard_from_question,
       ROUND(100.0*COUNT(*)/(SELECT COUNT(*) FROM items WHERE weight='hard'),2) AS pct_of_hard,
       ROUND(100.0*COUNT(*)/(SELECT COUNT(*) FROM items),2) AS pct_of_all
FROM items i JOIN q ON q.id=i.prompt_id
WHERE i.weight='hard' AND (q.ends_q=1 OR q.starts_q=1);
```

```
total_items  hard_items  hard_from_question  pct_of_hard  pct_of_all
5544         2482        305                 12.29        5.5
```

| Measure | Count |
|---|---|
| Total items | **5544** |
| Total `weight='hard'` | **2482** |
| Hard items whose source prompt is a question | **305** |
| — as % of hard items | **12.29%** |
| — as % of all items | **5.50%** |

Strict variant (source prompt literally ends in `?`, no interrogative-start inference): **209 items, 8.42% of hard**. The gap between 305 and 209 is 96 items caught only by the interrogative-start rule, which has a real false-positive mode — e.g. `"Do (1), and your reason for it is the right one: …"` is a directive that starts with "do". Treat **209 as the floor and 305 as the ceiling**; the floor alone is already large.

Excluding prompts the pipeline itself flagged as agent-authored: **303** — so this is essentially all genuine Jon text, not contamination.

Breakdown of the 305 by item kind:

| kind | n |
|---|---|
| directive | 97 |
| parameter | 88 |
| question | 79 |
| correction | 36 |
| thought | 5 |

**The 185 `directive` + `parameter` rows are the defect.** A hard `question` row (79) is honestly labelled — it says "this is unresolved." A hard `directive`/`parameter` mined from a question asserts a decision that was never made. And 88 of them are `parameter`, the kind that feeds `live_parameters` and `possibility_count` — i.e. they are actively narrowing the solution space.

By status, the 305 split: acted 140 · resolved 63 · acknowledged 53 · open 39 · dropped 10. **140 have already been acted on.**

All items from question prompts by weight: preference 366 · hard 305 · retracted 56.

## 6. Fifteen worst cases — stored assertion vs. the question it was mined from

All verbatim from `items.body` and `prompts.text_raw`. Every one is `weight='hard'`.

**1.** `it-dcee3fa067c9fab7` — `parameter` / resolved / `resolved_to=openbao_ownership=infra`
- **Prompt:** `where does openbao belong? App or Infra?`
- **Stored:** `OpenBao belongs to infra, not the app.`
- He named two options and asked which. The answer was recorded as his decision.

**2.** `it-c403028cab9d7bc8` — `parameter` / acted / `resolved_to=green_pr=merge_without_jon`
- **Prompt:** `Why is it waiting on me?`
- **Stored:** `Do not park green, mergeable PRs on me — merge them yourself and only escalate the genuinely gated ones.`
- A four-word question about one PR became a standing grant of merge authority. This one *expands agent autonomy* from a question.

**3.** `it-4e0228976563214d` — `parameter` / acknowledged / `resolved_to=burn_rate=underuse_is_a_defect`
- **Prompt:** `how is the corpus doing. any reason our burn is so slow?`
- **Stored:** `Slow quota burn is itself a problem — underuse of available capacity means the estate is not working hard enough.`
- He asked for an explanation. It was stored as a policy that spending more is correct.

**4.** `it-322d603af8929cb8` — `parameter` / resolved / `resolved_to=automation_interrupts=literal_string_gated`
- **Prompt:** `are you sure that second cron you setup wont kill a in progress job?`
- **Stored:** `An automation must not be able to interrupt work already in flight; interrupt conditions must be gated on literal evidence rather than judgement.`
- A request for verification of something the agent built became an architectural rule attributed to Jon.

**5.** `it-6a7ee6fd96b97f55` — `directive` / acted / `resolved_to=supervisor_repo=separate_from_agent_dotfiles`
- **Prompt:** `eta until work is done with supervisor? i think we might need to move it out of agent dotfiles soon. Its seems like this is becoming an app on its own what do you thing?`
- **Stored:** `The supervisor is becoming an app in its own right and should move out of agent-dotfiles soon -- what do you think?`
- The stored body **still contains "what do you think?"** and is nonetheless `kind=directive`, `weight=hard`, `status=acted`, with a `resolved_to` parameter set. The record openly says it is a question and is filed as a decision anyway.

**6.** `it-2e0cac55adb8d6e2` — `directive` / **open** / `resolved_to=NULL`
- **Prompt:** `can you not test on my mac or use the remote.hill90.com vps?`
- **Stored:** `Do not test on Jon's Mac -- use the remote.hill90.com VPS instead.`
- Grammatically ambiguous ("can you not X, or use Y?"). Resolved to the strict reading and stored hard.

**7.** `it-d7eb3931d20ccbfc` — `directive` / acted / `resolved_to=NULL`
- **Prompt:** `i guess you can close the dns lanes we wont need those again yea?`
- **Stored:** `Close the DNS lanes — we will not need them again.`
- "i guess … yea?" is maximal hedging. The hedge was stripped and the result made binding and acted on.

**8.** `it-33a2dfd8750dbc56` — `directive` / dropped / `resolved_to=NULL`
- **Prompt:** `you are writing a lot of code. Should i be able to view anything?`
- **Stored:** `Give Jon something viewable as code is written; a long stretch of invisible output is not acceptable.`
- "Should I…?" is a request for the agent's opinion. Stored as Jon declaring a standard, including the judgement "not acceptable" which he never said.

**9.** `it-fd96280fce27387a` — `directive` / dropped / `resolved_to=NULL`
- **Prompt:** `shouldnt the readme have way more then that. it only talks about dev?`
- **Stored:** `The README must cover more than dev; it is too thin.`
- "Shouldn't it…?" → "must".

**10.** `it-346e8463724ec59f` — `directive` / acted / `resolved_to=NULL`
- **Prompt:** `when will we start talking to agents of acp?`
- **Stored:** `Move agent communication onto a real protocol (ACP/RPC) rather than tmux keystrokes.`
- A "when" question about timing became a directive to change transports — and `/Users/jon/.local/state/agent-dotfiles-supervisor/` shows this was later judged a mis-prioritisation (prompt `mp-5b332a9124edbedc`, 2026-08-19: *"The ask was never to replace tmux lanes…"*). This item is a traceable cause of real misdirected work.

**11.** `it-75c8732b8afbc9de` — `parameter` / acknowledged / `resolved_to=estate_operation=unattended_overnight`
- **Prompt:** `so we good now. things will run tonight?`
- **Stored:** `The estate is expected to keep working unattended overnight.`
- Asking for reassurance before bed, stored as a requirement he set.

**12.** `it-d38d4d0ed86f398c` — `parameter` / acknowledged / `resolved_to=overnight_runs=must_self_recover`
- **Prompt:** `okay i am going to bed. we sure things wont get stuck?`
- **Stored:** `Overnight runs must survive without Jon awake to unstick them.`
- Same pattern, same night, second parameter minted from the same worry.

**13.** `it-1c5b188634d178c4` — `parameter` / **open** / `resolved_to=docs=updated_inline`
- **Prompt:** `so what is next. And you have updated the docs along the way yea?`
- **Stored:** `Docs are updated along the way, not as a later sweep`
- He was *checking whether the agent had done it*. Stored as his process rule — and the stored form asserts it as fact, not obligation.

**14.** `it-5d5dba1f971402ef` — `parameter` / acted / `resolved_to=worker_model=sonnet; director_model=opus`
- **Prompt:** `it says i have used 71% of my weekly limit. I just got it back august 10th at 6 am. What models are you using? Opus or Sonnet. do we need Sonnet for the workers? I dont think so if our Director uses opus yea?`
- **Stored:** `Workers do not need Opus -- run the workers on Sonnet and keep the Director on Opus.`
- Three questions and an explicit "I dont think so … yea?" — a hypothesis put up for correction. Stored as a settled model-routing policy, and acted on.

**15.** `it-e7a1f787b5115b2f` — `parameter` / acted / `resolved_to=system=self_repairing`
- **Prompt:** `with the idea of our skills is is setup in a way where we can use our system to fix our system?`
- **Stored:** `The skills are set up so the system can be used to fix the system`
- A question about whether something is true was stored as an assertion that it is true. This is the purest case: **interrogative → declarative with no other change.**

Two more worth naming:

**16.** `it-35ab7f7bb618fa1c` — `parameter` / resolved / `bringup_order=infra_then_app`. Prompt: `it will have to deploy to hill90 local infra before it does the app yea. its knows that?` → `Hill90 infra comes up first and owns the shared networks; the app attaches to it as a tenant afterwards.` The stored body adds "and owns the shared networks," which appears nowhere in the prompt.

**17.** `it-0f6f4b778302cde9` — `directive` / hard / acknowledged. Prompt: `I didnt tell it to you did. Do you think we need it?` → `Do not attribute a decision to Jon that he did not make; check who actually asked for it.` Jon caught this exact failure mode in conversation. The corpus recorded the warning against it by committing it.

## 7. Other integrity problems

**Empty tables with dependents**
- `links` = 0 → `conflicts` view permanently empty (§3). No production writer exists.
- `components` = 0, but `core.py` reads it at lines 1554, 3165, 3179 and writes at 3169, 3277. Component health tracking has recorded nothing — a health query against it cannot distinguish "healthy" from "never observed."
- `pr_authorship` = 0 while `pr_external_authorship` = 7. Authorship attribution is recording only the *external* half; every lane-authored PR is unattributed.
- `pr_no_lane_contributor` = 0.

**Orphaned foreign keys — none.** `PRAGMA foreign_key_check` returns empty. Explicit joins confirm: `items.prompt_id`→`prompts` 0 orphans, `events.task_id`→`tasks` 0, `tasks.lane`→`lanes` 0, `source_tasks.id`→`tasks` 0, `pr_authorship.task_id`→`tasks` 0, `links.item_id`→`items` 0. Referential integrity is clean.

**Duplicated items — 1289 rows across 40 distinct bodies (23.3% of all items).** Zero are exact `(prompt_id, body)` duplicates, so these are the same boilerplate applied to different prompts. The top ones:

```
829 x  Agent-authored dispatch brief
 78 x  Machine-authored text harvested as a user turn
 75 x  No durable instruction from Jon in this prompt.
 40 x  No durable instruction from Jon: this prompt was written by a supervisor agent driving a worker lane, not by J…
 38 x  Supervisor-authored lane instruction about closing, narrowing, verifying or handing off issues and PRs; carrie…
 38 x  Nothing durable of Jon's here: this is a supervisor agent's task brief to a worker lane (PR review notes, next…
 37 x  Nothing durable from Jon in this prompt: it is a supervisor agent's turn-by-turn brief to a coding lane.
 31 x  Nothing durable from Jon in this prompt.
 24 x  A supervisor-authored dispatch or review brief sent to a worker lane; carries no durable instruction from Jon…
 13 x  A synthetic probe string used to drive a test pane or check tool permissions; carries no durable instruction f…
```

**This is the largest finding by volume.** The "prompt corpus" is not a corpus of Jon's prompts:

- **1773 of 3683 prompts (48.1%)** carry an item explicitly flagging them as agent- or machine-authored.
- **2307 of 3683 prompts (62.6%)** yielded *only* retracted items — fully discarded as not-Jon.
- Only **1376 prompts (37.4%)** produced any live signal.

So the "3,683 prompts" figure overstates Jon's actual input by ~2.7×. Note also that 6 of those 1289 boilerplate rows are `directive`/`hard`/`acted` — i.e. text explicitly identified as machine-authored is nonetheless stored as a binding directive and acted on.

**Corpus span contradicts its own advertised size.** `MIN(at)=2026-06-14 21:54:41 UTC`, `MAX(at)=2026-08-19 08:44:03 UTC` — **65.5 days**. The `context` field of prompt `mp-793d5c130b32db9c` records the agent describing the corpus to Jon as *"Every prompt you've sent — 3,584 of them, fourteen months."* The database covers roughly two months, not fourteen. No prompt predates 2026-06-14.

**No impossible timestamps.** `prompts.at`: 0 non-positive, 0 in the future. `tasks`: 0 rows where `completed_at < created_at`. Range 2026-08-11 21:21:16 → 2026-08-19 18:31:57 UTC. Clean.

**`items.acked_at` is a dead column.** 1 of 5544 rows is non-NULL — and 386 of 387 rows with `status='acknowledged'` have `acked_at IS NULL`, as do all 1774 `acted`, all 582 `resolved`, and all 2368 `dropped`. The status transitions are recorded with no timestamp, so **there is no way to date when any item was acknowledged or acted on**, and no way to detect a stale binding parameter by age.

**Null provenance on parameters.** `resolved_to` is NULL on 4479 of 5544 items. More pointedly, **81 of the 920 hard live parameters have `resolved_to IS NULL`** — a parameter that, per the schema comment ("Turns 'what did he mean' from literary interpretation into a lookup — the entire point"), resolves to nothing. `possibility_count` reports 920; 81 of those are not actually usable as lookups. `status_reason` is correctly populated: 0 rows with `status='dropped'` and NULL reason.

**Events pipeline has never delivered.** All 703 events are `status='pending'`, all 703 have `notified_at IS NULL` and `acked_at IS NULL`, and 0 have a `retry_at`. Oldest is 2026-08-12 05:00:14 UTC — a week of completion events (702 `completion`, 1 `session`) queued and never notified.

**Task cancellation rate.** 713 of 1536 tasks (46.4%) are `cancelled`, vs 670 `complete` and 32 `failed`. 121 tasks sit in non-terminal states (100 `delivered`, 17 `delivery_pending`, 4 `accepted`).

**Duplicate prompt text:** 3 groups, 6 rows — negligible.

---

## Bottom line

The number you asked for is **305 hard items (12.29% of all hard items) mined from question prompts**, with **209 (8.42%)** on the strict "ends in `?`" reading. Of the 305, **185 are `directive` or `parameter`** — the kinds that assert a decision — and **140 have already been acted on**.

But the larger integrity problem is upstream of that: **62.6% of the "prompt corpus" is not Jon's prompts at all**, `links`/`conflicts` is a permanently-dead conflict detector in a system whose stated purpose is preventing conflicting parameters, and `acked_at` is unpopulated so no item's lifecycle can be dated. The question→directive conversion rate is a real defect; it is the third-largest one in this database.