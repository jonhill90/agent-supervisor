# Source: scripts/supervisor/watchdog_notify.py
# Lines: 1-38 (module docstring + SendError), 280-350 (classify + decide),
#        590-665 (path resolution + the real sender)
# Pattern: the estate's notification mechanism — a PURE DECISION CORE plus a
#          THIN ACTUATOR, an exception type that means "nobody was told", and
#          the three live defects (D3, D4, D5) that live in this exact file.
# Extracted: 2026-08-19 from commit 6b7c4435
# Relevance: 10/10 — findings A4, A5, D3, D4, D5 and S1-S3's paging all reuse
#            this path. The brief is explicit: FIX THE PATH, DO NOT BUILD A
#            CHANNEL. Delivery is proven (88 messages landed during the outage).
#
# stdlib only. `core.py`, `cli.py`, `ci_gate.py`, `itemize_prompts.py` are all
# stdlib too. DO NOT INTRODUCE A DEPENDENCY.

from __future__ import annotations

import calendar
import json
import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass
from pathlib import Path


# ============================================================================
# 1. THE ARCHITECTURE, from the module docstring. This split is the pattern.
# ============================================================================
"""Decide whether the watchdog's `escalate` state should reach a human.

Split per `docs/SPEC.md` §15, mirroring `recycle.py` -- a pure decision core
and a thin actuator. `decide_notify` takes the watchdog's current state and
whether the current escalate *episode* has already been notified, and
returns whether to send, why, and the episode flag for the next tick. It
does no I/O and sends nothing. `check_and_notify` is the actuator: it reads
`watchdog.status`, calls an injected `sender` -- the real one shells out to
the `notify` skill; tests inject a fake that only records calls -- and
persists the episode flag across ticks according to whether that send
actually succeeded. The flag means "a human has been told", never "we
tried" (#91).
"""
# ^^ TWO THINGS TO MIMIC, both load-bearing for this PRP:
#    (a) The decision function is PURE. That is what makes S1-S5 and A4/A5
#        testable without sending anything to Jon's phone.
#    (b) THE FLAG MEANS "A HUMAN HAS BEEN TOLD", NEVER "WE TRIED". The whole
#        audit is instances of the second being recorded as the first.


class SendError(Exception):
    """A send was attempted and failed. Always logged locally before this
    propagates -- an unreachable channel must not look like a healthy
    system, the same discipline the `notify` skill itself follows."""


# ============================================================================
# 2. CLASSIFY, THEN DECIDE — two functions, not one. The classifier reads the
#    fact off disk; the threshold comparison happens in the DECIDER, so the
#    threshold stays a decision-time parameter instead of being baked into
#    the reading. Copy this separation for every new check.
# ============================================================================
def classify_heartbeat(fields, *, now):
    if fields is None:
        return "missing", None
    checked_raw = fields.get("checked", "")
    try:
        checked_epoch = calendar.timegm(time.strptime(checked_raw, "%Y-%m-%dT%H:%M:%SZ"))
    except ValueError:
        return "unreadable", None            # <-- blindness is its OWN state,
    age_seconds = now - checked_epoch        #     never folded into "fine"
    if fields.get("state") == "stopped":
        return "stopped", age_seconds
    return "alive", age_seconds


def decide_notify_heartbeat(*, kind, age_seconds, threshold_seconds, episode_notified):
    """Pure decision ... Same one-per-episode shape as `decide_notify`: only a
    genuinely stale, still-unexplained heartbeat notifies, and only once per
    episode. Missing, stopped, and fresh are all silent AND reset the episode,
    so a later stale reading -- even a recurrence of the same underlying cause
    -- is treated as a new episode and pages again."""
    if kind == "missing":
        return NotifyDecision(
            should_notify=False,
            reason="inbox-poll.status missing — poller never started or state was wiped, not a stale-heartbeat page",
            next_episode_notified=False,
        )

    # ======================= DEFECT D5, LIVE, RIGHT HERE ====================
    # watchdog_notify.py:336. This exemption is UNBOUNDED IN TIME.
    # `inbox-poll.status` has read `stopped` since 17:15 and the alarm has been
    # permanently suppressed ever since. The reasoning below is sound for a
    # stop that JUST happened and false for one three days old.
    #
    # THE FIX: bound it. `if kind == "stopped" and age_seconds < STOP_GRACE`
    # -> silent; beyond that, a poller that stopped and never came back is
    # exactly what a human needs told about, and the EXIT trap that was
    # supposed to page plainly did not.
    if kind == "stopped":
        return NotifyDecision(
            should_notify=False,
            reason="poller reported its own stop (state: stopped) — its EXIT trap already decided whether to page, not double-paging here",
            next_episode_notified=False,
        )
    # ========================================================================

    stale = kind == "unreadable" or (age_seconds is not None and age_seconds > threshold_seconds)
    if not stale:
        return NotifyDecision(
            should_notify=False,
            reason=f"heartbeat {int(age_seconds)}s old, within the {threshold_seconds}s threshold — alive",
            next_episode_notified=False,
        )
    ...


