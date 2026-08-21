#!/bin/bash
# Dispatch one issue to one lane over `claude -p --output-format json`.
# `dispatch.sh`'s sibling, not its replacement -- same posture
# `dispatch-pi-rpc.sh` takes for `pi --mode rpc` (agent-supervisor#58/#160),
# built for agent-supervisor#171.
#
# WHY THIS SCRIPT EXISTS: #171/#215 measured that `pi --mode rpc` -- the
# transport #161 claimed to route one real lane onto -- is not exercisable
# with the credentials available to this estate. `pi --list-models` on this
# host lists exactly two providers, `github-copilot` and `openai-codex`; there
# is no `anthropic` provider configured (no ANTHROPIC_API_KEY, confirmed by
# `env` and a keychain lookup that found nothing) and pi's `--provider`
# defaults to `google`, which is also not configured. Both configured
# providers map onto the two harnesses #171's brief measured as exhausted
# (codex 100% weekly / zero credits, copilot 97.1%). So routing a lane
# through `pi`, over EITHER of its documented modes (`json` or `rpc`), would
# not be a real dispatch today -- it would fail against an exhausted quota,
# which is a worse outcome than never trying, because it would look like a
# transport defect rather than what it actually is. `claude -p` is the one
# non-keystroke surface this estate can actually exercise right now, because
# it draws on Claude's own capacity, not a wrapper's.
#
# WHY A SEPARATE SCRIPT, not a branch inside dispatch.sh: identical reasoning
# to `dispatch-pi-rpc.sh`'s own header -- `ClaudePrintAdapter.observe_lane` is
# a permanent no-op (there is no pane to poll), so there is no tmux pane for
# `lanes.sh` to classify as free, no window to rename, no input box to watch
# empty. Reusing `claim.sh` and `worktree.sh` unchanged, same as its sibling.
#
# WHY NOT REPLACE ANY STANDING `claude` LANE: `cli.py`'s own comment on
# `adapter_for_harness` is explicit -- "tmux stays the default transport for
# every existing lane (codex, claude) and is never replaced -- Jon requires
# the persistent, watchable terminals it gives him." This script never
# touches an existing lane; it registers a NEW one, opt-in, the same way
# `dispatch-pi-rpc.sh` adds a `pi-rpc` lane alongside `pi`'s send-keys default
# rather than converting one.
#
# FAIL CLOSED, EVERYWHERE, same shape as `dispatch-pi-rpc.sh`: `register`
# below performs a REAL `claude -p` handshake (`ClaudePrintAdapter.
# register_lane` calls `start_session` against a live subprocess) -- if
# `claude` is missing, crashes, or returns anything but a well-formed JSON
# result, this refuses and unwinds the claim and the worktree. `assign` then
# writes the brief into the ledger (`delivery_pending`) -- fast, no
# subprocess. Delivery -- the REAL, blocking `claude -p --resume <session>`
# call that waits out the actual turn -- is a separate step (`deliver`, see
# agent-supervisor#278 below), backgrounded by default so THIS script can
# return once the brief is on record rather than once the whole task is
# done. Nothing in this script ever falls back to `tmux send-keys` -- there
# is no tmux handling here at all to fall back to.
#
# agent-supervisor#278: measured live -- a `dispatch.sh` call routed onto a
# claude-print lane used to block for as long as the dispatched task took,
# sometimes hours, with zero output in between. A hung dispatch and a
# perfectly healthy one were indistinguishable to the caller (the watchdog),
# which read four straight timeouts as "dispatch is broken" and declared the
# loop dead. It was never broken -- `cli.py assign` was a single call that
# claimed the ledger's lock, ran `claude -p` to completion, and only then
# returned. Fixed by splitting `ClaudePrintAdapter.assign_task` (ledger
# writes only, fast) from `.deliver_task` (the blocking turn) -- see that
# class's own docstring in adapter.py. This script now backgrounds the
# `deliver` call and returns as soon as `assign` lands, unless `--wait` asks
# for the old synchronous behaviour.
#
# Usage:
#   dispatch-claude-print.sh [--wait] <issue> <slug> <brief-file> <repo> [repo-path]
#
# --wait   block until the real `claude -p` turn has exited and the task is
#          recorded complete -- the pre-#278 behaviour. Default: return once
#          the brief is assigned in the ledger (`delivery_pending`) and let
#          delivery run detached; poll the ledger/GitHub for completion the
#          way every other lane's completion is observed.
#
# Same positional argument meanings as `dispatch-pi-rpc.sh`.
#
# Exit 0 once the lane is registered, the worktree exists, and the brief is
# assigned in the ledger -- DISPATCHED, not COMPLETED (unless `--wait` was
# given, in which case exit 0 means the task reached `complete`). Exit
# non-zero on any refusal -- no free `claude` binary, an issue already
# claimed, a worktree that could not be built, a register or assign that
# could not reach `claude` -- and the issue's claim is released so it is not
# stranded looking taken.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON="${DISPATCH_PYTHON:-python3}"
CLI="$HERE/cli.py"

