#!/bin/bash
# Source: tests/supervisor/test_bootstrap_session.sh (parts A-D),
#         scripts/supervisor/tmux-isolation.sh (part B, verbatim, whole file),
#         tests/supervisor/test_observed_absence_sampling.sh (part E)
# Lines: test_bootstrap_session.sh 1-80; tmux-isolation.sh 1-16;
#        test_observed_absence_sampling.sh 1-70
# Pattern: how a shell test is written here — assertion helpers, tmux isolation,
#          scratch ledger, traps, and the POSITIVE-CONTROLLED ABSENCE check.
# Extracted: 2026-08-19 from commit 6b7c4435
# Relevance: 10/10 — every new gate in this PRP lands as a test of this shape.
#
# HOW THESE RUN: tests/supervisor/test_shell_suites.py globs `test_*.sh` and is
# picked up by `python -m unittest discover -s tests`. A shell test dropped in
# that directory IS enforced by CI — verified, not assumed. 109 test files today.

# ============================================================================
# A. THE HEADER. States what is under test and, critically, why a STUB would
#    not do. test_bootstrap_session.sh:1-14.
# ============================================================================
# These tests drive REAL tmux, not the fixture stub the lanes tests use: the
# thing under test IS session and window creation, and a stub that pretended
# to create windows would prove nothing about it.
#
# Every test runs against a throwaway session named for this PID. The live
# estate session must never be a test subject -- refusing to modify a running
# session is the script's central safety property, and a test that got that
# wrong would destroy the lanes it was meant to protect.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BOOT="$HERE/../../scripts/supervisor/bootstrap-session.sh"
source "$HERE/../../scripts/supervisor/tmux-isolation.sh"

# ============================================================================
# B. TMUX ISOLATION. AGENTS.md invariant 4. `tmux kill-server` destroyed this
#    estate THREE times; this guard is why it has not happened again. The whole
#    of scripts/supervisor/tmux-isolation.sh, reproduced — it is 16 lines:
#
#      assert_isolated_tmux() {
#        if [ -n "${TMUX:-}" ]; then
#          echo "tmux isolation: TMUX is set; refusing to target an attached server" >&2
#          return 1
#        fi
#        if [ -z "${TMUX_TMPDIR:-}" ]; then
#          echo "tmux isolation: TMUX_TMPDIR is required for destructive tmux verbs" >&2
#          return 1
#        fi
#        if [ ! -d "$TMUX_TMPDIR" ]; then
#          echo "tmux isolation: TMUX_TMPDIR does not exist: $TMUX_TMPDIR" >&2
#          return 1
#        fi
#      }
#
#    The mechanism: tmux resolves "default" purely relative to TMUX_TMPDIR, so
#    redirecting that variable redirects what "default" even MEANS. That is what
#    makes it safe to test session creation at all.
#    Since #185 the guard covers session CREATION, not just destruction — a
#    test harness that claimed the production session name on the default socket
#    got ticked by the production loop (finding A12 is the same class, new verb).
# ============================================================================
S="bootstrap-test-$$"
RT="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-tmux.XXXXXX")"
unset TMUX
export TMUX_TMPDIR="$RT"
assert_isolated_tmux || exit 1

# ============================================================================
# C. SCRATCH LEDGER — mandatory for anything that writes. agent-supervisor#153:
#    bootstrap-session.sh writes a `sessions` row on every session it creates.
#    Without this export, every run of the suite would write into Jon's REAL
#    ledger. The corpus work in this PRP makes that rule absolute.
# ============================================================================
LEDGER_DIR="$(mktemp -d "${TMPDIR:-/tmp}/bootstrap-ledger.XXXXXX")"
export AGENT_SUPERVISOR_STATE_DIR="$LEDGER_DIR"
CLI="$HERE/../../scripts/supervisor/cli.py"

# ============================================================================
# D. ASSERTIONS + CLEANUP. No framework. Three helpers, a pass/fail counter,
#    and an EXIT/INT/TERM trap. Copy verbatim.
# ============================================================================
pass=0; fail=0
ok()   { echo "  ok   $1"; pass=$((pass+1)); }
bad()  { echo "  FAIL $1 — $2"; fail=$((fail+1)); }
check(){ # check <name> <expected> <actual>
  if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "want '$2', got '$3'"; fi
}

# NEIGHBOUR is declared empty up front so `cleanup` can reference it
# unconditionally from line one. agent-supervisor#111: an inline kill-session
# is not a trap, so a crash between creating a second session and reaching that
# inline call leaves exactly the orphan the guard exists to prevent.
NEIGHBOUR=""
cleanup() {
  unset TMUX; export TMUX_TMPDIR="$RT"; assert_isolated_tmux
  tmux kill-session -t "$S" 2>/dev/null            # EXACT-MATCH kill. Never kill-server.
  [ -z "$NEIGHBOUR" ] || tmux kill-session -t "=$NEIGHBOUR" 2>/dev/null
}
cleanup_all() { cleanup; rm -rf "$RT" "$LEDGER_DIR"; }
trap cleanup_all EXIT INT TERM

