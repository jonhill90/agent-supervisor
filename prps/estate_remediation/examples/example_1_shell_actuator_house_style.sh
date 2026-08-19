#!/usr/bin/env bash
# Source: scripts/supervisor/bootstrap-session.sh (mainly), with the lock and
#         logging idiom from scripts/supervisor/poller-recover.sh:140-180
# Lines: bootstrap-session.sh 1-62, 140-200, 240-290; poller-recover.sh 39-62, 140-175
# Pattern: this estate's house style for a shell ACTUATOR — the header that
#          argues for its own existence, env-driven config, arg parsing,
#          validate-before-you-touch-anything, --dry-run, mkdir locking,
#          a refusal that NAMES what to do instead, and meaningful exit codes.
# Extracted: 2026-08-19 from commit 6b7c4435
# Relevance: 10/10 — the session reaper (A1/A2) is a near-sibling of this file,
#            and `bootstrap-session.sh` is the thing the reaper will invoke.
#
# READ THE HEADER COMMENTS AS PART OF THE PATTERN. Every load-bearing script in
# this estate opens with WHY it exists, WHAT it refuses to do, and the incident
# that taught it. A new actuator written without that header will not match.

# ============================================================================
# 1. THE HEADER. Verbatim from bootstrap-session.sh:1-25 — abridged.
# ============================================================================
# Create the tmux session and lane windows the supervisor dispatches into.
#
# WHY: ... `grep -rln 'new-session|new-window' scripts/` returned NOTHING: the
# session those scripts operate on only ever existed because it was built by
# hand. `dispatch.sh` fails closed with no lane to dispatch to, which is correct
# and is also the whole experience of a fresh clone.
#
# SAFETY. This script never modifies an existing session. It refuses instead.
# The estate's live session is running work at all times, and a bootstrap that
# "helpfully" reset it would destroy exactly the lanes it was meant to serve.
# Topping an existing session up to LANES is opt-in via --add-lanes, and even
# that only ever ADDS windows; it does not rename, renumber, kill or restart
# anything already there.
#
# Usage:
#   bootstrap-session.sh [--session NAME] [--lanes N] [--agent CMD]
#                        [--harness NAME] [--cwd DIR] [--add-lanes] [--dry-run]
#
# Exit 0 when the session exists with at least --lanes windows and every lane
# was started by this run or already present. Exit 1 on any refusal.

# ============================================================================
# 2. PRELUDE. Note `set -euo pipefail` here; several other scripts use
#    `set -uo pipefail` deliberately because they need to inspect exit codes.
#    Pick consciously and say why in a comment.
# ============================================================================
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=./session-defaults.sh
. "$HERE/session-defaults.sh"
SESSION="$(lanes_session_or_default)"   # <-- NEVER a hardcoded 'agent-supervisor'.
                                        #     Finding A11: 304 such literals exist.
LANES=10
AGENT_CMD="${LANES_AGENT_CMD:-}"        # empty => resolved later from the harness
                                        # registry, so there is ONE definition of
                                        # how a lane starts, not two that drift.
WORKDIR="$PWD"
ADD_LANES=0
DRY_RUN=0
SUPERVISOR_WINDOW="${LANES_SUPERVISOR_WINDOW:-1}"

# State lives under $SUPERVISOR_STATE (poller-recover.sh / heartbeat.sh shape).
# Deliverables live in git; this directory holds STATE, never code — rule S5.
STATE="${SUPERVISOR_STATE:-$HOME/.local/state/agent-dotfiles-supervisor}"
LOG="$STATE/reaper.log"

# ============================================================================
# 3. ARG PARSING. A plain `while/case` loop. No getopts, no long-option
#    library. Unknown args are consumed with a bare `shift` in the scripts that
#    tolerate them (heartbeat.sh) and rejected in the ones that do not.
# ============================================================================
while [ $# -gt 0 ]; do
  case "$1" in
    --session)    SESSION="${2:-}"; shift 2 ;;
    --lanes)      LANES="${2:-10}"; shift 2 ;;
    --agent)      AGENT_CMD="${2:-}"; shift 2 ;;
    --cwd)        WORKDIR="${2:-$PWD}"; shift 2 ;;
    --add-lanes)  ADD_LANES=1; shift ;;
    --dry-run)    DRY_RUN=1; shift ;;
    -h|--help)    sed -n '1,40p' "$0"; exit 0 ;;   # the header IS the help text
    *)            echo "unknown argument: $1" >&2; exit 1 ;;
  esac
done

