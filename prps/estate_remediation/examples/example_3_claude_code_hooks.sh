#!/usr/bin/env bash
# Source: (1) THIS repo: .claude/settings.json + .claude/protect-shared-checkout.sh  [PreToolUse/Bash]
#         (2) /Users/jon/source/repos/skills-research/Hill90/scripts/hooks/stop-gate.sh  [Stop]
#         (3) /Users/jon/source/repos/skills-research/Hill90/.claude/settings.json  [4 events registered]
# Pattern: Claude Code hooks — settings.json schema, stdin payload parsing, the
#          exit-code contract, and the fail-open vs fail-closed decision.
# Extracted: 2026-08-19
# Relevance: 10/10 — five of the ten STANDARD rules (S1, S2, S4, S5) are hooks.
#
# ############################################################################
# CORRECTION TO THE BRIEF, STATED FIRST BECAUSE IT CHANGES THE PLAN
# ############################################################################
# The brief anticipated that NO hook example might exist on this machine, and
# asked for a NO_EXAMPLE_EXISTS.md if so. That file is not needed. Working
# hooks exist in three places, and one of them is a `Stop` hook — the exact
# event S1 needs and the one the feature analysis says has "no working example
# in this estate to copy from".
#
# What IS true, and stays true (verified 2026-08-19):
#   * `~/.claude/settings.json` has NO `hooks` key. Its keys are exactly:
#     alwaysThinkingEnabled, effortLevel, enabledPlugins,
#     skipDangerousModePermissionPrompt, theme, tui, voiceEnabled.
#     So nothing is enforced GLOBALLY. That is finding-level and unchanged.
#   * This repo's `.claude/settings.json` has exactly one hook (PreToolUse/Bash).
#   * `skills-research/Hill90/.claude/settings.json` registers FOUR events —
#     PreCompact, PostToolUse (Edit|Write), PreToolUse (Bash), and **Stop** —
#     with three scripts under `scripts/hooks/`. Copy that file's shape.
#   * agent-dotfiles and vibes-v3 both register PreCompact + PostToolUse.
#
# The implementer should copy `stop-gate.sh` structurally, NOT declare a gap.

# ############################################################################
# PART 1 — THE settings.json SCHEMA
# Verbatim from skills-research/Hill90/.claude/settings.json. This is the
# widest real example on the machine and covers every event this PRP needs
# except SessionStart.
# ############################################################################
: <<'SETTINGS_JSON'
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          { "type": "command",
            "command": "bash $CLAUDE_PROJECT_DIR/scripts/hooks/block-local-deploy.sh",
            "timeout": 10 }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Edit|Write",
        "hooks": [
          { "type": "command",
            "command": "bash $CLAUDE_PROJECT_DIR/scripts/hooks/shellcheck-on-edit.sh",
            "timeout": 30 }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          { "type": "command",
            "command": "bash $CLAUDE_PROJECT_DIR/scripts/hooks/stop-gate.sh",
            "timeout": 30 }
        ]
      }
    ],
    "PreCompact": [
      {
        "hooks": [
          { "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/backup-transcript.sh",
            "timeout": 10,
            "statusMessage": "Backing up transcript..." }
        ]
      }
    ]
  }
}
SETTINGS_JSON
#
# Points the implementer must not miss:
#   * `matcher` is a REGEX alternation over tool names ("Edit|Write", "Bash").
#     `Stop` and `PreCompact` entries carry NO matcher — they are not per-tool.
#   * `$CLAUDE_PROJECT_DIR` expands to the project root. In THIS repo's
#     settings.json the command is the bare relative path
#     `.claude/protect-shared-checkout.sh` — both work; prefer the explicit
#     variable, because the four hooks in this PRP install into
#     `~/.claude/settings.json`, where there is no project root to be relative to.
#     **Hooks in the user-global file must use ABSOLUTE paths.**
#   * `timeout` is seconds. Set it. S1's check shells out to a Telegram log read.
#   * Multiple matcher-blocks per event are allowed (vibes-v3 has two under
#     PostToolUse). So four new hooks can be added WITHOUT disturbing anything —
#     but `~/.claude/settings.json` is still a single shared file, so its edits
#     cannot be parallelised across execution units.

