#!/bin/bash
# The only path that closes an issue in this estate -- #247.
#
# WHY: seven issues here were closed while their symptom continued, worst
# case the tmux test-isolation leak, closed TWICE while it recurred hourly
# and Jon killed the leaked sessions by hand. The common shape: the lane
# that did the work is also the thing that declared it done. It ran
# `gh issue close` itself, and nothing independent checked the claim. An
# agent that believes it finished is indistinguishable, from the outside,
# from an agent that actually finished.
#
# `cosmix/loom` solved the same problem for its own completion RPC by
# refusing to let the agent certify itself: identity comes from the KERNEL
# (`SO_PEERCRED`, a `/proc` ancestry walk), not from anything the agent
# sends. Their own module header records that a `.work/user.token` scheme
# was tried and dropped -- the token had to be simultaneously readable by
# the agent (to send it) and unreadable by the agent (to prevent forgery),
# a contradiction no secret resolves. The lesson that generalises is "identity
# the process cannot author", not their specific Rust/socket mechanism.
#
# This script is the bash equivalent, built from primitives already proven
# in this repo (watchdog.sh's duplicate-poller detector walks
# `ps -o ppid=`/`ps -o lstart=` the same way -- see its comment near
# "records=" -- this reuses that exact pair of fields, not a new mechanism):
#
#   1. IDENTITY, BY PID ANCESTRY. macOS has no /proc, so `identity_check`
#      below walks `ps -o ppid=` from this process up toward pid 1 and
#      refuses to close unless the SUPERVISOR's registered anchor pid is
#      actually in that chain -- a lane invoked from a different tmux pane's
#      process tree never has it as an ancestor, no matter what it sends.
#      A `ps -o lstart=` fingerprint recorded at `register` time is
#      rechecked against the live process at that pid, so a pid recycled by
#      the OS after the real supervisor exited reads as UNKNOWN, not as a
#      match (`register`'s comment says why this is best-effort, not proof).
#   2. A NONCE ISSUED AT VERIFICATION TIME, not chosen by whoever reports.
#      `nonce <issue>` is itself identity-gated, so only the supervisor can
#      mint one, and a completion report a lane writes ahead of time cannot
#      carry a nonce it was never given -- there is nothing to guess in
#      advance, per the loom lesson above.
#   3. THE SUPERVISOR RUNS THE CHECK ITSELF. `close` never trusts a lane's
#      claimed exit code or pasted transcript -- a transcript is a claim
#      about a run nobody else saw. It runs `--check` in this process and
#      reads ITS OWN exit status.
#   4. LANES LOSE `gh issue close` ENTIRELY. `close` is the only subcommand
#      that runs it, and `close` is identity-gated. `report` -- the
#      subcommand a lane uses to hand over its nonce and a note -- never
#      closes anything; it is a claim, filed, not certified.
#
# Every refusal is loud (stderr) AND recorded (`refusals.log`, append-only,
# never truncated by this script) -- "with the refusal recorded" is the
# literal acceptance criterion, not just a stderr line nobody kept.
#
# UNKNOWN NEVER MEANS SAFE. Every identity check that cannot be resolved --
# no identity registered yet, `ps` failing, the ancestor pid not found, the
# fingerprint not matching -- refuses. This mirrors session_guard.py's
# `remove_guard`: undeterminable must never collapse into "proceed".
#
# Usage:
#   verify_and_close.sh register [--pid PID]
#   verify_and_close.sh nonce <issue>
#   verify_and_close.sh report <issue> --nonce N [--note TEXT]
#   verify_and_close.sh close <issue> --repo OWNER/NAME --check "CMD" [--dir PATH] [--comment TEXT]
#
# Exit 0  the subcommand's operation completed (a `close` refusal still exits
#         non-zero -- see below).
# Exit 1  a gate refused: identity could not be established, no nonce was
#         issued, the report's nonce did not match, or the check command
#         itself failed. Nothing was closed.
# Exit 2  usage error.
set -uo pipefail

