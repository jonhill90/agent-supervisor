# Council seat — raw agent output

**task-id**: `a05ec2cf2fa4b735b`  
**brief opens**: READ-ONLY forensics. Absolutely no writes: do not INSERT/UPDATE/DELETE/CREATE anything in the sqlite DB, open it read-only (`sqlite3 "file:PATH?mode=ro" "..."`).  Targets…

---

# Forensics: `agent-dotfiles-supervisor`

## Method / instrument note (matters, read first)

`sqlite3 "file:...?mode=ro"` worked for the first two queries, then began failing with `Error: in prepare, unable to open database file (14)` for the rest of the session. Cause: the DB is in WAL journal mode; the `-wal`/`-shm` sidecars were checkpointed away mid-session (they were present at 15:16, absent at 15:18, back at 15:20), and a read-only open cannot create the `-shm` it needs. `sqlite3 -readonly` fails identically.

Workaround used, and it is **still zero writes to the target**: `cp` the main DB to `/tmp/ledger-forensics/l.db` and query the copy. The `-wal` was 0 bytes / absent at copy time, so the main file was complete. The temp copy has been deleted (`rm -rf /tmp/ledger-forensics` — verified gone). No file was written anywhere else.

---

## 1. Schema and row counts

`sqlite3 ... ".schema"` output is long; the tables are: `source_tasks`, `events`, `components`, `pr_verdicts`, `tasks`, `sessions`, `lanes`, `prompts`, `items`, `links`, `pr_authorship`, `pr_external_authorship`, `pr_no_lane_contributor`. Views (not tables): `unacknowledged`, `live_parameters`, `conflicts`, `open_questions`, `possibility_count`. One unique index `one_open_task_per_lane`, one trigger `one_open_pull_per_source_ref`.

```
components                     0
events                         703
items                          5544
lanes                          196
links                          0
pr_authorship                  0
pr_external_authorship         7
pr_no_lane_contributor         0
pr_verdicts                    1
prompts                        3683
sessions                       5
source_tasks                   873
tasks                          1536
```

```sql
SELECT COUNT(*) AS links_rowcount FROM links;
-- 0
```

**`links` has 0 rows.** Confirmed directly, `conflicts` view not used. Consequence: the entire conflict/supersedes/depends_on graph is empty. `items` has 5544 rows and not one of them is linked to another. The `conflicts` view can only ever return 0 rows, so any "no conflicts detected" claim built on it is blindness, not a clean bill of health.

Also empty and worth naming: `pr_authorship` = 0 rows (PR→task attribution never recorded), `components` = 0 rows (health table never populated), `pr_verdicts` = 1 row total.

## 2. `prompts`

```
cid|name|type|notnull|dflt_value|pk
0|id|TEXT|0||1
1|at|INTEGER|1||0
2|text_raw|TEXT|1||0
3|text_clean|TEXT|0||0
4|context|TEXT|1||0
5|session|TEXT|0||0
6|source_file|TEXT|0||0
7|project|TEXT|0||0
```
```
total|min_at|max_at|min_utc|max_utc
3683|1781474081|1787129043|2026-06-14 21:54:41|2026-08-19 08:44:03
```

Only timestamp column is `at` (unix seconds). Range 2026-06-14 21:54:41 UTC → 2026-08-19 08:44:03 UTC, 66 calendar days spanned, **32 distinct days with any row**.

## 3. Contamination measurement

Individual tells (SQL as run, `char(8212)` = em-dash):

```sql
SELECT COUNT(*) AS total,
 SUM(text_raw LIKE '%'||char(8212)||'%')                        AS emdash,
 SUM(text_raw LIKE '%Jon%')                                     AS thirdperson_Jon,
 SUM(text_raw LIKE '%Verified%')                                AS verified,
 SUM(text_raw LIKE '%`%')                                       AS backtick,
 SUM(text_raw LIKE '%'||char(10)||'- %' OR text_raw LIKE '- %') AS md_bullet,
 SUM(text_raw LIKE '%**%')                                      AS md_bold,
 SUM(text_raw GLOB '*[#][# ]*' OR text_raw GLOB '#*')           AS hash_header,
 SUM(length(text_raw) > 1200)                                   AS len_gt_1200,
 SUM(length(text_raw) > 400)                                    AS len_gt_400,
 SUM(text_raw LIKE '%'||char(10)||'%')                          AS multiline