# SKIP, do not fail, when the instrument is absent.
if ! command -v tmux >/dev/null 2>&1; then
  echo "  SKIP no tmux on PATH"; exit 0
fi

windows() { tmux list-windows -t "$S" -F '#{window_index} #{window_name}' 2>/dev/null; }

# 1. Refuses to touch a session that already exists. This is the one that
#    protects live work: the estate's session is always holding lanes.
tmux new-session -d -s "$S" -n existing 2>/dev/null
# Capture the layout rather than hardcoding "1 existing". tmux's base-index is
# a user setting: this session is created by raw tmux, not by the script, so it
# lands at whatever index the local .tmux.conf dictates -- 1 here, 0 on the CI
# runner. The property under test is "unchanged", not "equal to a literal", and
# hardcoding the index tested the runner's config instead of the script.
before_existing="$(windows)"
bash "$BOOT" --session "$S" --lanes 4 --agent bash >/dev/null 2>&1
check "refuses an existing session" "1" "$?"
check "existing session left untouched" "$before_existing" "$(windows)"
cleanup

# ^^ NOTE THE GENERAL RULE, which the whole PRP inherits (inferred req. #4):
#    assert the PROPERTY (unchanged / zero / bounded), never a snapshot literal.
#    The audit's own counts drifted 297->304 inside 24 hours.

# ============================================================================
# E. THE POSITIVE-CONTROLLED ABSENCE CHECK.
#    Adapted from tests/supervisor/test_observed_absence_sampling.sh:1-70.
#
#    This is the template every "zero violations" acceptance criterion in this
#    PRP must follow. The estate produced SIX false-clean results on 2026-07-31
#    alone (a missing `strings` binary read as an empty log; a green
#    `amtool check-config` on a config that could not deliver). An instrument
#    that cannot see the thing looks exactly like the thing being absent.
#
#    From #199's own brief: "the prior verification ... was a single post-run
#    snapshot -- exactly the shape #177 and #180 both closed on while the leak
#    kept recurring. #199's own acceptance is an OBSERVED ABSENCE: continuous
#    sampling across a real run, not a point-in-time check."
#
#    THREE PARTS, and all three are required:
# ============================================================================

# E1. Redirect what "the shared socket" even means, so the real one is at zero
#     risk while you sample the stand-in exactly as you would sample the real.
#     A SHORT, FIXED /tmp prefix -- not $TMPDIR. macOS's
#     /private/var/folders/.../T/ plus a descriptive name overflows AF_UNIX's
#     ~104-byte sun_path limit once tmux appends "/tmux-$UID/default". tmux's
#     error for that ("File name too long") looks like a setup bug, not a path
#     ceiling.
SHARED_RT="$(mktemp -d /tmp/oa-rt.XXXXXX)"
unset TMUX
export TMUX_TMPDIR="$SHARED_RT"
assert_isolated_tmux || { echo "  FAIL setup -- assert_isolated_tmux refused its own isolated dir"; exit 1; }

# E2. THE POSITIVE CONTROL. Prove the sampler CAN see a violation before you
#     let it report none. Plant one deliberately, assert it is detected, remove
#     it. A check that has never been shown going red is not a check.
sample_for_leak() {   # the instrument under scrutiny
  tmux -S "$SHARED_RT/tmux-$(id -u)/default" list-sessions -F '#{session_name}' 2>/dev/null
}
tmux new-session -d -s "planted-violation-$$" 2>/dev/null
if sample_for_leak | grep -q "planted-violation-$$"; then
  ok "POSITIVE CONTROL: the sampler detects a planted session"
else
  bad "POSITIVE CONTROL" "sampler is BLIND -- every 'zero leaks' result below is meaningless"
  exit 1     # refuse to report an absence from an instrument that cannot see
fi
tmux kill-session -t "=planted-violation-$$" 2>/dev/null

# E3. Only now assert the absence — and assert it by CONTINUOUS SAMPLING across
#     a real run under adverse conditions, not by one snapshot afterwards.
#     #199 names three conditions that must hold together: run inside a tmux
#     pane with $TMUX genuinely set for the child; run from a real `git worktree
#     add` checkout, not in place; and interrupt mid-run with SIGKILL, which no
#     EXIT/INT/TERM trap can catch. The SIGKILL is what turned a self-cleaning
#     transient leak into a persistent one against the pre-guard checkout.
#
#     Sketch of the loop (the real file is worth reading in full):
#         ( while :; do sample_for_leak >> "$OBS"; sleep 0.2; done ) & sampler=$!
#         run_the_thing_under_test
#         kill "$sampler" 2>/dev/null
#         grep -c "bootstrap-test-" "$OBS"   # expect 0, from a proven-sighted instrument

rm -rf "$SHARED_RT"
echo "  $pass passed, $fail failed"
[ "$fail" -eq 0 ]