# ============================================================================
# 4. LOGGING. Both to the durable file and to stdout, so a caller
#    (watchdog.sh) folds the same line into its own log without a second,
#    differently-worded message to keep in sync. UTC, ISO-8601, always.
#    poller-recover.sh:144-147.
# ============================================================================
log() {
  mkdir -p "$(dirname "$LOG")" 2>/dev/null
  printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$*" | tee -a "$LOG" 2>/dev/null
}

# ============================================================================
# 5. THE mkdir LOCK. macOS ships no flock(1). mkdir is atomic without it.
#    poller-recover.sh:39-62 argues this at length; the load-bearing part is
#    that the lock MUST BE RECLAIMABLE:
#
#      "An `EXIT` trap does not run on SIGKILL, a hard crash, or a LaunchAgent
#       enforcing a hard kill on a hung tick ... Without a reclaim path a lock
#       left behind that way is permanent: every later tick reads 'another
#       recovery is already in flight', logs the same line forever, and never
#       touches tmux again -- the poller stays down and NOTHING says so
#       distinctly from the ordinary, benign case."
#
#    That is the whole estate's failure mode in one paragraph. A reaper whose
#    lock cannot be reclaimed is a reaper that dies silently exactly once.
# ============================================================================
LOCK="$STATE/.reaper.lock"
mkdir -p "$STATE" 2>/dev/null
if ! mkdir "$LOCK" 2>/dev/null; then
  # Record who holds it and when, so a stale lock can be told from a live one.
  holder=$(cat "$LOCK/pid" 2>/dev/null || echo "")
  taken=$(cat "$LOCK/at" 2>/dev/null || echo 0)
  case "$taken" in ''|*[!0-9]*) taken=0 ;; esac
  age=$(( $(date +%s) - taken ))
  if [ -n "$holder" ] && kill -0 "$holder" 2>/dev/null; then
    log "another run (pid $holder) holds the lock -- benign no-op for this tick"
    exit 0
  elif [ "$age" -lt 300 ]; then
    log "lock held by pid ${holder:-unknown}, ${age}s old -- too young to reclaim; no-op"
    exit 0
  else
    log "RECLAIMING lock from dead pid ${holder:-unknown} (${age}s old)"
    rm -rf "$LOCK" && mkdir "$LOCK" 2>/dev/null || { log "could not reclaim lock"; exit 1; }
  fi
fi
printf '%s' "$$" > "$LOCK/pid"
date +%s > "$LOCK/at"
trap 'rm -rf "$LOCK"' EXIT INT TERM

# ============================================================================
# 6. VALIDATE BEFORE TOUCHING ANYTHING. Every guard below cites the review or
#    incident that added it. Note the SHAPE: reject early, to stderr, with the
#    remedy on the next line, exit 1.
# ============================================================================

# tmux silently rewrites `:` and `.` in a session name (they are its target
# delimiters), then every later target built from the ORIGINAL string misses.
# Review of #137 hit this: new-session succeeded as `bs_evil-N` while the
# follow-up move-window failed on `bs:evil-N`, leaving a stray half-built
# session the failure report never mentioned. Reject up front instead.
case "$SESSION" in
  ""|*:*|*.*)
    echo "bootstrap-session: --session must be non-empty and contain no ':' or '.' (got '$SESSION')" >&2
    echo "  tmux uses both as target delimiters and rewrites them in session names." >&2
    exit 1 ;;
esac