STATE_DIR="${AGENT_SUPERVISOR_STATE_DIR:-$HOME/.local/state/agent-dotfiles-supervisor}/verify-and-close"
GH="${VERIFY_AND_CLOSE_GH:-gh}"
IDENTITY_FILE="$STATE_DIR/identity.env"
REFUSALS_LOG="$STATE_DIR/refusals.log"

mkdir -p "$STATE_DIR/nonces" "$STATE_DIR/reports" "$STATE_DIR/verified"

_now() { date -u +%Y-%m-%dT%H:%M:%SZ; }

# Every refusal, from every subcommand, goes through here -- one place, so
# "with the refusal recorded" cannot drift true for one gate and false for
# another the way three independent `echo >> log` call sites would.
refuse() {
  local reason="$1"
  printf 'verify_and_close: REFUSED -- %s\n' "$reason" >&2
  printf '%s\tREFUSED\t%s\n' "$(_now)" "$reason" >>"$REFUSALS_LOG"
  return 1
}

reject() {
  local reason="$1"
  printf 'verify_and_close: REJECTED -- %s\n' "$reason" >&2
  printf '%s\tREJECTED\t%s\n' "$(_now)" "$reason" >>"$REFUSALS_LOG"
  return 1
}

_trim() { sed 's/^[[:space:]]*//;s/[[:space:]]*$//'; }

# Walk `ps -o ppid=` from $$ toward pid 1, bounded so a `ps` that starts
# lying (a stub bug, a cycle) cannot hang this script -- 64 hops is far more
# than any real process tree here. Prints one pid per line.
_ancestor_chain() {
  local pid="$$" hops=0 ppid
  while [ "$hops" -lt 64 ] && [ -n "$pid" ] && [ "$pid" != "0" ] && [ "$pid" != "1" ]; do
    printf '%s\n' "$pid"
    ppid="$(ps -o ppid= -p "$pid" 2>/dev/null | _trim)"
    [ -n "$ppid" ] || break
    pid="$ppid"
    hops=$((hops + 1))
  done
}

# register: record the caller's chosen anchor pid (default $PPID, the
# process that spawned THIS invocation) as "the supervisor". Every later
# `close`/`nonce` call checks its own ancestry against this.
#
# TRUST ON FIRST USE, STATED, NOT HIDDEN: the very first registration has
# no prior identity to check against, so it is accepted unconditionally --
# same shape the issue itself names as unavoidable ("no secret can resolve
# this" -- loom's abandoned token). Every registration AFTER the first is
# gated by `identity_check` against the identity already on file, so once a
# supervisor has registered, only that same ancestry can re-register or
# rotate it -- a lane cannot overwrite the anchor to make itself trusted.
cmd_register() {
  local pid=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --pid) pid="${2:-}"; shift 2 ;;
      *) echo "verify_and_close: register: unknown argument '$1'" >&2; return 2 ;;
    esac
  done
  if [ -f "$IDENTITY_FILE" ]; then
    if ! identity_check; then
      refuse "register: an identity is already on file and this caller's ancestry does not match it -- only the registered supervisor may re-register"
      return 1
    fi
  fi
  local anchor="${pid:-$PPID}"
  local start
  start="$(ps -o lstart= -p "$anchor" 2>/dev/null | _trim)"
  if [ -z "$start" ]; then
    refuse "register: could not read a live process at pid $anchor -- refusing to register an anchor that cannot be fingerprinted"
    return 1
  fi
  {
    printf 'ANCHOR_PID=%q\n' "$anchor"
    printf 'ANCHOR_START=%q\n' "$start"
    printf 'REGISTERED_AT=%q\n' "$(_now)"
  } >"$IDENTITY_FILE"
  echo "verify_and_close: registered anchor pid $anchor (start: $start)"
}