FROM prompts;
```
```
total  emdash  thirdperson_Jon  verified  backtick  md_bullet  md_bold  hash_header  len_gt_1200  len_gt_400  multiline
3683   1034    1608             441       277       182        56       301          1050         1738        814
```
```sql
SELECT COUNT(*) FROM prompts WHERE text_raw GLOB '*#[# ]*[A-Z][A-Z][A-Z]*';  -- ALL-CAPS md header: 37
```

Human tells:
```sql
SELECT
 SUM(lower(text_raw) LIKE '% teh %' OR lower(text_raw) LIKE 'teh %') AS teh,
 SUM(lower(text_raw) LIKE '%yea%')      AS yea,
 SUM(text_raw LIKE '%dont%')            AS dont,
 SUM(text_raw LIKE '%cauuse%')          AS cauuse,
 SUM(text_raw LIKE '%whatt%')           AS whatt,
 SUM(text_raw GLOB '*[ ]i[ ]*')         AS lowercase_i,
 SUM(text_raw = lower(text_raw))        AS all_lowercase,
 SUM(length(text_raw) <= 200)           AS len_le_200,
 SUM(length(text_raw) <= 120)           AS len_le_120
FROM prompts;
```
```
teh  yea  dont  cauuse  whatt  lowercase_i  all_lowercase  len_le_200  len_le_120
4    178  173   0       1      359          572            1065        785
```

Composite score (sum of 8 boolean tells: em-dash, "Jon", "Verified", backtick, newline-bullet, `**`, ALL-CAPS `#` header, len>1200):

```sql
WITH scored AS (
  SELECT id,
    (text_raw LIKE '%'||char(8212)||'%') + (text_raw LIKE '%Jon%')
  + (text_raw LIKE '%Verified%')        + (text_raw LIKE '%`%')
  + (text_raw LIKE '%'||char(10)||'- %')+ (text_raw LIKE '%**%')
  + (text_raw GLOB '*#[# ]*[A-Z][A-Z][A-Z]*') + (length(text_raw) > 1200) AS agent_score
  FROM prompts)
SELECT agent_score, COUNT(*) FROM scored GROUP BY agent_score;
```
```
score  rows
0      1304
1      1289
2       434
3       328
4       186
5        75
6        46
7        19
8         2
```
```
score0_likely_human  score1_ambiguous  score2plus_clearly_agent  score3plus  total
1304                 1289              1090                      656         3683
```

Direct provenance strings (unambiguous machine-authored markers):
```
supervisor_loop_tick  any_loop_tick  system_reminder  slash_command  caveat_block  continuation  verified_dated
29                    37             1                0             0             0             3
```

**Estimate.** Clearly agent-written: **1090 rows (29.6%)** at score ≥2; **656 (17.8%)** at the conservative score ≥3. Likely human: **1304 (35.4%)** at score 0. **1289 rows (35.0%) are ambiguous at score 1** — single-tell rows, most commonly a bare em-dash or the token "Jon". I cannot resolve those from text alone, and no column resolves them either (see §4). Upper bound on contamination is therefore 1090+1289 = **2379 (64.6%)**; lower bound 1090 (29.6%). Corroborating: 1050 rows (28.5%) exceed 1200 chars and 1738 (47.2%) exceed 400 chars — Jon's described register does not produce a 4000-char prompt, and the longest rows are verbatim supervisor loop messages.

Five clearest agent rows (score ≥4, most recent, truncated to 300 chars, newlines shown as `\n`):

```
--- id=mp-b07e34de5b480891 at=2026-08-17 00:24:14 len=2227 score=4
STOP MIGRATING LANES. A REGRESSION IS ACTIVE AND EVERY MIGRATION MAKES IT WORSE. \n \n MEASURED JUST NOW: \n claude-print lanes: 32 with a usable harness_session_id: 0 \n send-keys lanes: 20 with a usable harness_session_id: 20 \n \n EVERY MIGRATED LANE IS UNRECOVERABLE. The transport itself is fine -- c