# `command -v` succeeds for shell builtins (`cd`, `true`, `echo`), which have
# no PATH-resident binary and are not harnesses. Review of #137 showed
# `--agent cd` sailing through this guard and producing exactly the all-`dead`
# session the guard exists to prevent. Require a real executable path.
AGENT_BIN="${AGENT_CMD%% *}"
AGENT_PATH="$(command -v "$AGENT_BIN" 2>/dev/null || true)"
case "$AGENT_PATH" in /*) ;; *) AGENT_PATH="" ;; esac
if [ -z "$AGENT_PATH" ] || [ ! -x "$AGENT_PATH" ]; then
  echo "bootstrap-session: agent command not on PATH: $AGENT_BIN" >&2
  echo "  pass --agent with the harness this machine actually has (claude, copilot, codex)" >&2
  exit 1
fi

# GOTCHA worth copying wholesale (poller-recover.sh:157-171, agent-supervisor#25):
# lsof lives at /usr/sbin/lsof on macOS and /usr/sbin is NOT on the LaunchAgent
# PATH. Under that PATH `command -v lsof` finds nothing, and the check that
# depended on it treated "instrument missing" identically to "condition absent"
# -- the fail-OPEN defect. Resolve the binary once, by absolute path, so the
# check does not depend on the caller's PATH at all.
LSOF_BIN=""
if command -v lsof >/dev/null 2>&1; then LSOF_BIN="lsof"
elif [ -x /usr/sbin/lsof ]; then LSOF_BIN="/usr/sbin/lsof"; fi

# ============================================================================
# 7. THE REFUSAL THAT NAMES ITS ACTUATOR. bootstrap-session.sh:244-251.
#    Seat 4's proposed 11th invariant: "a refusal-to-act must name what does
#    act instead, or it is a bug." Four of these five lines are the naming.
#    43 sites in the estate refuse WITHOUT naming an actuator; that count is
#    grandfathered and may only go down.
# ============================================================================
if session_exists && [ "$ADD_LANES" -eq 0 ]; then
  count="$(printf '%s\n' "$existing_indexes" | grep -c . || true)"
  echo "bootstrap-session: session '$SESSION' already exists ($count window(s)) -- refusing." >&2
  echo "  This script never modifies a running session; that session may be holding live work." >&2
  echo "  To add lanes up to --lanes without touching existing windows: --add-lanes" >&2
  echo "  To start clean, kill it yourself first: tmux kill-session -t $SESSION" >&2
  exit 1
fi

# ============================================================================
# 8. --dry-run IS A FIRST-CLASS PATH, not an afterthought. The `run` wrapper
#    prints instead of executing. This discipline is what caught the two
#    destructive restore.sh invocations during the audit (156 restores planned
#    into a 10-window session) BEFORE anything ran them. Every new actuator in
#    this PRP needs it.
# ============================================================================
run() {
  if [ "$DRY_RUN" -eq 1 ]; then echo "  would run: tmux $*"; else tmux "$@"; fi
}

echo "bootstrap-session: session=$SESSION lanes=$LANES agent=$AGENT_CMD cwd=$WORKDIR"
[ "$DRY_RUN" -eq 1 ] && echo "  (dry run -- nothing will change)"

if ! session_exists; then
  run new-session -d -s "$SESSION" -n "$SUPERVISOR_NAME" -c "$WORKDIR"
  # tmux may be configured with base-index 1 or 0; renumber rather than assume.
  if [ "$DRY_RUN" -eq 0 ]; then
    first="$(tmux list-windows -t "=$SESSION" -F '#{window_index}' | head -1)"
    [ "$first" = "$SUPERVISOR_WINDOW" ] || tmux move-window -s "=$SESSION:$first" -t "=$SESSION:$SUPERVISOR_WINDOW"
  fi
  run send-keys -t "=$SESSION:$SUPERVISOR_WINDOW" "$AGENT_CMD" Enter

  # ==========================================================================
  # 9. THE LEDGER WRITE — directly load-bearing for A2. This is the ONLY place
  #    a fresh clone's ledger gets a `sessions` row: the write side of
  #    "supervised vs Jon's own". The reaper's set-difference (A1) reads what
  #    this writes. Note it only fires on the branch that actually CREATES a
  #    session — --add-lanes has no opinion on supervision, and a pre-existing
  #    session must not be silently re-decided.
  #    Note also that a FAILED record is a WARNING with a named remedy, not a
  #    silent pass and not a fatal.
  # ==========================================================================
  if [ "$DRY_RUN" -eq 0 ]; then
    if ! "${SUPERVISOR_PYTHON:-python3}" "$HERE/cli.py" adopt-session --session "$SESSION" --source "bootstrap-session.sh" >/dev/null; then
      echo "bootstrap-session: WARNING: session '$SESSION' was created but could not be recorded as supervised -- it will read as unknown/unsupervised until adopted by hand ('cli.py adopt-session --session $SESSION')" >&2
    fi
  else
    echo "  would run: ${SUPERVISOR_PYTHON:-python3} $HERE/cli.py adopt-session --session $SESSION --source bootstrap-session.sh"
  fi
fi

# ============================================================================
# 10. EXIT CODES CARRY MEANING. From restore.sh:44-46, which is the model:
#
#       Exit 0  every lane the ledger knows is live or was restored
#            1  usage / no plan could be read
#            2  at least one lane is unrecoverable (reported, not restarted)
#
#     "2 means 'some lane could not be brought back', and that is not a crash."
#     For S2's run-from-main wrapper the estate deliberately uses 78
#     (EX_CONFIG) as its refusal code. Document the code in the header.
# ============================================================================
exit 0