# identity_check: UNKNOWN unless every step below resolves positively.
# Nothing here ever guesses "probably fine".
identity_check() {
  if [ ! -f "$IDENTITY_FILE" ]; then
    refuse "identity: no supervisor identity has been registered -- run 'register' from the supervisor first"
    return 1
  fi
  local ANCHOR_PID="" ANCHOR_START=""
  # shellcheck source=/dev/null
  . "$IDENTITY_FILE"
  if [ -z "$ANCHOR_PID" ] || [ -z "$ANCHOR_START" ]; then
    refuse "identity: identity file is malformed -- refusing rather than guessing what it meant"
    return 1
  fi
  local chain
  chain="$(_ancestor_chain)"
  if ! grep -qx "$ANCHOR_PID" <<<"$chain"; then
    refuse "identity: registered anchor pid $ANCHOR_PID is not an ancestor of this process ($$) -- caller is not the supervisor"
    return 1
  fi
  local live_start
  live_start="$(ps -o lstart= -p "$ANCHOR_PID" 2>/dev/null | _trim)"
  if [ -z "$live_start" ]; then
    refuse "identity: anchor pid $ANCHOR_PID is in the ancestry chain but no longer alive to fingerprint -- UNKNOWN, not a match"
    return 1
  fi
  if [ "$live_start" != "$ANCHOR_START" ]; then
    refuse "identity: anchor pid $ANCHOR_PID is alive but its start time changed ('$live_start' vs registered '$ANCHOR_START') -- the pid was recycled, UNKNOWN, not a match"
    return 1
  fi
  return 0
}

_hex32() {
  if command -v openssl >/dev/null 2>&1; then
    openssl rand -hex 16
  else
    od -An -tx1 -N16 /dev/urandom | tr -d ' \n'
  fi
}

# nonce <issue>: identity-gated. A lane cannot mint its own nonce, so it
# cannot pre-write a completion report that will ever match one -- the
# whole point of "issued at verification time by the supervisor" (#247).
cmd_nonce() {
  local issue="${1:-}"
  [ -n "$issue" ] || { echo "usage: verify_and_close.sh nonce <issue>" >&2; return 2; }
  identity_check || return 1
  local n
  n="$(_hex32)"
  {
    # Named ISSUED_NONCE, deliberately not NONCE -- `close` sources this
    # file and a report file into the same shell scope, and a report is
    # lane-controlled text (cmd_report writes NONCE=<whatever it was given>).
    # Sharing a variable name would let the report file's value silently
    # clobber the one this script just issued, depending on source order --
    # exactly the kind of ambient-authority bug this whole script exists to
    # avoid. Distinct names make the two values impossible to conflate.
    printf 'ISSUED_NONCE=%q\n' "$n"
    printf 'ISSUED_AT=%q\n' "$(_now)"
  } >"$STATE_DIR/nonces/$issue.nonce"
  printf '%s\n' "$n"
}

# report <issue> --nonce N [--note TEXT]: UNGATED. This is the one thing a
# lane is still allowed to do -- report, not certify (#247 item 3). Filing a
# report with a nonce it was never issued is harmless: `close` below is what
# checks the nonce, and it is identity-gated, so a lane cannot reach it
# regardless of what it writes here.
cmd_report() {
  local issue="${1:-}"; shift || true
  [ -n "$issue" ] || { echo "usage: verify_and_close.sh report <issue> --nonce N [--note TEXT]" >&2; return 2; }
  local nonce="" note=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --nonce) nonce="${2:-}"; shift 2 ;;
      --note) note="${2:-}"; shift 2 ;;
      *) echo "verify_and_close: report: unknown argument '$1'" >&2; return 2 ;;
    esac
  done
  [ -n "$nonce" ] || { echo "usage: verify_and_close.sh report <issue> --nonce N [--note TEXT]" >&2; return 2; }
  {
    printf 'ISSUE=%q\n' "$issue"
    printf 'NONCE=%q\n' "$nonce"
    printf 'NOTE=%q\n' "$note"
    printf 'REPORTED_AT=%q\n' "$(_now)"
  } >"$STATE_DIR/reports/$issue.json"
  echo "verify_and_close: filed report for #$issue -- this is a claim, not a certification"
}

