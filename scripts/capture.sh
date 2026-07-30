#!/usr/bin/env bash
#
# capture.sh — evidence capture for a single break/fix exercise.
#
# Lab entries reconstructed from memory a week later read exactly like what they are.
# This captures the raw material live; the polished lab/NN-*.md is derived from it.
#
# Workflow:
#   ./capture.sh predict 03-502-vs-503     write the prediction BEFORE breaking anything
#   ./capture.sh session 03-502-vs-503     recorded terminal session (script --timing)
#   ./capture.sh collect 03-502-vs-503     snapshot logs, sockets, journal, config state
#
# Output goes to evidence-working/<lab-id>/ which is gitignored — sanitize excerpts
# before they enter a lab entry. See CONVENTIONS.md.

set -euo pipefail

CMD="${1:-}"; LAB="${2:-}"
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIR="${ROOT}/evidence-working/${LAB}"

[ -z "$CMD" ] || [ -z "$LAB" ] && { sed -n '3,14p' "$0" | sed 's/^# \?//'; exit 2; }

mkdir -p "$DIR"
STAMP="$(date -Is)"

case "$CMD" in

predict)
  if [ -s "${DIR}/prediction.txt" ]; then
    echo "prediction.txt already exists for ${LAB}."
    echo "Predictions are never edited after the fact — that is the whole point."
    echo "Appending a timestamped addendum instead."
    printf '\n--- addendum %s ---\n' "$STAMP" >> "${DIR}/prediction.txt"
  else
    cat > "${DIR}/prediction.txt" <<EOF
# Prediction — ${LAB}
# Written ${STAMP}, BEFORE the fault was introduced. Do not edit after observing.

Fault to be introduced:

Client-visible result (status, body, timing):

Component that generates the response:

First log expected to hold useful evidence:

How far the request travels (nginx / Apache / PHP-FPM / application):

Immediate, queued, or timeout-driven:

Expected process or socket state:

Confidence, and what I am least sure about:
EOF
  fi
  "${EDITOR:-vi}" "${DIR}/prediction.txt"
  echo "→ ${DIR}/prediction.txt"
  ;;

session)
  [ -s "${DIR}/prediction.txt" ] || { echo "No prediction.txt yet. Run: $0 predict ${LAB}"; exit 1; }
  echo "Recording to ${DIR}/terminal.log — exit the shell to stop."
  script --timing="${DIR}/timing.log" --append "${DIR}/terminal.log"
  ;;

collect)
  echo "Collecting into ${DIR} at ${STAMP}"
  SUB="${DIR}/collect-${STAMP//:/}"
  mkdir -p "$SUB"

  # Sockets and processes
  ss -ltnp            > "${SUB}/ss-listening.txt" 2>&1 || true
  ss -tan             > "${SUB}/ss-all.txt"       2>&1 || true
  ps -eo user:20,pid,rss,args --sort=-rss | head -40 > "${SUB}/ps-rss.txt" 2>&1 || true
  free -h             > "${SUB}/free.txt"         2>&1 || true

  # Service state
  for unit in nginx apache2 httpd php8.3-fpm php-fpm; do
    if systemctl is-active --quiet "$unit" 2>/dev/null; then
      systemctl status "$unit" --no-pager -l > "${SUB}/systemctl-${unit}.txt" 2>&1 || true
    fi
  done

  # Logs — tails only; full logs are noise
  for f in /var/log/nginx/*.log /var/log/apache2/*.log /var/log/php*-fpm.log; do
    [ -r "$f" ] || continue
    tail -200 "$f" > "${SUB}/$(basename "$f")" 2>&1 || true
  done
  journalctl --since '15 min ago' --no-pager > "${SUB}/journal.log" 2>&1 || true
  dmesg -T 2>/dev/null | tail -100 > "${SUB}/dmesg.txt" || true

  # Running configuration, as actually loaded
  nginx -T > "${SUB}/nginx-dump.conf" 2>&1 || true
  (apache2ctl -S || apachectl -S) > "${SUB}/apache-vhosts.txt" 2>&1 || true

  echo "→ ${SUB}"
  echo
  echo "Reminder: sanitize before anything from here enters a committed lab entry."
  ;;

*)
  echo "unknown command: ${CMD}" >&2; exit 2 ;;
esac