--- id=mp-4f7af8ff614e1cd6 at=2026-08-16 23:39:00 len=3772 score=6
Supervisor loop tick. **SETTLED PRIORITY: A then B, nothing else.** \n \n **REPORT ONE NUMBER: STRANDED LANES = 1.** Trend today: 13 → 4 → 3 → 1 → **1**. Working: 2. Transport **claude-print 25 / send-keys 29**. \n \n **#294's ACCEPTANCE IS MET — reviews are unblocked.** Verified by the next dispatch, not the

--- id=mp-40920828cb85fc43 at=2026-08-16 23:21:00 len=4202 score=6
Supervisor loop tick. **SETTLED PRIORITY: A then B, nothing else.** \n \n **REPORT ONE NUMBER: STRANDED LANES. Last measured 1** (agent-tui:2 `as251-rev251`) — down from 13 → 4 → 3 → **1**. Transport **claude-print 25 / send-keys 29**. \n \n **PR #294 MERGED (876edb12e5) — lane identity for author exclusion.*

--- id=mp-887eac8a5fca148b at=2026-08-16 22:47:00 len=4368 score=5
Supervisor loop tick. **THE SETTLED PRIORITY — supersedes every earlier priority message. It is in PHASES.md.** \n \n **THE ONE THESIS: "A great harness does not make a weak model strong. It stops a strong model from being wasted." EVERYTHING THAT MATTERS IS WASTE ELIMINATION.** \n \n **DO A THEN B AND NOTHIN

--- id=mp-f979fef93058dc35 at=2026-08-16 22:06:00 len=4624 score=5
Supervisor loop tick. **PRIORITY: transport migration — PR #288 CLEAN, CI green at 56d16e8e, independent review dispatched. Collect that verdict first.** It took live dispatchable send-keys panes from 14 → 4. \n \n **DISPATCHED: pre-dispatch COLLISION CHECK into dispatch.sh.** Prevents the measured failu
```

These are cron/loop prompts injected into the transcript by the supervisor itself, harvested and stored as prompts.

## 4. Is there a `source`/`origin`/`author` column?

**No.** The full column list is in §2: `id, at, text_raw, text_clean, context, session, source_file, project`. None distinguishes human from agent.

```
distinct source_file=916   nulls=0
distinct project=486       nulls=99
distinct session=916       nulls=0
distinct context=2705
```

`source_file` and `session` are 1:1 (916 each) and are Claude Code transcript UUIDs — every row was scraped from a `.jsonl` transcript's user-role turns, which is exactly why machine-injected turns land in the table indistinguishable from typed ones. Top `source_file`: `c5aa6462-...jsonl` 340, `64f0575e-...` 207, `71d933a0-...` 193.

`project`:
```
-Users-jon-source-repos-Personal-hill90-app                 | 1057
-Users-jon-source-repos-Personal-agent-dotfiles             |  555
-Users-jon-source-repos-Personal-Hill90                     |  553
-Users-jon-source-repos-Personal-Skills                     |  333
-Users-jon-source-repos-DebateWho                           |  172
(null)                                                      |   99
-Users-jon-source-repos-Personal-AgentBox                   |   60
```

`context` is 2705 distinct values, and its single most common value (823 rows, 22.3%) is the literal string `[context undetermined: no prior assistant turn in this transcript file]` — i.e. for 823 rows the harvester could not establish what the prompt was answering.

## 5. Dispatch / task / lane / event tables

**`tasks` (1536)** — by status, with last update:
```
cancelled         713  2026-08-19 15:35:56
complete          670  2026-08-19 18:31:57
delivered         100  2026-08-19 17:08:00
failed             32  2026-08-19 02:40:34
delivery_pending   17  2026-08-17 04:17:50
accepted            4  2026-08-19 17:01:29
```
```
max(updated_at)=2026-08-19 18:31:57  max(created_at)=2026-08-19 17:08:00
ever_delivered=1509  ever_accepted=209  ever_completed=1415
```

**Work genuinely dispatched, not just intended.** 1509/1536 (98.2%) carry a non-null `delivered_at` and 1415 (92.1%) a `completed_at`. But `accepted_at` is set on only **209 (13.6%)** — the acceptance handshake fires on one task in seven, so ~1200 tasks went delivered→complete without ever being recorded as accepted. 713 cancelled is 46.4% of all tasks.

**`source_tasks` (873)**:
```
complete   653  2026-08-19 18:33:05
delivered  100  2026-08-19 17:30:44
cancelled   75  2026-08-19 05:09:41
failed      24  2026-08-19 07:13:46
created     17  2026-08-19 03:04:15
accepted     4  2026-08-19 17:30:44
```

**`events` (703)** — this is the clean failure:
```
completion  pending  702  last created 2026-08-19 18:31:57
session     pending    1  last created 2026-08-15 08:07:36