# ============================================================================
# 3. THE MESSAGE BUILDER — and DEFECT D4, which is that the estate has one of
#    these and does not use it for every caller.
# ============================================================================
def build_heartbeat_message(*, age_seconds, threshold_seconds):
    """A message a human can act on from a lock screen: how stale, against
    what threshold, and the one command to look deeper."""
    age_desc = "unreadable" if age_seconds is None else f"{int(age_seconds)}s"
    return (
        f"watchdog: inbox-poll heartbeat stale — last checked {age_desc} ago, "
        f"threshold {threshold_seconds}s. "
        f"cat ~/.local/state/agent-dotfiles-supervisor/inbox-poll.status"
    )
# ^^ The DOCSTRING is the standard to hold every new page to: how bad, against
#    what threshold, and ONE command to look deeper — readable from a lock screen.
#
# DEFECT D4 (watchdog_notify.py:299): this `inbox-poll` message is hardcoded
# for ALL THREE subscribers. Every heartbeat page ever sent named the wrong
# subsystem, the wrong file, and the wrong threshold — it says `600s` in a
# message about a check whose real threshold is `210s`.
# THE FIX: the caller supplies its own subsystem, status file and threshold;
# the acceptance test asserts the PAGED threshold equals the CALLER's, which is
# the only assertion that would have caught this.


# ============================================================================
# 4. PATH RESOLUTION — and DEFECT D3, the silent fallback.
# ============================================================================
def resolve_notify_script(configured):
    if _resolves(configured):
        return configured, None
    fallback = str(DEFAULT_NOTIFY_SCRIPT)
    return fallback, (
        f"NOTIFY-PATH-STALE: configured notifier {configured!r} does not resolve; "
        f"falling back to the one shipped beside this module: {fallback}"
    )
# ^^ DEFECT D3: this ran on the fallback for TWO DAYS — 83 of 119 lines are
#    NOTIFY-PATH-STALE — and a broken config was indistinguishable from a
#    working one, because the warning is a returned string that goes into a log
#    nobody reads. The estate has 18,900+ lines of watchdog.log and zero readers.
#    THE FIX (acceptance criterion, verbatim): "NOTIFY-PATH-STALE cannot occur:
#    a stale notifier path exits non-zero and pages via the SURVIVING channel."
#    A degraded instrument must announce itself THROUGH a working channel, not
#    into the log of the thing that is degraded.


# ============================================================================
# 5. THE ACTUATOR. This is the function every new pager in this PRP calls.
#    Note especially the two `except` blocks — they are the most-copied
#    reasoning in this file.
# ============================================================================
def send_via_notify_skill(message: str, *, notify_script: str) -> None:
    """Real sender: shells out to whichever notifier is configured.

    Two call shapes, chosen by extension, because two notifiers exist and
    only one of them can currently reach Jon:

    - `*.sh` -> `notify.sh "<subject>" "<body>"`. This is
      `scripts/supervisor/notify.sh`, which delivers over Telegram and is
      the only path proven to land on Jon's phone (first real message
      2026-08-11 05:52Z).
    - anything else -> `python <script> --message <msg> --send`, the
      `notify` skill, which is iMessage-only today.

    `AGENT_NOTIFY_CALLER=supervisor` is set on the child's environment
    because `notify.sh` refuses to touch any channel without it
    (agent-dotfiles#52) -- this is the one process in the estate allowed
    to identify itself that way; nothing else should.
    """
    env = dict(os.environ, AGENT_NOTIFY_CALLER="supervisor")
    if notify_script.endswith(".sh"):
        argv = [notify_script, "Supervisor escalation", message]
    else:
        argv = [sys.executable, notify_script, "--message", message, "--send"]
    try:
        result = subprocess.run(argv, capture_output=True, text=True, timeout=30, env=env)
    except OSError as error:
        # A notifier that cannot be RUN is a delivery failure like any other,
        # and has to arrive through the same channel as one (#118). Left
        # uncaught, `subprocess.run` raised a bare FileNotFoundError past
        # `main()`, which only catches SendError: the process died with a
        # traceback instead of producing the NOTIFY-FAILED line, the rc=1, and
        # the "escalation did NOT reach a human" line `watchdog.sh` writes
        # into `watchdog.status` from it. The estate's loudest failure came
        # out as its quietest. Catching OSError covers the whole family --
        # missing, not executable, dangling symlink, unusable interpreter --
        # rather than only the path shape that happened to get reported.
        raise SendError(f"could not run notifier {notify_script!r}: {error}") from error
    except subprocess.TimeoutExpired as error:
        # Same reasoning, other way to not deliver: a channel that hangs is a
        # channel that reached nobody, and must not exit through a traceback
        # either.
        raise SendError(f"notifier {notify_script!r} timed out after 30s; nobody was told") from error
    if result.returncode != 0:
        raise SendError(
            f"notify.py exited {result.returncode}: {result.stderr.strip() or result.stdout.strip() or '(no output)'}"
        )


# ============================================================================
# 6. THE ANTI-GOAL. Copy the mechanism; do not copy more paging.
# ============================================================================
# "Do NOT make alerting louder. 88 Telegram messages delivered during the
#  outage; he was paged every nine minutes for two hours. Louder trains him to
#  filter."
#
# Every new page in this PRP must justify itself against that. The one-per-
# EPISODE flag above is the mechanism that makes A4 ("no_session must page")
# and A5 ("ceiling breach must hand off") additions rather than a storm.
# And note the direction D2 pushes: the 30-minute report must always SEND
# (a zero is the most important number), which is MORE FREQUENT TRUTHFUL
# REPORTS, not more alarms. State that reconciliation explicitly in the PRP.
