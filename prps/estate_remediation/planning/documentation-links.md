# Documentation Resources: estate_remediation

**Phase 2B of /generate-prp.** Produced by `prp-gen-documentation-hunter`, autonomously.
**Archon**: NOT AVAILABLE. No Archon call was attempted. All sources below are official
upstream documentation, fetched live on 2026-08-19, or **direct measurement on this machine**
where the docs are silent or where the docs and the running binary disagree.

## Overview

Every external mechanism this remediation depends on is documented below with a URL, the reason
it matters to a specific finding, and a minimal working example. **Four claims in the feature
analysis and the council's own prescriptions are contradicted by measurement** — they are called
out in "Measured contradictions" and each carries the exact command that produced the result.

**Standing rule honoured:** nothing here is from training data. Where no authoritative source
was found, the section says "could not find" rather than filling the gap.

---

## Measured contradictions — read these before planning

Run on this machine, 2026-08-19. Commands are reproducible verbatim.

### 1. S3's prescribed preflight (`tmux display -t "$TARGET"`) CANNOT DETECT A MISSING TARGET

The seat prescribes `tmux display -t "$TARGET"` as the loop-script preflight (finding S3, A10).
**It exits 0 on a target that does not exist.** tmux 3.5:

```
display-message -p -t =sess:@0    -> out="sess:@0.%0"  exit=0   (real target)
display-message -p -t =sess:@99   -> out="sess:@0.%0"  exit=0   (WRONG WINDOW, silently)
display-message -p -t =nosuch:@0  -> out=":."          exit=0   (empty, still exit 0)
display-message -p -t %99         -> out=":."          exit=0
```

A preflight built as prescribed reports success into a void — **the exact defect A10 exists to
fix.** The working preflights, same run:

```
list-panes  -t =sess:@99   -> "can't find window: @99"    exit=1
list-panes  -t =nosuch:@0  -> "can't find session: nosuch" exit=1
has-session -t =sess:@99   -> "can't find window: @99"    exit=1
```

**Prescription for the PRP:** preflight with `tmux has-session -t "=<sess>:<@id>"` or
`tmux list-panes -t ...`, never `display-message`. And the acceptance test must be positive-
controlled against a deliberately bogus target, because the naive form passes.

### 2. `has-session` prefix-matches — a preflight can pass against the wrong session

```
tmux new-session -d -s mysession
has-session -t mysess     exit=0   <-- prefix match, WRONG SESSION
has-session -t =mysess    exit=1
has-session -t =mysession exit=0
```

Confirms the man page: *"If the session name is prefixed with an '=', only an exact match is
accepted (so '=mysess' will only match exactly 'mysess', not 'mysession')."*
**Every `has-session`/`kill-session` in this estate must carry the `=` prefix** — this is also
the anti-goal-8 guard (`tmux kill-server` destroyed the estate three times; a prefix-matching
`kill-session` is the same class).

### 3. SQLite REGEXP is NOT available to `core.py` — S6's trigger will fail closed on ALL inserts

The `sqlite3` **CLI** on this machine has `regexp` (probe: `sqlite3 :memory: "select 'a' regexp
'a';"` → `1`). **Python's `sqlite3` module does not.** A `BEFORE INSERT` trigger using `REGEXP`:

- **CREATE TRIGGER succeeds** (SQLite does not resolve functions at create time)
- then **every INSERT into `items` fails** with `OperationalError: no such function: regexp` —
  including the honest, non-interrogative ones — from any connection that did not register it.

Measured (`python3`, sqlite lib 3.53.4):
```
bare regexp                         -> OperationalError: no such function: regexp
CREATE TRIGGER using regexp         -> OK
INSERT (no regexp fn registered)    -> OperationalError: no such function: regexp
INSERT after conn.create_function   -> IntegrityError: question may not be a hard item  (correct)
INSERT of a non-question hard item  -> OK
```

**Prescription:** either (a) use `GLOB`/`LIKE`, which are built in and need no registration, or
(b) keep `REGEXP` and register `create_function("regexp", 2, ...)` on **every** connection in
`core.py`, with a test that opens a fresh connection and inserts. Option (b) is a landmine: any
future connection that forgets the registration bricks the table. **Option (a) is recommended,
and it also pins the classifier as literal SQL** — which is what assumption 4 of the feature
analysis requires ("pin the exact regex in the migration").

### 4. `.claude/patterns/*.md` — CONFIRMED MISSING (my brief's item 5)

```
ls .../audit-remediation/.claude/patterns/  -> No such file or directory
ls ~/.claude/patterns/                      -> No such file or directory
```
Neither `parallel-subagents.md`, `quality-gates.md` nor `archon-workflow.md` exists in the
worktree or in the user-global harness directory. I did **not** fetch `jonhill90/skills` to look
for them (remote ref, not fetched — could not check). **The parallel-group and quality-gate
conventions must be reconstructed from `docs/plans/prp/estate-remediation/execution/execution-plan.md`,
and the PRP should say so explicitly rather than citing files that do not exist.**

---

## 1. Claude Code hooks — S1, S2, S4, S5