total=703  never_notified=703  never_acked=703
```
**Every event ever written is still `pending`. Zero have ever been notified, zero acked.** The completion-notification path has never fired once in the table's lifetime. Last 20 events all read `notified=NEVER`.

**`lanes` (196)**:
```
claude  claude-print  162  last 2026-08-19 17:08:00
claude  send-keys      30  last 2026-08-19 15:35:56
codex   send-keys       4  last 2026-08-14 05:47:50
```

**`items` (5544)** — dominant bucket is `thought/dropped` at **2324 (41.9%)**. Actioned: `directive/acted` 1098, `parameter/acted` 549, `correction/acted` 90. Still open: `parameter/open` 251, `question/open` 69, `directive/open` 55, `thought/open` 44, `correction/open` 14 — **433 open items**.

Last activity per table: `tasks` 2026-08-19 18:31:57 · `source_tasks` 18:33:05 · `events` 18:31:57 · `lanes` 17:08:00 · `pr_verdicts` 13:56:36 · `pr_external_authorship` 06:03:10 · `prompts` 08:44:03 · `sessions` 2026-08-16 01:59:07 (stale 3 days).

Most recent 20 rows of `tasks`, `source_tasks`, `events` were printed in full above during collection; the tasks tail shows `as356/as353/as359/as378/at42/as346/skills197` complete with `del=y acc=y cmp=y`, `as343-exec-plan` stuck at `delivered`, and two `ledger-claim:` rows cancelled.

## 6. Log files

129 `.log` files, 5,452,228 bytes total. Sizes/mtimes for the 12 non-trivial ones:

```
2236742  2026-08-19 15:18:13  watchdog.log
1340298  2026-08-19 13:15:36  inbox-poll.log
1034786  2026-08-19 15:18:14  advance-live.log
 204613  2026-08-19 15:18:13  poller-recover.log
 171071  2026-08-19 15:18:13  quota-watch-recover.log
 161274  2026-08-19 15:17:12  quota-watch.log
 112267  2026-08-19 15:16:29  notify.log
  36303  2026-08-19 15:17:57  heartbeat.log
  20686  2026-08-19 15:16:11  director-loop.log
  19696  2026-08-19 14:21:23  watchdog-notify.log
  10143  2026-08-19 15:16:29  jon-report.log
   7001  2026-08-19 15:07:30  weekly-watch.log
