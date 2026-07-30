#!/usr/bin/env bash
#
# lint-labs.sh — content-integrity gate for break/fix entries.
#
# Fails loud BEFORE staging. Checks that lab entries carry the sections that make them
# worth reading, that the status table matches the files on disk, and — the one that
# actually matters — that no entry was written without a prediction.
#
# Exit 0 = pass, 1 = failures.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; RST=$'\033[0m'
FAILED=0
err()  { printf '%s  FAIL%s  %s\n' "$RED" "$RST" "$1"; FAILED=1; }
warn() { printf '%s  WARN%s  %s\n' "$YEL" "$RST" "$1"; }
ok()   { printf '%s  ok%s    %s\n' "$GRN" "$RST" "$1"; }

REQUIRED=(
  "## Expected behavior"
  "## Deliberate fault"
  "## Prediction"
  "## Actual result"
  "## Investigation path"
  "## Root cause"
  "## Remediation"
  "## Verification"
  "## Lesson"
)

shopt -s nullglob
ENTRIES=(lab/[0-9][0-9]-*.md)

if [ ${#ENTRIES[@]} -eq 0 ]; then
  printf 'No lab entries yet — nothing to lint.\n'
  exit 0
fi

for f in "${ENTRIES[@]}"; do
  base="$(basename "$f")"

  for section in "${REQUIRED[@]}"; do
    grep -qF "$section" "$f" || err "${base}: missing section '${section}'"
  done

  # The prediction must have content between its heading and the next one.
  body="$(awk '/^## Prediction/{flag=1;next} /^## /{flag=0} flag' "$f" \
          | grep -vE '^\s*$|^>|^-\s*(What|Which|How far|Immediate)' | tr -d '[:space:]')"
  if [ -z "$body" ]; then
    err "${base}: Prediction section is empty — the prediction is written BEFORE the fault"
  fi

  # An entry with a filled Actual result but an untouched template prediction is the
  # failure mode this whole discipline exists to prevent.
  if grep -qF "Written before the fault was introduced" "$f" && [ -n "$body" ]; then
    :
  fi

  # Wrong predictions must keep a corrected-model section rather than being edited away.
  if grep -qiE '^\s*(prediction was )?(wrong|incorrect)' "$f" && ! grep -qF "## Corrected model" "$f"; then
    warn "${base}: notes an incorrect prediction but has no '## Corrected model' section"
  fi

  # Placeholders left behind
  grep -qE '<title>|<stage>|<slug>|^\s*```text\s*```' "$f" \
    && err "${base}: unfilled template placeholder remains"

  ok "$base"
done

# Status table in lab/README.md must reference every entry that exists.
if [ -r lab/README.md ]; then
  for f in "${ENTRIES[@]}"; do
    n="$(basename "$f" | cut -d- -f1)"
    grep -qE "^\| $n \|" lab/README.md \
      || err "lab/README.md: no status row for lab ${n}"
  done
  # And an entry marked complete must actually exist.
  while read -r n; do
    [ -z "$n" ] && continue
    ls "lab/${n}-"*.md >/dev/null 2>&1 \
      || err "lab/README.md: lab ${n} is not marked 'not started' but has no entry file"
  done < <(awk -F'|' '/^\| [0-9]{2} \|/ && $NF !~ /not started/ {gsub(/ /,"",$2); print $2}' lab/README.md)
fi

printf '\n'
[ "$FAILED" -eq 0 ] && { printf '%sPASS%s\n' "$GRN" "$RST"; exit 0; }
printf '%sFAIL%s — resolve before staging\n' "$RED" "$RST"
exit 1
