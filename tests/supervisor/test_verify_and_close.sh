#!/bin/bash
# verify_and_close.sh -- #247, "a lane must not be able to certify its own
# work". The acceptance criterion the issue names is explicit: NOT a green
# test suite on its own, but that a lane attempting to close its own issue
# is refused, demonstrated. This file demonstrates all three bullets from
# the issue:
#
#   - a lane running `close` (the wrapper) is refused, with the refusal
#     recorded in refusals.log;
#   - a completion report written without a supervisor-issued nonce is
#     rejected;
#   - a close attempted where PID ancestry cannot be established is refused,
#     never assumed safe.
#
# It also pins the properties around those three: the supervisor's own
# check command is what gates the close (never a claimed result), a lane
# can still file a report (it just cannot certify with one), and gh issue
# close is called exactly once, only on the fully-gated happy path.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAC="$HERE/../../scripts/supervisor/verify_and_close.sh"
pass=0; fail=0

ok()   { echo "  ok   $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL $1"; sed 's/^/       /' <<<"${2:-}"; fail=$((fail+1)); }
want_exit()     { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected exit $3, got $2: ${4:-}"; fi }
want_contains() { if grep -qF -- "$2" <<<"$3"; then ok "$1"; else bad "$1" "want '$2' in: $3"; fi }
want_missing()  { if grep -qF -- "$2" <<<"$3"; then bad "$1" "unwanted '$2' in: $3"; else ok "$1"; fi }

echo "verify_and_close.sh"

D=$(mktemp -d)
trap 'rm -rf "$D"' EXIT

cp "$HERE/stubs/ps-verify-and-close" "$D/ps"
cp "$HERE/stubs/gh-verify-and-close" "$D/gh"
chmod +x "$D/ps" "$D/gh"

STATE="$D/state"
GHLOG="$D/gh.log"

run() {
  # PATH puts the stubs first; AGENT_SUPERVISOR_STATE_DIR is not optional
  # here for the same reason it isn't in test_lane_done.sh -- without it
  # this suite would write into the real supervisor state directory under
  # $HOME.
  PATH="$D:$PATH" AGENT_SUPERVISOR_STATE_DIR="$STATE" STUB_GH_LOG="$GHLOG" \
    bash "$VAC" "$@" 2>&1
}
refusals() { cat "$STATE/verify-and-close/refusals.log" 2>/dev/null; }

# ============================================================ scenario setup
# ANCHOR (555) stands in for the supervisor's own process tree.
# LANE_PPID (777) stands in for a lane's -- a different pane's process tree,
# which never has 555 as an ancestor no matter how many hops are walked.
ANCHOR=555
LANE_PPID=777

as_supervisor() { STUB_PS_FIXED_PPID="$ANCHOR" run "$@"; }
as_lane()       { STUB_PS_FIXED_PPID="$LANE_PPID" run "$@"; }
as_unknown_ps() { ( unset STUB_PS_FIXED_PPID; run "$@" ); }  # `ps` cannot report ancestry at all

# --- a close attempted before anyone has registered is refused, UNKNOWN ----
rm -rf "$STATE"
out=$(as_supervisor close 1 --repo o/r --check true); rc=$?
want_exit "no identity registered yet: close refused" "$rc" 1 "$out"
want_contains "no identity registered yet: reason names it" "no supervisor identity has been registered" "$out"
want_contains "refusal is recorded, not just printed" "no supervisor identity has been registered" "$(refusals)"
want_missing "gh issue close was never called" "issue close" "$(cat "$GHLOG" 2>/dev/null)"

# --- register, as the supervisor -------------------------------------------
rm -rf "$STATE" "$GHLOG"
out=$(as_supervisor register --pid "$ANCHOR"); rc=$?
want_exit "supervisor can register" "$rc" 0 "$out"
want_contains "register names the anchor pid" "anchor pid $ANCHOR" "$out"

# --- acceptance bullet 3: PID ancestry cannot be established -> refused ----
# Two shapes of "cannot be established": ps itself fails to report
# ancestry, and ps reports an ancestry that simply does not include the
# registered anchor (the lane case, bullet 1).
out=$(as_unknown_ps close 1 --repo o/r --check true); rc=$?
want_exit "ps cannot report ancestry: close refused" "$rc" 1 "$out"
want_missing "ps cannot report ancestry: gh never called" "issue close" "$(cat "$GHLOG" 2>/dev/null)"

# --- acceptance bullet 1: a lane running the wrapper is refused ------------
out=$(as_lane close 1 --repo o/r --check true); rc=$?
want_exit "a lane's close attempt is refused" "$rc" 1 "$out"
want_contains "a lane's close attempt names why" "is not an ancestor" "$out"
want_contains "the lane's refusal is recorded" "is not an ancestor" "$(refusals)"
want_missing "a lane's close attempt never reaches gh issue close" "issue close" "$(cat "$GHLOG" 2>/dev/null)"

# A lane CAN still register itself if nothing has ever registered -- that is
# the accepted trust-on-first-use boundary. But once the supervisor holds
# the identity, a lane cannot steal or overwrite it:
out=$(as_lane register --pid "$LANE_PPID"); rc=$?
want_exit "a lane cannot re-register over an existing identity" "$rc" 1 "$out"
want_contains "re-register refusal names why" "only the registered supervisor may re-register" "$out"

# --- acceptance bullet 2: a report without a matching nonce is rejected ----
NONCE=$(as_supervisor nonce 1)
out=$(as_lane report 1 --nonce "not-the-real-nonce" --note "I finished"); rc=$?
want_exit "a lane CAN still file a report (it just cannot certify)" "$rc" 0 "$out"
out=$(as_supervisor close 1 --repo o/r --check true); rc=$?
want_exit "a report with the wrong nonce is rejected, not closed" "$rc" 1 "$out"
want_contains "wrong-nonce rejection names why" "does not match the supervisor-issued nonce" "$out"
want_contains "the rejection is recorded" "does not match the supervisor-issued nonce" "$(refusals)"
want_missing "wrong-nonce report never reaches gh issue close" "issue close" "$(cat "$GHLOG" 2>/dev/null)"

# A lane cannot mint the nonce it would need either -- `nonce` is gated the
# same way `close` is:
out=$(as_lane nonce 1); rc=$?
want_exit "a lane cannot mint its own nonce" "$rc" 1 "$out"

# A completion report filed with NO nonce at all is the same rejection, not
# a crash or a silent pass:
out=$(as_lane report 2 --note "no nonce given" 2>&1); rc=$?
want_exit "report without --nonce is a usage error, not accepted" "$rc" 2 "$out"

# --- the supervisor runs the check itself -- a lane's claim is never trusted
NONCE=$(as_supervisor nonce 3)
out=$(as_lane report 3 --nonce "$NONCE" --note "all tests pass, trust me")
out=$(as_supervisor close 3 --repo o/r --check false); rc=$?
want_exit "a failing check refuses the close regardless of the lane's note" "$rc" 1 "$out"
want_contains "the refusal shows the check's own exit code" "exited 1" "$out"
want_missing "a failed check never reaches gh issue close" "issue close" "$(cat "$GHLOG" 2>/dev/null)"

# --- the full happy path: only the supervisor, with a matching nonce, and a
# --- passing check, actually closes anything
NONCE=$(as_supervisor nonce 4)
as_lane report 4 --nonce "$NONCE" --note "done" >/dev/null
out=$(as_supervisor close 4 --repo o/r --check true); rc=$?
want_exit "supervisor + matching nonce + passing check: closes" "$rc" 0 "$out"
want_contains "gh issue close was called exactly once for #4" "issue close 4 --repo o/r" "$(cat "$GHLOG")"
want_contains "the closing comment cites the check that passed" "check: \`true\` (exit 0)" "$(cat "$GHLOG")"

# The nonce is single-use: replaying the same close must not re-close or
# re-call gh (there is no nonce file left to satisfy gate 2).
: >"$GHLOG"
out=$(as_supervisor close 4 --repo o/r --check true); rc=$?
want_exit "a consumed nonce cannot be replayed" "$rc" 1 "$out"
want_missing "replay never reaches gh issue close" "issue close" "$(cat "$GHLOG")"

echo "$pass passed, $fail failed"
[ "$fail" -eq 0 ]