# close <issue> --repo OWNER/NAME --check "CMD" [--dir PATH] [--comment TEXT]
# The only subcommand that runs `gh issue close`. Every gate below must pass,
# in order, or nothing is closed:
cmd_close() {
  local issue="${1:-}"; shift || true
  [ -n "$issue" ] || { echo "usage: verify_and_close.sh close <issue> --repo OWNER/NAME --check CMD [--dir PATH] [--comment TEXT]" >&2; return 2; }
  local repo="" check="" dir="." comment=""
  while [ "$#" -gt 0 ]; do
    case "$1" in
      --repo) repo="${2:-}"; shift 2 ;;
      --check) check="${2:-}"; shift 2 ;;
      --dir) dir="${2:-}"; shift 2 ;;
      --comment) comment="${2:-}"; shift 2 ;;
      *) echo "verify_and_close: close: unknown argument '$1'" >&2; return 2 ;;
    esac
  done
  if [ -z "$repo" ] || [ -z "$check" ]; then
    echo "usage: verify_and_close.sh close <issue> --repo OWNER/NAME --check CMD [--dir PATH] [--comment TEXT]" >&2
    return 2
  fi

  # Gate 1: identity, by PID ancestry. Refuses UNKNOWN, never assumes.
  identity_check || return 1

  # Gate 2: a nonce must have been issued for this issue, by this same
  # (identity-checked) supervisor.
  local nonce_file="$STATE_DIR/nonces/$issue.nonce"
  if [ ! -f "$nonce_file" ]; then
    refuse "close #$issue: no nonce has been issued for this issue -- run 'nonce $issue' first"
    return 1
  fi
  local ISSUED_NONCE=""
  # shellcheck source=/dev/null
  . "$nonce_file"

  # Gate 3: a completion report must be on file, and its nonce must match
  # the one THIS supervisor issued -- not a nonce the lane invented.
  local report_file="$STATE_DIR/reports/$issue.json"
  if [ ! -f "$report_file" ]; then
    reject "close #$issue: no completion report has been filed for this issue"
    return 1
  fi
  local NONCE=""
  # shellcheck source=/dev/null
  . "$report_file"
  if [ -z "$NONCE" ] || [ "$NONCE" != "$ISSUED_NONCE" ]; then
    reject "close #$issue: completion report's nonce does not match the supervisor-issued nonce -- rejected"
    return 1
  fi

  # Gate 4: the supervisor runs the issue's own check command itself. A
  # lane's claimed result, anywhere in the report above, is never read for
  # this decision -- only this exit status is.
  local check_out check_rc sha
  check_out="$(cd "$dir" && eval "$check" 2>&1)"
  check_rc=$?
  sha="$(cd "$dir" && git rev-parse HEAD 2>/dev/null || echo unknown)"
  if [ "$check_rc" -ne 0 ]; then
    refuse "close #$issue: check command exited $check_rc -- not closing. Output:
$check_out"
    return 1
  fi

  local n
  n="$(_hex32)"
  local final_comment="${comment:-Verified and closed by the supervisor. check: \`$check\` (exit 0) at $sha. verification: $n}"
  if ! "$GH" issue close "$issue" --repo "$repo" --comment "$final_comment"; then
    refuse "close #$issue: check passed but 'gh issue close' itself failed -- not marking verified"
    return 1
  fi

  {
    printf 'ISSUE=%q\n' "$issue"
    printf 'REPO=%q\n' "$repo"
    printf 'NONCE=%q\n' "$ISSUED_NONCE"
    printf 'VERIFICATION=%q\n' "$n"
    printf 'CHECK=%q\n' "$check"
    printf 'SHA=%q\n' "$sha"
    printf 'CLOSED_AT=%q\n' "$(_now)"
  } >"$STATE_DIR/verified/$issue.json"
  # Single-use: a nonce that closed one issue must not be replayable.
  rm -f "$nonce_file"
  echo "verify_and_close: #$issue verified (check passed at $sha) and closed"
}

main() {
  local sub="${1:-}"; shift || true
  case "$sub" in
    register) cmd_register "$@" ;;
    nonce) cmd_nonce "$@" ;;
    report) cmd_report "$@" ;;
    close) cmd_close "$@" ;;
    ""|-h|--help)
      sed -n '/^# Usage:/,/^set -uo pipefail/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//' >&2
      exit 2
      ;;
    *)
      echo "verify_and_close: unknown subcommand '$sub'" >&2
      exit 2
      ;;
  esac
}

main "$@"