```
The other 117 are per-dispatch stubs, 67–1475 bytes, mtimes 2026-08-16 → 2026-08-19. Three are 0 bytes: `contest-stop.log` (15:18 today), `launchd.stdout.log`, `launchd.stderr.log` (both 2026-08-11 01:00, never written).

Grep counts (case-insensitive):
```
LOG                             LINES   ERROR    FAIL    died   stuck restart   quota
watchdog.log                    18930    1880    1804     132     189     803    1446
inbox-poll.log                  23295     145     521       0       0     290       0
advance-live.log                 8420       0     287      94       0     651      15
poller-recover.log               2705       0      38     143       0       0       0
quota-watch-recover.log           861       0       0       0       0     582     582
quota-watch.log                  1978       0       0       0       9    1969
notify.log                        971      11      67      20      26      20      20
heartbeat.log                     357       0       2       0       0       8      93
director-loop.log                 212       0       0       0       0      65       9
watchdog-notify.log               119      83      83       0       0      12       0
jon-report.log                    120       0       0       0       0       0       0
weekly-watch.log                   86       0       2       0       0       0       0
```

Lifetime aggregates (watchdog.log starts 2026-08-11T04:15:00Z):
```
RESTARTED loop total:                  70
ESCALATE: 3 restarts in 3600s total:  147
SKIPPED restart total:                  2
RESPAWNED (poller-recover.log):       143
inbox-poll STOPPING pid total:        166
inbox-poll FAIL total:                278   RECOVERED after N failure(s): 131
advance-live FAIL total:              278
```

### Loop deaths and watchdog restarts

70 loop restarts and **147 `ESCALATE: 3 restarts in 3600s; leaving the loop down deliberately`** — the watchdog hit its own restart ceiling and deliberately left the loop dead 147 times. Most recent cluster:
```
2026-08-19T02:17:45Z RESTARTED loop — idle with 154 actionable item(s)
2026-08-19T02:28:45Z RESTARTED loop — idle with 137 actionable item(s)
2026-08-19T02:33:18Z ESCALATE: 3 restarts in 3600s; leaving the loop down deliberately
2026-08-19T02:37:06Z ESCALATE: ...
2026-08-19T02:40:27Z ESCALATE: ...
2026-08-19T02:43:36Z ESCALATE: ...
2026-08-19T03:00:18Z ESCALATE: ...
2026-08-19T03:03:35Z RESTARTED loop — idle with 125 actionable item(s)
2026-08-19T17:15:12Z SKIPPED restart — pre-send re-check could not tell: no adapter under harness/ claims pane command Python
2026-08-19T18:21:22Z QUOTA-WATCH-RECOVER: RESTARTED quota-watch.sh (pid 65268) -- heartbeat 1494s old, over 600s
```
Note the restart triggers: the loop was **idle with 154 / 137 / 125 actionable items** queued.

Poller: 143 `RESPAWNED dead pane agent-supervisor:@36`. Last 10 span 2026-08-19 03:43 → 17:15. Last poller-recover line is a hard refusal:
```
2026-08-19T17:15:24Z FAILED -- inbox-poll.sh is already running (pid 2567) with no window named 'inbox-poll' in session 'agent-supervisor' -- refusing to start a second poller; it needs a window reattached, not a duplicate
```
Poller uptimes between kills, last 10: 331s, 2523s, 20022s, 26s, 331s, 12930s, 6551s, 26s, 3924s, 2040s.

### Current terminal state (last 30 lines, `watchdog.log`)

The supervisor session is **gone** and the watchdog is looping on that every 3 minutes:
```
2026-08-19T19:18:12Z no agent-supervisor session
2026-08-19T19:18:12Z HEARTBEAT-CHECK: poller reported its own stop (state: stopped) — its EXIT trap already decided whether to page
2026-08-19T19:18:12Z DIRECTOR-INBOX-CHECK: director inbox empty — nothing pending
2026-08-19T19:18:12Z POLLER-CHECK: zero live inbox-poll.sh processes by pid — dead-poller recovery handles this
2026-08-19T19:18:12Z POLLER-RECOVER: no session 'agent-supervisor' -- nothing to recover into
2026-08-19T19:18:12Z LANE-SWEEP: completed=0 failed_unaccepted=0 unresolved=100 errors=0
2026-08-19T19:18:12Z NEVER-BUSY-CHECK FAILED (streak 31): lanes.sh --json agent-supervisor: lanes: session 'agent-supervisor' does not exist
```
`LANE-SWEEP: unresolved=100` on every tick. Fail streaks on disk: `.watchdog-never-busy-check-fail-streak` = **31**, `.watchdog-guard-audit-fail-streak` = **30**.

`director-loop.log` last 30 lines: 11 consecutive `configured target director:@3 is gone (tmux renumbered across a restart); resolved to director:@35` from 14:18 to 16:59, then:
```
2026-08-19T17:16:45Z ticked director:@65 but the pane did NOT start working -- a human should look
2026-08-19T17:33:34Z target session director does not exist -- a human should look
2026-08-19T17:49:22Z / 18:26:37 / 18:43:01 / 18:59:49 / 19:16:11  (same, 5 more)
```

`advance-live.log` last 30 lines are 15 identical no-op pairs, 18:33→19:18, every ~3 min:
```
2026-08-19T19:18:14Z CURRENT: 0e2e08e60271... already matches origin/main after a fresh fetch, nothing to advance
2026-08-19T19:18:14Z POLLER-CHECK: poller already at 0e2e08e60271..., current
```
Its 278 FAILs are dominated by a single repeating condition, last 10 all between 15:09 and 15:28 today:
`FAIL: live worktree .../live has uncommitted changes -- refusing to advance a dirty tree, not stashing it`

### Quota stand-downs

`grep -ciE 'stand-down|rate limit|limit reached|usage limit' watchdog.log` = **0**. There is no quota stand-down in the watchdog log at all. The 1446 "quota" hits decompose entirely into plumbing: `QUOTA-WATCH-HEARTBEAT-CHECK` 861, `QUOTA-WATCH-RECOVER` 582 — all of them `alive` / `nothing to do`.

What actually exists is quota **blindness**, not stand-down. `quota-watch.log` tail:
```
2026-08-19T18:29:20Z quota-watch: BLIND: 2 consecutive UNKNOWN readings, confirmed state stuck at SAFE -- paging
2026-08-19T18:47:18Z quota-watch: vision restored after 4 consecutive UNKNOWN reading(s)
2026-08-19T18:59:17Z quota-watch: vision restored after 1 consecutive UNKNOWN reading(s)
2026-08-19T19:11:16Z quota-watch: BLIND: 2 consecutive UNKNOWN readings, confirmed state stuck at SAFE -- paging
2026-08-19T19:17:12Z quota-watch: reading UNKNOWN (rc=2), confirmed state is SAFE
```
`.quota-watch.state` on disk right now:
```
checked: 2026-08-19T19:17:12Z
state: UNKNOWN
confirmed: SAFE
unknown_streak: 3
blind_alarm_sent: 1
```
The meter is unreadable and the "confirmed" value is pinned at SAFE. `heartbeat.log` has 80 lines of `quota UNKNOWN (rc=2) -- refusing to nudge on an unreadable meter` out of 93 quota lines total — so quota was unreadable on 86% of the occasions the heartbeat consulted it.

### Heartbeat "all clear" vs actual dispatch

`heartbeat.log` covers 2026-08-17T05:37:20Z → 2026-08-19T19:17:57Z, 357 lines:
```
OK lines:                                   83
STALLED lines:                              42
quota UNKNOWN lines:                        80
OK while 0 pane-working:                    37   (44.6% of all OKs)
OK while 0 pane-working AND 0 in-flight:     0
```
**The heartbeat is not falsely all-clear on dispatch.** It reported OK 83 times; 37 of those were with zero panes working, but in every one of those 37 there was at least 1 in-flight task, and it never once printed OK with both counters at zero. Its recorded stall detections are real and escalating — last four:
```
2026-08-19T16:18:01Z STALLED 2169s -- nudged director:@35, pane is now working
2026-08-19T17:53:04Z STALLED 2658s -- target session director does not exist; a human should look
2026-08-19T18:45:50Z STALLED 5816s -- target session director does not exist; a human should look
2026-08-19T19:17:57Z quota UNKNOWN (rc=2) -- refusing to nudge on an unreadable meter
```
The `last ledger write` age it reports climbed monotonically today: 91s (17:05) → 755s → 1700s → 2658s (17:53) → 5816s (18:45). That matches the DB: last `tasks.created_at` is 17:08:00.

The paging path *is* live — `notify.log` last 30 lines are all `SENT telegram (supervisor)`, including `never-busy safety check has failed 3/6/9/…/30 times in a row`, `worktree-guard-audit safety check has failed 24/27/30 times in a row`, `quota-watch BLIND (#305)` twice, and `Telegram inbox poller stopped`. Between 17:24 and 19:16 Jon was paged **13 times** about the same two failing safety checks.

Where output *is* hollow is `jon-report.log`: the last 5 half-hourly cycles read
```
closed-report: nothing closed in the window and every repo read cleanly -- not sending
phase-report: sent -- 122 open, 65 closed today
```
identical `122 open, 65 closed` at 16:53, 17:23, 17:54, 18:45, 19:16 — five consecutive reports sent to Jon with an unchanged number, over the same 2.5 hours in which nothing dispatched, the director session vanished, and the watchdog paged 13 times.

`watchdog-notify.log`: 83 of 119 lines are `NOTIFY-PATH-STALE: configured notifier '/Users/jon/source/repos/Personal/agent-dotfiles/scripts/supervisor/notify.sh' does not resolve; falling back to the one shipped beside this module`. The configured notifier path has been broken since at least 2026-08-17 and every page since has gone out through a fallback.

## 7. Activity days and gaps

Distinct days: `prompts` **32**, `tasks` (by `updated_at`) **9**.

Per-day, prompts (last 20 days present):
```
2026-08-19 |   7      2026-08-09 |   1
2026-08-18 |  34      2026-08-07 |  49
2026-08-17 | 102      2026-08-06 | 177
2026-08-16 | 425      2026-08-05 | 189
2026-08-15 | 263      2026-08-04 | 253
2026-08-14 | 155      2026-08-03 | 236
2026-08-13 | 124      2026-08-02 |   5
2026-08-12 | 275      2026-08-01 |  41
2026-08-11 | 299      2026-07-31 |  95
2026-08-10 |  43      2026-07-30 |  76
```
2026-08-08 is absent entirely. Prompt capture collapses after 08-16: 425 → 102 → 34 → 7.

Per-day, tasks (`created_at` / `updated_at`):
```
2026-08-19 | 134 / 135      2026-08-15 | 287 / 292
2026-08-18 | 176 / 176      2026-08-14 | 167 / 166
2026-08-17 |  39 /  40      2026-08-13 | 223 / 222
2026-08-16 | 272 / 270      2026-08-12 | 228 / 232
                            2026-08-11 |  10 /   3
```
The `tasks` table only begins 2026-08-11 — 9 days — while `prompts` goes back to 06-14. There is no task record for the first 58 days of the prompt corpus.

**Gaps > 3 hours in the most recent 48 hours: none.** Union of `prompts.at`, `tasks.created_at`, `tasks.updated_at`, `source_tasks.updated_at`, `events.created_at`; window max = 2026-08-19 18:33:05 UTC; 494 timestamp points in window.

Positive control at a 0.5h threshold (proves the query fires):
```
2026-08-17 21:20:40 -> 22:39:57  gap=1.32h
2026-08-18 16:39:16 -> 18:59:20  gap=2.33h   <-- largest
2026-08-19 11:21:18 -> 12:20:26  gap=0.99h
2026-08-19 15:41:20 -> 16:13:02  gap=0.53h
2026-08-19 17:56:53 -> 18:31:57  gap=0.58h
(20 gaps > 0.5h in total)
```
Largest gap in 48h is **2.33h**, 2026-08-18 16:39→18:59. Caveat on that number: 24 of the 48 hours predate the current outage, and the ledger's own clock stopped advancing meaningfully after 18:33 — the gap that is opening *right now* (18:33 → 19:18+, ~45 min and counting with the session dead) is not yet 3h and so does not appear.

## Headline numbers

- `links` **0 rows** — the conflict graph across 5544 `items` is completely empty; the `conflicts` view is structurally incapable of returning anything.
- `events` **703 rows, 703 never notified, 703 never acked** — the completion-notification path has fired zero times, ever.
- `prompts` **1090/3683 (29.6%) clearly agent-written**, 1289 (35.0%) ambiguous, upper bound 64.6%. No column distinguishes them; all 3683 were scraped from Claude Code transcript user-turns.
- `tasks` **1509/1536 delivered, 1415 completed, but only 209 (13.6%) ever accepted**; 713 (46.4%) cancelled.
- **147** `ESCALATE: leaving the loop down deliberately`, **70** loop restarts, **143** dead-pane poller respawns, **166** poller stops.
- Right now: `agent-supervisor` session does not exist, `director` session does not exist, zero live pollers, never-busy fail streak 31, guard-audit fail streak 30, quota meter UNKNOWN with `blind_alarm_sent: 1`, last task created 2026-08-19 17:08:00 UTC.
- `pr_authorship` 0 rows, `components` 0 rows, `pr_verdicts` 1 row.