**Official docs**: https://code.claude.com/docs/en/hooks.md (reference)
**Guide**: https://code.claude.com/docs/en/hooks-guide.md
**Relevance: 10/10.** Five of the ten STANDARD rules are hooks and there is no working example
in this estate to copy beyond `.claude/protect-shared-checkout.sh`.

### settings.json schema

Nesting is: `hooks` → event name → **array of matcher groups** → `matcher` + `hooks` array →
handler objects with `type: "command"`.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command", "command": "/abs/path/check_quote_policy.sh", "timeout": 30 }
        ]
      },
      {
        "matcher": "Write|Edit",
        "hooks": [
          { "type": "command", "command": "/abs/path/check_quote_policy.sh" }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [{ "type": "command", "command": "/abs/path/no_code_in_state.sh" }]
      }
    ],
    "Stop": [
      { "hooks": [{ "type": "command", "command": "/abs/path/check_stop_authorized.sh" }] }
    ],
    "SessionStart": [
      { "matcher": "startup", "hooks": [{ "type": "command", "command": "/abs/path/assert_from_main.sh" }] }
    ]
  }
}
```

Handler fields: `type` (required — `command`, `http`, `mcp_tool`, `prompt`, `agent`),
`command`, `timeout` (seconds; default 600, 30s for `UserPromptSubmit`), `if` (permission-rule
syntax pre-filter), `statusMessage`. Top-level sibling: `disableAllHooks`.

### THE EXIT-CODE CONTRACT — the load-bearing part

| Exit | Meaning |
|---|---|
| **0** | Action proceeds. stdout parsed as JSON if it starts with `{`. For `UserPromptSubmit`, `UserPromptExpansion`, `SessionStart`, stdout is **plain text injected into context**, never parsed as JSON. |
| **2** | **BLOCKING** on blockable events. **stderr is the reason** shown to the user/Claude. |
| any other non-zero | **Non-blocking.** Action proceeds. First stderr line surfaces as `Failed with non-blocking status code: <code>`. |

**Exit 2 blocks on**: `PreToolUse` (tool call blocked), `UserPromptSubmit`,
`UserPromptExpansion`, `Stop` / `SubagentStop` (**the stop is prevented; Claude keeps working**),
`TeammateIdle`, `TaskCreated`, `TaskCompleted`, `ConfigChange`, `PostToolBatch`, `PreCompact`,
`Elicitation`, `ElicitationResult`.
**Exit 2 does NOT block on**: `PostToolUse` / `PostToolUseFailure` (tool already ran — stderr is
shown to Claude, nothing is undone), `SessionStart`, `Setup`, `Notification`, `StopFailure`.
**`WorktreeCreate` is the exception: ANY non-zero exit fails creation, not just 2.**

> **Direct consequence for S5.** The seat specifies a **`PostToolUse`** hook to reject
> `~/.local/state/**` writes. `PostToolUse` **cannot prevent the write** — it has already
> happened. If S5 must *prevent* rather than *report*, it has to be a **`PreToolUse`** hook on
> `Write|Edit`. Flag this to Jon as a mechanism correction, not a silent substitution.

### Event list (abridged to what this PRP needs)

`SessionStart`, `SessionEnd`, `Setup`; `UserPromptSubmit`, `UserPromptExpansion`, `Stop`,
`StopFailure`; `PreToolUse`, `PermissionRequest`, `PermissionDenied`, `PostToolUse`,
`PostToolUseFailure`, `PostToolBatch`; `SubagentStart`, `SubagentStop`, `TeammateIdle`,
`TaskCreated`, `TaskCompleted`; `ConfigChange`, `CwdChanged`, `DirectoryAdded`, `FileChanged`,
`InstructionsLoaded`, `WorktreeCreate`, `WorktreeRemove`; `PreCompact`, `PostCompact`;
`Elicitation`, `ElicitationResult`, `Notification`, `MessageDisplay`.

### stdin payloads

Common to all: `session_id`, `prompt_id`, `transcript_path`, `cwd`, `permission_mode`,
`hook_event_name`.

- **`PreToolUse`**: + `tool_name`, `tool_input` (e.g. `{"command": "...", "description": "..."}`
  for Bash; `{"file_path": ..., "content": ...}` for Write), `tool_use_id`.
- **`PostToolUse`**: `PreToolUse` fields + `tool_response` (`{"output": ..., "status_code": ...}`).
- **`Stop`**: + **`stop_hook_active`** (bool).
- **`SessionStart`**: + `source` ∈ `startup | resume | clear | compact | fork`.

### `Stop` — S1's mechanism, and its infinite-loop cap

`stop_hook_active` is `true` when the Stop hook just blocked the previous stop. **Claude Code
overrides a `Stop` hook after 8 consecutive blocks without progress** (raise with
`CLAUDE_CODE_STOP_HOOK_BLOCK_CAP`). `check_stop_authorized.sh` MUST check the field or it will
spin to the cap and then be ignored — which is a guard that looks installed and is not.

```bash
#!/usr/bin/env bash
# check_stop_authorized.sh — S1. Minimal working shape.
set -uo pipefail            # NOTE: deliberately not -e; see the `!` trap below.
INPUT=$(cat)
[ "$(printf '%s' "$INPUT" | /usr/bin/python3 -c \
      'import json,sys; print(json.load(sys.stdin).get("stop_hook_active"))')" = "True" ] && exit 0
if stop_is_authorized; then exit 0; fi
echo "STOP REFUSED: no $STATE/handoff/<session>.blocked naming a Jon-only decision, and no Telegram send in 10m." >&2
exit 2                       # 2 == block the stop. Any other non-zero is advisory and lets it stop.
```

### JSON stdout (exit 0) — the alternative to exit 2

```json
{ "hookSpecificOutput": { "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "Attributed quote contains profanity." } }
```
`permissionDecision` ∈ `allow | deny | ask | defer`; `updatedInput` can rewrite tool args.
`PostToolUse` uses `{"decision":"block","reason":"..."}` (ends the turn; does not undo).
`Stop` uses `{"continue": false, "stopReason": "..."}`.
Universal fields: `continue`, `stopReason`, `systemMessage`, `suppressOutput`.
`SessionStart` on exit 0 emits **plain text**, which is appended to context.

### Matcher syntax

- Empty `""` or omitted, or `"*"` → matches everything.
- Plain names / `|` / `,` lists → **literal, case-sensitive** exact match (`Bash`, `Edit|Write`).
  `bash` ≠ `Bash`.
- Anything containing regex metacharacters → **unanchored JavaScript regex** (`mcp__github__.*`).
- **Matcher meaning is per-event**: tool name for `PreToolUse`/`PostToolUse`; `source` for
  `SessionStart` (`startup|resume|clear|compact|fork`); literal filenames for `FileChanged`.
- **`Stop`, `UserPromptSubmit`, `PostToolBatch`, `TeammateIdle`, `WorktreeCreate` accept NO
  matcher** — omit the key.

S4's shape (`gh (issue|pr) (create|edit|comment)`) is **not a matcher** — the matcher can only
see the tool name. Use `matcher: "Bash"` plus the `if` pre-filter, and do the real command
inspection inside the script against `tool_input.command`:

```json
{ "matcher": "Bash",
  "hooks": [{ "type": "command", "if": "Bash(gh *)", "command": "/abs/check_quote_policy.sh" }] }
```

### Gotchas the docs call out — all four bite this PRP

1. **Multiple hooks on one event run in PARALLEL**; results merge with `deny > defer > ask >
   allow`. A `deny` from one does **not** suppress a sibling's side effects.
2. **`PreToolUse` fires in every permission mode, including `bypassPermissions`** — so S4/S5
   still fire on the 132 `--dangerously-skip-permissions` lanes (F3). Hooks can **tighten**
   but never loosen.
3. **Shell profile output corrupts hook JSON.** A non-interactive shell that `echo`s from a
   profile prepends text and breaks parsing. Guard with `if [[ $- == *i* ]]`.
4. **Workspace trust** is required for project-level hooks; `-p` mode does not grant it. Since
   these four land in **user-global `~/.claude/settings.json`** (feature analysis, inferred
   req. 6), that is the surface — an installer/uninstaller, not a manual edit.

---

## 2. launchd — A8, A9, S2, S3

**launchd.plist(5)**: https://keith.github.io/xcode-man-pages/launchd.plist.5.html
**launchctl(1)**: https://keith.github.io/xcode-man-pages/launchctl.1.html
*(Apple's own man pages, rendered from the Xcode SDK. Apple has no HTML canonical for these;
`man 5 launchd.plist` on the machine is the same text.)*
**Relevance: 10/10.**

### Keys, verbatim

- **`Label`** — *"This required key uniquely identifies the job to `launchd`."*
- **`ProgramArguments`** — *"maps to the second argument of execvp(3) and specifies the argument
  vector"*. **This is what A8's `ProgramArguments[0]` check reads, and what `run-from-main.sh`
  must become element 0 of.**
- **`RunAtLoad`** — *"control whether your job is launched once at the time the job is loaded.
  The default is false."*
- **`StartInterval`** — *"causes the job to be started every N seconds."* **Relative to load,
  not wall-clock.** Correct for the 5-minute `launchctl list` auditor and the session reaper.
- **`StartCalendarInterval`** — *"causes the job to be started every calendar interval as
  specified. Missing arguments are considered to be wildcard."* Dict keys `Minute` (0–59),
  `Hour` (0–23), `Day` (1–31), `Weekday` (*"0 and 7 are Sunday"*), `Month` (1–12). Correct for
  the **daily** auditors (S5, S10). **The wildcard rule is the trap: a dict of only
  `{Hour: 3}` fires 60 times — once a minute for an hour.** Always pin `Minute` too.
- **`KeepAlive`** — *"The default is false and therefore only demand will start the job."*
  Sub-keys: `SuccessfulExit` (*"restarted as long as the program exits with an exit status of
  zero"*), `Crashed`, `PathState`, `OtherJobEnabled`. **`NetworkState` is documented as
  "no longer implemented as it never acted how most users expected" — do not use it.**
  **Do not use `KeepAlive` for the reaper**; a job that refuses via exit 78 under
  `KeepAlive{SuccessfulExit:false}` would be respawned into a hot loop.
- **`ThrottleInterval`** — *"jobs will not be spawned more than once every 10 seconds"* by
  default. A `StartInterval` under 10 is silently throttled.
- **`StandardOutPath` / `StandardErrorPath`** — *"If the file does not exist, it will be created
  with writable permissions."*
- **`EnvironmentVariables`** — the only supported way to fix the LaunchAgent-PATH trap the
  gotcha brief names (`lsof` at `/usr/sbin/lsof` not on the agent PATH).

### `launchctl list` and the 768 encoding — A9

The man page documents three columns (PID, last exit status, Label) and states only:
*"If the number in this column is negative, it represents the negative of the signal which
stopped the job. Thus, '-15' would indicate that the job was terminated with SIGTERM."*

**The man page does NOT explain positive values above 255.** The encoding is the raw
`waitpid(2)` status word. Authority — `<sys/wait.h>` on this machine
(`$(xcrun --show-sdk-path)/usr/include/sys/wait.h`), read directly:

```c
#define _WSTATUS(x)     (_W_INT(x) & 0177)
#define WIFEXITED(x)    (_WSTATUS(x) == 0)
#define WEXITSTATUS(x)  ((_W_INT(x) >> 8) & 0x000000ff)
#define WTERMSIG(x)     (_WSTATUS(x))
```

So `status >> 8` is the exit code. **`768 = 3 << 8` → exit 3** — which matches the feature
analysis exactly (`director-loop.sh` exits 3 at line 110). Parser for the A9 sweep:

```bash
# launchctl list emits: PID  Status  Label   (tab-separated, one header line)
launchctl list | awk 'NR>1 && $2 != "0" && $2 != "-" {
   s=$2+0
   if (s < 0)          printf "%s: killed by signal %d\n", $3, -s
   else if (s % 256)   printf "%s: raw status %d (signalled)\n", $3, s
   else                printf "%s: exit %d (raw %d)\n", $3, int(s/256), s
}'
```
**Positive-control this parser** (inferred req. 5): plant a plist that `exit 3`s and assert the
sweep reports it, before trusting a clean sweep.

`WEXITSTATUS` masks to 8 bits, so **exit 78 (`EX_CONFIG`, the deliberate refusal code for S2)
appears as raw `19968` (78 × 256)** and must not be mistaken for a signal.

### Reloading a changed plist — correctly

The man page's *"Recommended alternative subcommands: bootstrap | bootout | enable | disable"*
supersedes `load`/`unload`. Domain targets: `gui/<uid>`, `user/<uid>`, `system`.

```bash
launchctl bootout  gui/$UID/com.jonhill.director-loop 2>/dev/null || true
launchctl bootstrap gui/$UID ~/Library/LaunchAgents/com.jonhill.director-loop.plist
launchctl kickstart -k gui/$UID/com.jonhill.director-loop   # -k kills+restarts; run once now
launchctl print gui/$UID/com.jonhill.director-loop | grep -E 'state|last exit|path'
```

**Trap:** editing the plist in place without `bootout`/`bootstrap` leaves the OLD
`ProgramArguments` live. A8's acceptance ("every `ProgramArguments[0]` resolves under
`$SUPERVISOR_LIVE`") must read **`launchctl print`**, not the file on disk — otherwise the check
verifies the intention and not the running job. This is the "verify the instrument" rule applied
to launchd.

---

## 3. tmux — A1, A2, A10, A12, and invariant 4/5

**Official**: https://man.openbsd.org/tmux.1 (OpenBSD hosts the canonical tmux man page).
tmux on this machine: **3.5**. **Relevance: 10/10.**

### Server / socket model — the test-isolation mechanism

> *"In tmux, a session is displayed on screen by a client and all sessions are managed by a
> single server. The server and each client are separate processes which communicate through a
> socket in /tmp."*
> *"tmux stores the server socket in a directory under `TMUX_TMPDIR` or /tmp if it is unset. The
> default socket is named default. This option allows a different socket name to be specified,
> allowing several independent tmux servers to be run."*

`-L <name>` names a socket inside that directory; `-S <path>` gives an absolute socket path.
**This is the documented basis for AGENTS.md invariant 4 and for A12** — a test that exports
`TMUX_TMPDIR` to a `mktemp -d` **and** passes `-L`, and asserts both, cannot reach production.
Working shape (this is the exact harness used for every measurement in this file):

```bash
export TMUX_TMPDIR=$(mktemp -d /tmp/xxx.XXXXXX)
tmux -L testsock new-session -d -s mysession
...
tmux -L testsock kill-session -t "=mysession"   # exact match ONLY
rm -rf "$TMUX_TMPDIR"                            # never `tmux kill-server`
```

### Why `window_id` (`@N`) does not survive a server restart — A10

> *"Sessions, window and panes are each numbered with a unique ID; session IDs are prefixed with
> a '$', windows with a '@', and panes with a '%'. These are unique and are unchanged for the
> life of the session, window or pane **in the tmux server**."*

The documented uniqueness scope is **the server process**. A new server allocates from `@0`
again — so a stored `@35` is either dangling or, worse, silently now points at somebody else's
window. This makes invariant 5 (address by `@id`, never index) **necessary and insufficient**,
exactly as the gotcha brief says. **Any target persisted as `@N` across a restart must be
re-resolved by name, and preflighted (see contradiction 1).**

### `has-session` — the correct preflight

> *"has-session [-t target-session]: Report an error and exit with 1 if the specified session
> does not exist. If it does exist, exit with 0."*
> *"If the session name is prefixed with an '=', only an exact match is accepted (so '=mysess'
> will only match exactly 'mysess', not 'mysession')."*

Matching order without `=`: session ID, exact name, name prefix, glob pattern.
**Measured**: `has-session -t "=sess:@99"` correctly exits 1 with `can't find window: @99` — so
`has-session` (unlike `display-message`) **does** validate the window component. Use it.

### Creating a session that does not exist — A1's actuator

```
new-session [-AdDEPX] [-c start-directory] [-e environment] [-F format]
            [-n window-name] [-s session-name] [-t group-name] [shell-command ...]
```
`-d` detached (mandatory for an unattended launchd job — there is no terminal), `-A` attaches to
an existing session of that name instead of erroring, making the reaper **idempotent**:

```bash
tmux new-session -A -d -s "$SESSION"    # create if absent, no-op if present
```
Combined with the set-difference in A2, the whole reaper body is:
```bash
tmux list-sessions -F '#{session_name}' > "$tmp/live"
comm -23 <(sqlite3 "$LEDGER" 'select session from sessions order by 1') <(sort "$tmp/live") |
  while read -r s; do tmux new-session -A -d -s "$s" || exit 1; done
```

`list-sessions` synopsis: `list-sessions [-r] [-F format] [-f filter] [-O sort-order]`.
`kill-session [-aCg] [-f filter] [-t target-session]` — **always `-t "=name"`.**

---

## 4. SQLite — S6, S8, C1–C9, and the ledger access constraint

**CREATE TRIGGER**: https://sqlite.org/lang_createtrigger.html
**REGEXP / LIKE / GLOB**: https://sqlite.org/lang_expr.html
**ALTER TABLE**: https://sqlite.org/lang_altertable.html
**URI filenames**: https://sqlite.org/uri.html
Library on this machine: CLI 3.51.0 (Apple), Python module 3.53.4. **Relevance: 10/10.**

### `BEFORE INSERT` + `RAISE(ABORT)` — S6's trigger

Grammar: `CREATE TRIGGER name BEFORE INSERT ON table FOR EACH ROW [WHEN expr] BEGIN stmts END`.
Docs: *"SQLite supports only FOR EACH ROW triggers, not FOR EACH STATEMENT triggers."*
*"If a WHEN clause is supplied, the SQL statements specified are only executed if the WHEN clause
is true."* In a BEFORE INSERT trigger, `NEW.column` is valid; `OLD` is not.

RAISE forms:
- **`RAISE(ABORT, msg)`** — *"performs ON CONFLICT abort processing and terminates the query with
  SQLITE_CONSTRAINT"*. Backs out the current statement; the enclosing transaction survives.
  **This is the right one for S6.** Surfaces in Python as `sqlite3.IntegrityError` with the
  message — measured.
- `RAISE(FAIL, msg)` — similar, but prior changes of the same statement are kept.
- `RAISE(ROLLBACK, msg)` — rolls the whole transaction back. **Too violent for an ingest loop.**
- `RAISE(IGNORE)` — *"the remainder of the current trigger program, the statement that caused the
  trigger program to execute and any subsequent trigger programs ... are abandoned. No database
  changes are rolled back."* **Silently drops the row — precisely the failure mode this audit is
  about. Do not use.**

Working example, **measured green and measured red** on this machine (GLOB form — no function
registration needed, and the classifier is pinned literally in the schema as assumption 4 requires):

```sql
CREATE TRIGGER items_no_hard_from_question
BEFORE INSERT ON items FOR EACH ROW
WHEN NEW.weight = 'hard'
 AND NEW.kind IN ('directive','parameter')
 AND ( NEW.source_text GLOB '*?'                       -- strict floor: ends in '?'
    OR lower(NEW.source_text) GLOB 'what *'            -- broad set, enumerated explicitly
    OR lower(NEW.source_text) GLOB 'why *'
    OR lower(NEW.source_text) GLOB 'how *'
    OR lower(NEW.source_text) GLOB 'should *'
    OR lower(NEW.source_text) GLOB 'can *'
    OR lower(NEW.source_text) GLOB 'is *'  )
BEGIN
  SELECT RAISE(ABORT, 'a question may not be recorded as a hard item');
END;
```

> **GLOB vs LIKE vs REGEXP, from the docs.** GLOB *"uses Unix file globbing syntax and is always
> case-sensitive"* (hence `lower(...)`); `?` in GLOB is a single-char wildcard, so a **literal**
> `?` must be written `[?]` if you mean the character — `'*?'` above matches "any string then any
> one char", i.e. non-empty, **which is a bug**. Use `'*[?]'`. LIKE (`'%?'`) has no such
> ambiguity and is case-insensitive for ASCII by default. **Pin whichever you choose in the
> migration and publish its count at landing** — the 209/305/581 disagreement is a disagreement
> about this literal.

**REGEXP — the trap, verbatim from the docs:** *"No regexp() user function is defined by default
and so use of the REGEXP operator will normally result in an error message."* `X REGEXP Y`
desugars to `regexp(Y, X)` — **arguments reversed**. See measured contradiction 3.

**Precedent in-tree:** `one_open_pull_per_source_ref` is already a `BEFORE INSERT ... RAISE(ABORT)`
trigger — copy its shape.

### Adding a NOT NULL column safely — the `prompts.provenance` change

From the ALTER TABLE docs, the rules on `ADD COLUMN`:
- *"The column may not have a PRIMARY KEY or UNIQUE constraint."*
- *"The column may not have a default value of CURRENT_TIME, CURRENT_DATE, CURRENT_TIMESTAMP, or
  an expression in parentheses."*
- **NOT NULL requires a non-NULL DEFAULT.**
- CHECK constraints on an added column *"are tested against all existing rows; the operation fails
  if any constraint violation occurs."*
- Foreign keys: if `REFERENCES` is added, the column must default to NULL.

So the feature analysis's `provenance TEXT NOT NULL CHECK (provenance IN ('human','agent'))`
**cannot be added as written** — no default. Two correct paths:

```sql
-- Path A: one statement, needs a default that is itself honest.
ALTER TABLE prompts ADD COLUMN provenance TEXT NOT NULL DEFAULT 'unknown'
  CHECK (provenance IN ('human','agent','unknown'));
-- then backfill from promptSource, then (optionally) tighten via the 12-step rebuild.

-- Path B: nullable now, tighten later via the documented 12-step table rebuild.
ALTER TABLE prompts ADD COLUMN provenance TEXT CHECK (provenance IN ('human','agent'));
```
**Path A's `'unknown'` is the honest option** and matches this estate's own rule against
instruments that cannot distinguish "no data" from "clean". Widening the CHECK to admit
`'unknown'` is what makes the constraint enforceable at all.

For any change ADD COLUMN cannot express, the docs give a **12-step procedure**: disable FKs →
BEGIN → record existing indexes/triggers/views → `CREATE TABLE new_x` → `INSERT INTO new_x SELECT
... FROM x` → `DROP TABLE x` → `ALTER TABLE new_x RENAME TO x` → recreate indexes/triggers/views →
`PRAGMA foreign_key_check` → COMMIT → re-enable FKs. **Do not reorder** — the docs warn the
sequence matters when `legacy_alter_table` / `foreign_keys` interact.

### `mode=ro` vs `immutable=1` — the ledger read constraint

- `mode=ro | rw | rwc | memory` — read-only / read-write / read-write-create / in-memory.
- `immutable=1` — *"signals that the underlying database file is on read-only media and cannot be
  modified, even by elevated processes."* SQLite then **skips file locking and change detection.**
  The docs warn: *"If this query parameter ... asserts that a database file is immutable and that
  file changes anyhow, then SQLite might return incorrect query results and/or SQLITE_CORRUPT
  errors."*

**This settles the two-seats-disagreed problem.** `immutable=1` is what let seat-raw-2 read a
`journal_mode=delete` file; it is **actively unsafe** on the WAL-mode file seat-raw-3 found,
because a live writer *is* changing it — silently wrong results, which is worse than an error.
**Prescription:** never hardcode the access mode. Check first, and prefer a copy:

```bash
mode=$(sqlite3 "file:$LEDGER?mode=ro" 'pragma journal_mode;')   # 'delete' | 'wal'
if [ "$mode" = wal ]; then
  sqlite3 "file:$LEDGER?mode=ro" ".backup '$tmp/ledger.sqlite3'"   # consistent snapshot, safe under a writer
  LEDGER="$tmp/ledger.sqlite3"
fi
```
`.backup` is the correct snapshot verb — a bare `cp` of a WAL database without its `-wal` sidecar
is a torn read.
**Note `mode=ro` alone cannot open a WAL database it must create a `-shm` for** — that is the
concrete obstacle seat-raw-3 hit, and the reason `.backup` (or `immutable=1`, with the risk
above) is needed rather than a plain read-only open.

---

## 5. GitHub Actions — E1, and every new CI gate

**Workflow syntax**: https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
**Required status checks**: https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks
**Relevance: 9/10.**

### Job-name collision — E1's root

The docs state `job_id` must be *"a string that is unique to the `jobs` object"* — **uniqueness
is scoped to one workflow file only.** The docs **do not** state that check-run names must be
unique across workflows; they state the consequence:

> *"If a check and a commit status have the same name, both must pass when that name is required."*

**So `fixpass-evidence.yml:gate` and `ui-evidence.yml:gate` are two distinct check runs sharing
one name, and GitHub's branch protection UI cannot distinguish them.** This is a documented,
long-standing limitation, corroborated by GitHub's own community discussion
[#161714 "required status checks: not possible to select two jobs with same name in different
workflows"](https://github.com/orgs/community/discussions/161714) — *cited as corroboration of
the limitation's existence, not as authority.*

**Could not find**: an official first-party workflow-linter action that enforces cross-workflow
job-name uniqueness. **Recommendation: write it as a custom test** (it is ~15 lines of stdlib
Python over `.github/workflows/*.yml`, needs no dependency, and lands in the existing
`unittest discover` suite). That also answers the brief's question 4 directly.

Note `jobs.<job_id>.name` overrides the displayed name, so **renaming one `gate:` is a one-line
fix**; the lint test is the recurrence guard.

### `bash -eo pipefail` and why `! cmd` never aborts — the 5½-month-dead-guard trap

The default shell for a `run:` block on non-Windows runners is bash. When `shell: bash` is set
explicitly the docs give the exact command: **`bash --noprofile --norc -eo pipefail {0}`**.

The GNU Bash manual, verbatim (https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html):

> **`-e`** *"Exit immediately if a pipeline returns a non-zero status. The shell does not exit if
> the command that fails is part of the command list immediately following a `while` or `until`
> reserved word, part of the test in an `if` statement, part of any command executed in a `&&` or
> `||` list except the command following the final `&&` or `||`, any command in a pipeline but the
> last (subject to the state of the `pipefail` shell option), **or if the command's return status
> is being inverted with `!`.**"*

> **`-o pipefail`** *"the return value of a pipeline is the value of the last (rightmost) command
> to exit with a non-zero status, or zero if all commands in the pipeline exit successfully."*

Measured on this machine, with the runner's exact invocation:

```
bash --noprofile --norc -eo pipefail -c '! false | grep zzz; echo REACHED; exit 0'
  -> REACHED          step exit=0     # the !-negated failure did NOT abort
bash --noprofile --norc -eo pipefail -c 'false | grep -q zzz; echo NOT-REACHED'
  -> (no output)      step exit=1     # the un-negated one DID
```

**This is the sibling repo's dead guard reproduced in three lines**, and it is the template for
inferred requirement 1's mutation evidence. **`if` is the same trap** — a failing command inside
an `if` test also never aborts. The only correct shape for a bash CI gate:

```bash
if grep -qn 'FORBIDDEN' scripts/deploy.sh; then
  echo "::error::forbidden pattern present"
  exit 1                       # explicit exit — never `! grep ...`, never a bare guard in `if`
fi
```
**Acceptance for every new bash gate: revert the fix, re-run, observe red, commit the run URL.**
A gate not shown going red has not been shown to be a gate.

**Could not find** the POSIX `set -e` text at a fetchable pubs.opengroup.org URL (the
`V3_chap02.html` page truncated before the `set` built-in; `utilities/set.html` 404s). The Bash
manual above is the authority that actually governs `bash -eo pipefail`, so the gap is not
material — but stated rather than papered over.

---

## 6. git — S2 and S10

**merge-base**: https://git-scm.com/docs/git-merge-base
**worktree**: https://git-scm.com/docs/git-worktree
**Relevance: 9/10.**

### `merge-base --is-ancestor` — S2's `run-from-main.sh`

> *"Check if the first `<commit>` is an ancestor of the second `<commit>`, and exit with status 0
> if true, or with status 1 if not. **Errors are signaled by a non-zero status that is not 1.**"*

Measured: `HEAD` vs `HEAD` → **0** (a commit **is** its own ancestor — the docs do not state this;
this is measurement, and it is what makes "exactly on main" pass). `HEAD` vs `HEAD~1` → **1**.
Bogus SHA → **128**.

**The three-way distinction is load-bearing and the naive wrapper loses it:**

```bash
#!/usr/bin/env bash
# run-from-main.sh — S2. Refuse to execute from a ref that is not an ancestor of origin/main.
set -uo pipefail                      # NOT -e: we must read $? ourselves.
git -C "$REPO" fetch --quiet origin main || { notify "run-from-main: fetch failed"; exit 78; }
git -C "$REPO" merge-base --is-ancestor HEAD origin/main
rc=$?
case $rc in
  0) exec "$@" ;;                                        # ancestor: proceed
  1) notify "REFUSED: $(git -C "$REPO" rev-parse --short HEAD) on $(git -C "$REPO" branch --show-current) is not an ancestor of origin/main. Nothing ran. Merge it or run from live/."
     exit 78 ;;                                          # EX_CONFIG — deliberate refusal
  *) notify "REFUSED: merge-base errored ($rc) in $REPO. Nothing ran."
     exit 78 ;;                                          # error != 'not an ancestor'
esac
```
Two things this shape gets right that a bare `if ! git merge-base ...` does not: **128 is not
conflated with 1**, and the refusal **names what does act instead** (seat 4's proposed 11th
invariant). Exit 78 shows in `launchctl list` as raw **19968**; the A9 parser above decodes it.

### `git worktree prune` — S10, against 346 worktrees

> *"Remove worktree information in `$GIT_DIR/worktrees` for worktrees whose working trees are
> missing."*
> `-n, --dry-run`: *"do not remove anything; just report what it would remove."*
> `-v, --verbose`: *"report all removals."*
> `--expire <time>`: *"only prune missing worktrees if older than `<time>`."*

Default expiry comes from `gc.worktreePruneExpire`. **`prune` only removes administrative files
for worktrees whose directory is already gone — it never deletes a working tree**, so it is safe
to run unconditionally, as S10 specifies. `git worktree lock [--reason ...]` exempts a worktree
from pruning; `git worktree repair` is the correct fix for a *moved* worktree — **pruning a moved
worktree is the wrong verb and loses the link.**

The countable, positive-controllable form for the S10 auditor:

```bash
git worktree list --porcelain -z | tr '\0' '\n' | grep -c '^prunable '   # how many are stale
git worktree prune -n -v                                                 # dry-run first (the
                                                                         # dry-run discipline
                                                                         # that caught A6)
git worktree prune -v
git worktree list --porcelain -z | tr '\0' '\n' | grep -c '^worktree '   # ceiling check (default 10)
git branch --format='%(refname:short)' | grep -vx main | wc -l           # ceiling check (default 25)
```
`-z` is required for safe parsing when paths contain newlines. **Thresholds 25/10 are the
council's defaults, not Jon's** — parameterise them.

---

## Documentation gaps — stated, not filled

1. **`.claude/patterns/{parallel-subagents,quality-gates,archon-workflow}.md`** — confirmed absent
   from both the worktree and `~/.claude/`. I did **not** fetch `jonhill90/skills@5688dfe1`
   (remote ref; could not check). Reconstruct from the in-tree execution plan and say so.
2. **A first-party GitHub Actions linter for cross-workflow job-name uniqueness** — could not
   find. Ship a custom stdlib test.
3. **POSIX's own `set -e` text at a fetchable URL** — could not fetch (page truncated / 404).
   The Bash manual governs `bash -eo pipefail` and is quoted above.
4. **Apple HTML canonical for `launchd.plist(5)` / `launchctl(1)`** — Apple publishes no current
   HTML version. The Xcode-SDK-rendered mirror is used; it is byte-identical to `man 5
   launchd.plist` on this machine, which is the real authority. **Verify against the local man
   page rather than the mirror if it matters.**
5. **`launchctl list`'s positive status encoding above 255** — not in the man page. Established
   from `<sys/wait.h>` on this machine instead, and cited as such.
6. **tmux's uniqueness scope for `@N` across a server restart** — the man page bounds it to "the
   life of the ... window **in the tmux server**", which implies but does not state that a new
   server reuses IDs. Not measured here (would require restarting a server). **Treat A10 as
   sound and label this specific inference as an inference.**

---

## Quick reference URLs

```yaml
Claude Code hooks:
  reference:        https://code.claude.com/docs/en/hooks.md
  guide:            https://code.claude.com/docs/en/hooks-guide.md
launchd:
  launchd.plist(5): https://keith.github.io/xcode-man-pages/launchd.plist.5.html
  launchctl(1):     https://keith.github.io/xcode-man-pages/launchctl.1.html
  status encoding:  $(xcrun --show-sdk-path)/usr/include/sys/wait.h
tmux:
  tmux(1):          https://man.openbsd.org/tmux.1
SQLite:
  CREATE TRIGGER:   https://sqlite.org/lang_createtrigger.html
  REGEXP/GLOB/LIKE: https://sqlite.org/lang_expr.html
  ALTER TABLE:      https://sqlite.org/lang_altertable.html
  URI filenames:    https://sqlite.org/uri.html
GitHub Actions:
  workflow syntax:  https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax
  required checks:  https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/collaborating-on-repositories-with-code-quality-features/troubleshooting-required-status-checks
bash:
  set builtin:      https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html
git:
  merge-base:       https://git-scm.com/docs/git-merge-base
  worktree:         https://git-scm.com/docs/git-worktree
```

---

## Recommendations for PRP assembly

1. **Lead the PRP's "Known Gotchas" with the four measured contradictions.** Two of them
   (`display-message` preflight, `PostToolUse` for S5) mean a prescribed mechanism does not do
   what the council said it does. An implementer who follows the seat text literally ships a
   guard that is green and dead — the exact history this PRP exists to end.
2. **Every bash gate gets the `if ... exit 1` shape**, never `! cmd`, never a bare guard inside
   an `if` test, with the three-line reproduction above as its mutation evidence.
3. **Every "zero" assertion gets a positive control**: the bogus tmux target, the planted
   `exit 3` plist, the synthetic hard-from-question insert, the deliberately-renamed duplicate
   job name.
4. **Pin S6's classifier as literal SQL (GLOB/LIKE), not REGEXP**, and publish its count at
   landing. `'*?'` in GLOB matches "any non-empty string" — write `'*[?]'`.
5. **`provenance TEXT NOT NULL CHECK (...)` cannot be added by ALTER TABLE as specified.** Use
   the `DEFAULT 'unknown'` form with a widened CHECK, or the 12-step rebuild.
6. **Check the ledger's journal mode before opening it**, and snapshot with `.backup`, not `cp`
   and not `immutable=1`, when it is WAL.
7. **Read `launchctl print`, not the plist on disk**, for A8's acceptance.

## Archon ingestion candidates

- https://code.claude.com/docs/en/hooks.md — the exit-code contract and per-event blockability
  table is the single most reusable artifact here.
- https://sqlite.org/lang_altertable.html — the ADD COLUMN restrictions and 12-step procedure.
- https://www.gnu.org/software/bash/manual/html_node/The-Set-Builtin.html — the `!` exemption
  clause, which has now cost this estate's sibling 5½ months.
