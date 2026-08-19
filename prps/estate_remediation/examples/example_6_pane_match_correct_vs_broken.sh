#!/usr/bin/env bash
# Source: scripts/supervisor/heartbeat.sh
# Lines: 84-96 (CORRECT) and 190-201 (BROKEN)
# Pattern: verifying an effect in a tmux pane — the right way and the wrong way,
#          in ONE file, 104 lines apart. Finding E2.
# Extracted: 2026-08-19 from commit 6b7c4435
# Relevance: 10/10 — the single most instructive artifact in this estate.
#
# ============================================================================
# WHY THIS IS THE MOST IMPORTANT EXAMPLE IN THIS DIRECTORY
# ============================================================================
# The same author, in the same file, wrote the fix and then reintroduced the
# defect one screen later. The header comment at line 84 DESCRIBES the trap in
# detail and the code at line 197 walks straight into it. Reading only one half
# teaches nothing; reading both teaches the actual lesson, which is that the
# discipline has to be applied at EVERY read of a pane, not once per file.
#
# The defect: line 197 greps the WHOLE pane for `esc to interrupt`. The message
# this script types into that same pane at line 149 CONTAINS the literal string
# `esc to interrupt`. So the grep matches the script's own message. The success
# branch is taken unconditionally and line 200 — the "the pane did NOT start
# working; a human should look" branch — is UNREACHABLE. Every nudge in the
# estate's history has reported success.
#
# The fix at line 93 is three extra pipeline stages: strip blank lines, take
# only the LAST one, then match. A busy marker is a statement about the pane's
# CURRENT footer, never about text the pane happens to be displaying anywhere
# in its scrollback.


# ----------------------------------------------------------------------------
# CORRECT — heartbeat.sh:84-96. Copy THIS shape.
# ----------------------------------------------------------------------------
working=0
while read -r w; do
  [ -n "$w" ] || continue
  # LAST NON-BLANK LINE ONLY -- never a scrollback sweep. This is lanes.sh's
  # #65 discipline and skipping it broke this file within one hour of writing
  # it: the nudge text below QUOTES the string `esc to interrupt`, so the
  # moment the first nudge landed in the Director's pane, a whole-pane grep
  # matched its own message and every later pass reported "1 pane-working".
  # The heartbeat fired once and then permanently disabled itself, staying
  # silent through a 9,223-second stall. A busy marker is a statement about
  # the CURRENT footer, never about text a pane happens to be displaying.
  p=$(tmux capture-pane -p -t "=$w" 2>/dev/null) || continue
  if grep -v '^[[:space:]]*$' <<<"$p" | tail -1 | grep -q 'esc to interrupt'; then
    working=$(( working + 1 ))
  fi
done < <(tmux list-windows -a -F '#{session_name}:#{window_id}' 2>/dev/null | grep -v Hill90)
#                                    ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
# Note also: windows are addressed by `#{window_id}` (`@N`), never by index —
# AGENTS.md invariant 5. But see the GOTCHA at the bottom of this file: an @id
# does not survive a tmux server restart either.


# ----------------------------------------------------------------------------
# BROKEN — heartbeat.sh:190-201. This is what the same file does 104 lines later.
# ----------------------------------------------------------------------------

# The message contains the very string the verification below greps for.
# (heartbeat.sh:149, abridged — the literal is on the first line.)
MSG="HEARTBEAT: the estate looks STALLED -- no ledger write for ${since}s and no lane showing \`esc to interrupt\`. ..."

# C-u then retype then Enter, ALWAYS -- Enter alone does not submit text a
# previous send-keys left in the box. (This part is correct and worth copying.)
tmux send-keys -t "=$TARGET" C-u 2>/dev/null
sleep 1
tmux send-keys -t "=$TARGET" -l "$MSG" 2>/dev/null
sleep 2
tmux send-keys -t "=$TARGET" Enter 2>/dev/null
sleep 6

# vvv THE DEFECT vvv
# No blank-line strip. No `tail -1`. A whole-pane grep for a string that $MSG
# — typed into this exact pane four lines ago — is guaranteed to contain.
# This condition is ALWAYS TRUE. The else branch cannot execute.
if tmux capture-pane -p -t "=$TARGET" 2>/dev/null | grep -q 'esc to interrupt'; then
  log "STALLED ${since}s -- nudged $TARGET, pane is now working"
else
  # UNREACHABLE. heartbeat.sh:200. Never once executed.
  log "STALLED ${since}s -- nudged $TARGET but the pane did NOT start working; a human should look"
fi


# ----------------------------------------------------------------------------
# THE FIX the implementer must write
# ----------------------------------------------------------------------------
# Two independent changes, and BOTH are needed. Doing only one leaves a check
# that is correct today and re-breaks the next time someone edits the message.
#
#   1. Match the footer, not the pane. Reuse the line-93 pipeline verbatim.
#   2. Make the message incapable of matching. The marker must not be a
#      substring of anything this script types. Either drop the backticked
#      literal from $MSG, or match on a token the harness emits and a human
#      message never would.
#
# Sketch:
#
#     pane_is_working() {   # ONE definition, called from both sites.
#       local target="$1" p
#       p=$(tmux capture-pane -p -t "=$target" 2>/dev/null) || return 1
#       grep -v '^[[:space:]]*$' <<<"$p" | tail -1 | grep -q 'esc to interrupt'
#     }
#
# A shared helper is the structural fix: the audit's gotcha #7 records the same
# class in director-route.sh:149 — "any private copy of a matcher is this
# defect". Two copies of a matcher WILL drift; one already did, in this file.
#
# ----------------------------------------------------------------------------
# MUTATION VERIFICATION — required, and easy here
# ----------------------------------------------------------------------------
# The test must go RED when the fix is reverted. Concretely, in an isolated
# tmux (see example_2):
#
#   * plant a pane whose scrollback CONTAINS `esc to interrupt` but whose last
#     non-blank line does not (i.e. an idle pane that was recently nudged);
#   * assert the check reports NOT working;
#   * revert to the whole-pane grep and assert the same test now reports
#     working. Commit that transcript.
#
# Without the planted-scrollback case the test passes against BOTH versions and
# proves nothing. That is exactly how this defect survived being described in
# a comment twelve lines above the code that has it.
#
# ----------------------------------------------------------------------------
# TWO GOTCHAS THIS FILE ALSO CARRIES (do not lose them in the fix)
# ----------------------------------------------------------------------------
# 1. A claude-print lane HAS NO PANE. 162 of 196 lanes ran on that transport.
#    A pane-only probe reports a busy claude-print estate as 0 working, which
#    heartbeat.sh already compensates for with a bounded ledger in-flight count
#    (heartbeat.sh:101-119). Any new liveness check needs the same second source.
# 2. `window_id` does not survive a tmux server restart (finding A10 /
#    agent-supervisor#346). heartbeat.sh:180-188 handles this correctly —
#    it re-resolves the target, and REFUSES to guess when the session has more
#    than one window rather than typing into an unrelated pane. That refusal
#    names what a human must do; see example_1 for the same posture.
