#!/usr/bin/env bash
# Generate ownership.tsv from the PRP's own task blocks, then verify it.
#
# WHY THIS EXISTS. The execution plan's parallel-safety contract rests on a file
# that did not exist. Its detector was:
#
#     cut -f2 ownership.tsv | sort | uniq -d
#
# with the rule "any output = STOP, silence = clean". Measured against a missing
# file, `cut` writes to stderr, sort and uniq emit nothing, and the pipeline exits
# 0 -- so an ABSENT manifest is indistinguishable from a CLEAN one. That is the
# same defect the whole remediation exists to remove: a guard that reports success
# while doing nothing.
#
# So this script does two things that the plan asserted but never built:
#   1. DERIVES the manifest from prps/estate_remediation.md, rather than trusting a
#      hand-maintained copy that can drift from the tasks it claims to describe.
#   2. VERIFIES it with a check that can FAIL -- explicit `if`/`exit`, never a bare
#      pipeline, and never `!`-negation (a `!`-negated pipeline does not abort under
#      `bash -eo pipefail`; that is how a guard in this repo was green and dead for
#      five and a half months).
#
# House style: `set -uo pipefail`, not `set -euo`. `set -e` would abort on the first
# grep that legitimately matches nothing.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PRP="${PRP_PATH:-$HERE/../../estate_remediation.md}"
OUT="${OWNERSHIP_TSV:-$HERE/ownership.tsv}"

# T8 and T10 both touch all six LaunchAgent plists. That overlap is REQUIRED
# serialization -- T8 repoints them, T10 wraps them, and the plan's ordering
# constraint (advance live/ -> repoint -> verify -> wrap) depends on both.
# It is the only permitted duplicate, so it is named here rather than discovered.
ALLOWED_DUP_RE='^launchd/com\.jonhill\..*\.plist$'
EXPECTED_DUPS=6

log() { printf '%s build-ownership-manifest: %s\n' "$(date -u '+%Y-%m-%dT%H:%M:%SZ')" "$*"; }

if [ ! -r "$PRP" ]; then
  log "FATAL: cannot read PRP at $PRP"
  exit 3   # could-not-measure, distinct from "found violations"
fi

# --- derive -----------------------------------------------------------------
# Task blocks look like:
#   Task 7: Some name
#   FILES TO CREATE/MODIFY:
#     - CREATE path/one.sh
#     - MODIFY path/two.py
#   PATTERN TO FOLLOW: ...
python3 - "$PRP" "$OUT" <<'PY'
import re, sys
prp, out = sys.argv[1], sys.argv[2]
task = None
in_files = False
rows = []
for line in open(prp, encoding='utf-8'):
    m = re.match(r'^Task (\d+):\s*(.+?)\s*$', line)
    if m:
        task, in_files = m.group(1), False
        continue
    if re.match(r'^FILES TO CREATE/MODIFY:\s*$', line):
        in_files = True
        continue
    if in_files:
        m = re.match(r'^\s+-\s+(CREATE|MODIFY|DELETE|READ)\s+(\S+)', line)
        if m:
            rows.append((task, m.group(2), m.group(1)))
            continue
        # any other non-blank, non-indented-bullet line ends the block
        if line.strip() and not line.startswith('  -'):
            in_files = False
with open(out, 'w', encoding='utf-8') as f:
    f.write("task\tpath\tverb\n")
    for t, p, v in rows:
        f.write(f"T{t}\t{p}\t{v}\n")
print(f"rows={len(rows)}")
PY
rc=$?
if [ "$rc" -ne 0 ]; then
  log "FATAL: manifest derivation failed (rc=$rc)"
  exit 3
fi

# --- verify the manifest is real before trusting any verdict from it --------
# A blind detector and a clean estate look identical. This is the positive control.
if [ ! -s "$OUT" ]; then
  log "FATAL: manifest is missing or empty at $OUT -- a verdict from it would be meaningless"
  exit 3
fi

rows=$(( $(wc -l < "$OUT") - 1 ))
if [ "$rows" -lt 100 ]; then
  log "FATAL: manifest has only $rows rows; the PRP declares 35 tasks and ~140 paths."
  log "       Too few rows means the parser stopped early -- treat as could-not-measure."
  exit 3
fi

# --- the actual duplicate check ---------------------------------------------
dups="$(tail -n +2 "$OUT" | cut -f2 | sort | uniq -d)"

if [ -z "$dups" ]; then
  log "FATAL: ZERO duplicates found. T8 and T10 are both declared to own all six"
  log "       LaunchAgent plists, so exactly $EXPECTED_DUPS duplicates are expected."
  log "       Zero means the parser did not see those blocks -- blind, not clean."
  exit 3
fi

n_dups=$(printf '%s\n' "$dups" | wc -l | tr -d ' ')
unexpected="$(printf '%s\n' "$dups" | grep -vE "$ALLOWED_DUP_RE")"

if [ -n "$unexpected" ]; then
  log "VIOLATION: paths claimed by more than one task, outside the allowed T8/T10 overlap:"
  printf '%s\n' "$unexpected" | while IFS= read -r p; do
    [ -z "$p" ] && continue
    owners="$(awk -F'\t' -v p="$p" '$2==p {printf "%s ", $1}' "$OUT")"
    log "  $p  <- claimed by: $owners"
  done
  log "Two agents would edit the same file concurrently. HALT the group."
  exit 1
fi

if [ "$n_dups" -ne "$EXPECTED_DUPS" ]; then
  log "VIOLATION: expected exactly $EXPECTED_DUPS allowed duplicates (the plists), found $n_dups."
  printf '%s\n' "$dups" | while IFS= read -r p; do log "  $p"; done
  exit 1
fi

log "OK: $rows paths, $n_dups duplicates, all within the declared T8/T10 plist overlap."
exit 0