WAIT=""
POSITIONAL=()
while [ $# -gt 0 ]; do
  case "$1" in
    --wait)
      WAIT=1
      shift
      ;;
    *)
      POSITIONAL+=("$1")
      shift
      ;;
  esac
done
# bash 3.2-safe empty-array expansion -- see dispatch.sh's own comment on
# POSITIONAL for why the bare "${arr[@]}" form is not safe under `set -u`.
set -- "${POSITIONAL[@]+"${POSITIONAL[@]}"}"

ISSUE="${1:-}"
SLUG="${2:-}"
BRIEF="${3:-}"
REPO="${4:-}"
REPO_PATH="${5:-$PWD}"

if [ -z "$ISSUE" ] || [ -z "$SLUG" ] || [ -z "$BRIEF" ] || [ -z "$REPO" ]; then
  echo "usage: dispatch-claude-print.sh [--wait] <issue> <slug> <brief-file> <repo> [repo-path]" >&2
  exit 2
fi

[ -f "$BRIEF" ] || { echo "dispatch-claude-print: no brief file at $BRIEF" >&2; exit 1; }
BRIEF="$(cd "$(dirname "$BRIEF")" && pwd)/$(basename "$BRIEF")"

# Fail closed before anything else is touched: no `claude` on PATH means
# every step below would fail anyway, and this is the cheapest place to say
# so.
command -v claude >/dev/null 2>&1 || {
  echo "dispatch-claude-print: no 'claude' binary on PATH -- refusing rather than falling back to send-keys" >&2
  exit 1
}

# Same window-naming convention dispatch.sh/dispatch-pi-rpc.sh use.
NAME_PART="${REPO##*/}"
if [[ "$NAME_PART" == *-* ]]; then
  PREFIX=$(tr '-' '\n' <<<"$NAME_PART" | cut -c1 | tr -d '\n')
else
  PREFIX="$NAME_PART"
fi
LABEL="${PREFIX}${ISSUE}-${SLUG}"
LANE="$LABEL"
TASK_ID="$LABEL"

# --- 1. claim the issue on GitHub, same tool dispatch.sh uses --------------
if ! "$HERE/claim.sh" take "$ISSUE" "$REPO" "$LANE"; then
  echo "dispatch-claude-print: could not claim #$ISSUE -- not dispatching" >&2
  exit 1
fi

release_claim() { "$HERE/claim.sh" release "$ISSUE" "$REPO" >/dev/null 2>&1; }

# --- 2. give the lane its own worktree, same tool dispatch.sh uses --------
WORKTREE_ERR=$(mktemp)
WORKTREE=$("$HERE/worktree.sh" new "${ISSUE}-${SLUG}" "$REPO_PATH" 2>"$WORKTREE_ERR")
WORKTREE_RC=$?
if [ "$WORKTREE_RC" -ne 0 ] || [ -z "$WORKTREE" ]; then
  echo "dispatch-claude-print: worktree.sh new failed for #$ISSUE in $REPO_PATH -- NOT dispatching" >&2
  sed 's/^/  /' "$WORKTREE_ERR" >&2
  rm -f "$WORKTREE_ERR"
  release_claim
  exit 1
fi
rm -f "$WORKTREE_ERR"

abort() {
  echo "dispatch-claude-print: $1" >&2
  "$HERE/worktree.sh" done "$WORKTREE" >/dev/null 2>&1
  release_claim
  exit 1
}

# --- 3. the standing deliverable contract, same text dispatch.sh appends --
CONTRACT_MARKER="<!-- dispatch:deliverable-contract -->"
if ! grep -qF "$CONTRACT_MARKER" "$BRIEF" 2>/dev/null; then
  cat >>"$BRIEF" <<EOF || abort "could not append the deliverable contract to $BRIEF -- #$ISSUE was NOT dispatched"

$CONTRACT_MARKER
## Delivering this work