# ############################################################################
# PART 2 — A BLOCKING PreToolUse HOOK.
# Verbatim from THIS repo: .claude/protect-shared-checkout.sh
# This is the shape S4 (profanity/quote guard) and S5 (no-code-in-state) copy.
# ############################################################################
#
# PreToolUse guard: refuse a branch switch inside the SHARED checkout.
#
# WHY. On 2026-08-17 the watchdog edited notify.sh in the shared checkout,
# committed to a branch, and pushed. Something then switched the shared checkout
# back to main and the edit vanished from the working tree mid-session. The
# watchdog had told Jon "telegram works" -- it had worked, and then silently
# stopped, because the file under it changed.
#
# It blocks the SWITCH, not the work: commit, push, add, status, log, diff all
# pass. If you need a different branch, make a worktree.
set -uo pipefail
SHARED="${SUPERVISOR_SHARED_CHECKOUT:-$HOME/source/repos/Personal/agent-supervisor}"

# THE PAYLOAD ARRIVES ON STDIN AS JSON. Parsed with python3 here (stdlib only,
# no jq dependency). stop-gate.sh uses `jq`; both are in use in this estate.
# Prefer python3 for anything installed into ~/.claude — jq is not guaranteed.
payload=$(cat 2>/dev/null || true)
cmd=$(printf '%s' "$payload" | python3 -c 'import json,sys
try: print((json.load(sys.stdin).get("tool_input") or {}).get("command",""))
except Exception: print("")' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# NARROW FAST. Only care about branch-changing git verbs; everything else is
# an immediate exit 0. A hook that runs real logic on every Bash call is a tax
# on every turn.
printf '%s' "$cmd" | grep -qE 'git +(checkout|switch)( |$)' || exit 0
# `git checkout -- <path>` and `checkout <file>` restore files; they do not move HEAD.
printf '%s' "$cmd" | grep -qE 'git +checkout +--( |$)' && exit 0

here=$(pwd -P 2>/dev/null)
target="$here"
if printf '%s' "$cmd" | grep -qE 'cd +[^&;|]*agent-supervisor'; then target="$SHARED"; fi
[ "$target" = "$(cd "$SHARED" 2>/dev/null && pwd -P)" ] || exit 0

# THE REFUSAL. To STDERR, naming the offending command, the incident, AND the
# actuator ("use a worktree instead" + the literal command). Seat 4's 11th
# invariant, in a hook.
cat >&2 <<MSG
BLOCKED: branch switch inside the SHARED checkout ($SHARED).

  $cmd

Lanes isolate with worktrees (362 exist). The shared checkout has no owner, so
switching it yanks the working tree out from under anything else using it --
that is how a verified notify.sh fix silently reverted on 2026-08-17.

Use a worktree instead:
  git worktree add /tmp/<name> -b <branch>
MSG
exit 2
#
# ^^^ THE EXIT-CODE CONTRACT, as this estate uses it:
#     exit 0  -> allow. stdout is NOT shown to the model.
#     exit 2  -> BLOCK. stderr IS fed back to the model as the reason.
#     other   -> non-blocking error; the tool call proceeds.
#     A hook that writes a reason and exits 0 has done nothing. This is the
#     `!`-negated-pipeline class of defect in a new costume: verify by
#     REVERTING the fix and watching the block disappear.

# ############################################################################
# PART 3 — A `Stop` HOOK. Verbatim structure from
# skills-research/Hill90/scripts/hooks/stop-gate.sh (99 lines).
# S1 ("the agent may not go quiet; stopping is an event that must be
# justified") is this file with a different rule set.
# ############################################################################
: <<'STOP_GATE'
#!/usr/bin/env bash
set -euo pipefail

# Stop hook: verify that required verification commands ran during the session.
# Input: JSON via stdin with transcript_path
# Output: exit 2 (blocking) if required checks are missing, exit 0 otherwise

INPUT=$(cat)
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // empty')
CWD=$(echo "$INPUT" | jq -r '.cwd // empty')

# --- FOUR FAIL-OPEN GATES. Read these as a design decision, not boilerplate.
# Each one asks "can this hook SEE?" before it judges. An unreadable transcript
# is blindness, not compliance -- so it declines to judge and SAYS SO through
# `systemMessage`, rather than silently passing. This is the estate's
# "verify the instrument before you believe the verdict" rule, in a hook.
if [[ -z "$TRANSCRIPT_PATH" ]]; then
  jq -n '{systemMessage: "stop-gate: no transcript path provided — skipping verification check"}'
  exit 0
fi
if [[ ! -f "$TRANSCRIPT_PATH" ]]; then
  jq -n '{systemMessage: "stop-gate: transcript file not found — skipping verification check"}'
  exit 0
fi
if [[ ! -s "$TRANSCRIPT_PATH" ]]; then
  jq -n '{systemMessage: "stop-gate: transcript file is empty — skipping verification check"}'
  exit 0
fi
TRANSCRIPT=$(cat "$TRANSCRIPT_PATH" 2>/dev/null) || {
  jq -n '{systemMessage: "stop-gate: could not read transcript — skipping verification check"}'
  exit 0
}

# --- What the session actually did, read off the transcript.
MODIFIED_FILES=$(echo "$TRANSCRIPT" | jq -r '
  select(.tool_name == "Edit" or .tool_name == "Write") |
  .tool_input.file_path // empty
' 2>/dev/null || true)

MISSING_CHECKS=()
transcript_has_command() { echo "$TRANSCRIPT" | grep -qE "$1" 2>/dev/null; }
has_modified_path()      { echo "$MODIFIED_FILES" | grep -qE "$1" 2>/dev/null; }

# --- The rules. Each is "if you touched X, you must have run Y".
if has_modified_path 'scripts/.*\.sh'; then
  transcript_has_command 'shellcheck' || MISSING_CHECKS+=("shellcheck (modified shell scripts in scripts/)")
fi
if has_modified_path 'tests/scripts/'; then
  transcript_has_command 'bats' || MISSING_CHECKS+=("bats (modified test files in tests/scripts/)")
fi

# --- The block. Names every missing check, not just the first.
if [[ ${#MISSING_CHECKS[@]} -gt 0 ]]; then
  MISSING_LIST=$(printf '  - %s\n' "${MISSING_CHECKS[@]}")
  echo "stop-gate: required verification commands were not found in this session:" >&2
  echo "$MISSING_LIST" >&2
  echo "Please run these checks before finishing." >&2
  exit 2
fi
exit 0
STOP_GATE
#
# WHAT S1 CHANGES about this template:
#   * The rule is not "did you run a check" but "are you ALLOWED to stop":
#     block unless a `$STATE/handoff/<session>.blocked` file names a Jon-only
#     decision AND a Telegram send is logged in the last 10 minutes, OR zero
#     dispatchable issues remain.
#   * FAIL-OPEN vs FAIL-CLOSED is the real design call and it must be argued
#     explicitly in the PRP. stop-gate.sh fails OPEN on a blind instrument,
#     which is right for a "did you run the tests" nudge. S1 exists because
#     the agent went quiet 52 times in 9 days — but a Stop hook that fails
#     CLOSED on an unreadable transcript can wedge every session on the
#     machine, since `~/.claude/settings.json` is global. Recommendation:
#     fail open on blindness, fail closed on a readable transcript that shows
#     an unjustified stop, and PAGE on the fail-open path so blindness is
#     never silent (that is exactly what D3's NOTIFY-PATH-STALE got wrong).
#
# ############################################################################
# PART 4 — INSTALLING INTO ~/.claude/settings.json  (inferred requirement #6)
# ############################################################################
# That file is user-global, unversioned, shared with every other project on
# this machine, and today has no `hooks` key at all. Editing it by hand is an
# outward-facing change to Jon's environment. The deliverable is an INSTALLER
# and an UNINSTALLER, and the installer must:
#   1. back the file up, timestamped, before writing;
#   2. MERGE — read the JSON, add under `hooks`, write back. Never overwrite:
#      the file carries seven live keys that are none of this PRP's business;
#   3. use python3's `json` module, not `sed`/`jq` string surgery;
#   4. be idempotent — re-running adds nothing a second time;
#   5. use ABSOLUTE paths in every `command` (no $CLAUDE_PROJECT_DIR);
#   6. verify by re-reading the file and asserting the hooks are present,
#      then by triggering one and observing the block.