Added by \`dispatch-claude-print.sh\` on every dispatch, not by the brief's author.

Unless this brief says otherwise, when you are finished:
**push your branch and open a PR**.
If you produced no code -- a review, an investigation, an options paper --
**post your findings as a comment** on the issue or PR the brief names.

Do not stop with the work only in your worktree. From outside, a lane that
finished without shipping is indistinguishable from a lane that did nothing:
unshipped work looks exactly like no work, and the worktree is temporary.
EOF
fi

# --- 4. register the lane -- a REAL claude -p handshake --------------------
# `ClaudePrintAdapter.register_lane` spawns `claude -p --session-id <uuid>`
# in $WORKTREE and requires a well-formed JSON result back. This is the
# fail-closed gate: a `claude` that cannot start, crashes, or never answers
# makes THIS call fail.
REGISTER_OUT=$("$PYTHON" "$CLI" register \
  --lane "$LANE" \
  --target "claude-print:$LANE" \
  --harness claude \
  --transport claude-print \
  --repo "$WORKTREE" 2>&1)
REGISTER_RC=$?
if [ "$REGISTER_RC" -ne 0 ]; then
  abort "register failed -- claude -p is not reachable in $WORKTREE, refusing rather than falling back to send-keys:
$REGISTER_OUT"
fi

# --- 5. record the work as a task, before any delivery is attempted -------
SOURCE_URL="https://github.com/$REPO/issues/$ISSUE"
RECONSTRUCT_OUT=$("$PYTHON" "$CLI" reconstruct-task \
  --task "$TASK_ID" \
  --source-url "$SOURCE_URL" \
  --source-ref "$ISSUE" \
  --summary "#$ISSUE $SLUG; worktree=$WORKTREE; brief=$BRIEF" \
  --evidence "claimed by dispatch-claude-print.sh for lane $LANE" 2>&1)
RECONSTRUCT_RC=$?
if [ "$RECONSTRUCT_RC" -ne 0 ]; then
  abort "reconstruct-task failed -- #$ISSUE was NOT dispatched:
$RECONSTRUCT_OUT"
fi

# --- 6. assign -- fast, ledger-only, no subprocess --------------------------
# `assign` routes to `ClaudePrintAdapter.assign_task` because the lane it
# just registered carries transport=claude-print: agent-supervisor#278 split
# that method so this call writes `assigned` -> `delivery_pending` and
# returns WITHOUT touching `claude -p` at all -- see adapter.py's own
# docstring. A ledger write failing here raises, `assign` exits non-zero,
# and this script refuses exactly like every step above it -- never a silent
# report of success.
MESSAGE="Read $BRIEF and do exactly what it says. That file is your complete brief. Do all of your work in the worktree at $WORKTREE -- it is yours, already branched; never work in the shared checkout at $REPO_PATH."
ASSIGN_OUT=$("$PYTHON" "$CLI" assign \
  --lane "$LANE" \
  --task "$TASK_ID" \
  --summary "$MESSAGE" 2>&1)
ASSIGN_RC=$?
if [ "$ASSIGN_RC" -ne 0 ]; then
  abort "assign failed -- #$ISSUE was NOT dispatched:
$ASSIGN_OUT"
fi

# --- 7. deliver -- the REAL, blocking claude -p call -------------------------
# `deliver` re-spawns `claude -p --resume <session>` against $WORKTREE,
# sends the brief pointer as the prompt, and blocks until the process exits
# with its JSON result -- there is no tmux pane and no send-keys anywhere in
# this call, same as before #278. What changed: by default (no `--wait`)
# this runs DETACHED, so a crash, a timeout, or a hang in the actual turn no
# longer holds this script (or dispatch.sh, or whatever called it) hostage
# for the task's whole duration. Its outcome from here on is observed the
# way every other lane's is -- polling the ledger (`cli.py lane-diagnostic`)
# and GitHub for the PR -- not by this waiter.
STATE_DIR="${AGENT_SUPERVISOR_STATE_DIR:-$HOME/.local/state/agent-dotfiles-supervisor}"
DELIVER_LOG_DIR="$STATE_DIR/claude-print-deliver-logs"
mkdir -p "$DELIVER_LOG_DIR" 2>/dev/null || DELIVER_LOG_DIR="${TMPDIR:-/tmp}"
DELIVER_LOG="$DELIVER_LOG_DIR/$TASK_ID.log"

if [ -n "$WAIT" ]; then
  DELIVER_OUT=$("$PYTHON" "$CLI" deliver --lane "$LANE" --task "$TASK_ID" 2>&1)
  DELIVER_RC=$?
  if [ "$DELIVER_RC" -ne 0 ]; then
    abort "deliver failed -- claude -p did not complete #$ISSUE, refusing rather than falling back to send-keys:
$DELIVER_OUT"
  fi
  echo "dispatch-claude-print: #$ISSUE delivered to $LANE over claude-print, task $TASK_ID complete"
  echo "  lane:     $LANE"
  echo "  task:     $TASK_ID"
  echo "  worktree: $WORKTREE"
  echo "  brief:    $BRIEF"
  echo "$DELIVER_OUT"
else
  # agent-supervisor#75 established this exact shape for the same reason
  # (advance-live.sh's poller-restart waiter): `set -m` puts the backgrounded
  # job in its OWN process group instead of this script's, so it outlives
  # this script (and dispatch.sh, and whatever launched THAT) exiting --
  # `nohup`-equivalent survival without depending on `nohup` being on PATH.
  set -m
  "$PYTHON" "$CLI" deliver --lane "$LANE" --task "$TASK_ID" >"$DELIVER_LOG" 2>&1 &
  DELIVER_PID=$!
  set +m
  echo "dispatch-claude-print: #$ISSUE assigned to $LANE over claude-print, task $TASK_ID -- delivery running detached (pid $DELIVER_PID)"
  echo "  lane:     $LANE"
  echo "  task:     $TASK_ID"
  echo "  worktree: $WORKTREE"
  echo "  brief:    $BRIEF"
  echo "  log:      $DELIVER_LOG"
fi
exit 0
