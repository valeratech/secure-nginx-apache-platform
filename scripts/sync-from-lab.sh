#!/usr/bin/env bash
#
# sync-from-lab.sh — pull configuration off the running VM into reference/.
#
# WHY THIS EXISTS INSTEAD OF HAND-AUTHORING:
# reference/ claims to be the configuration that is actually running. Hand-written config
# drifts from the box within days and the claim silently becomes false. Everything in
# reference/ therefore arrives by copying it off the VM, never by typing it into the repo.
#
# Prose and lab writeups follow the ordinary author → archive → extract flow.
# Configuration follows this one.
#
# Usage:
#   ./sync-from-lab.sh fetch      package config on the VM, transfer, verify checksums
#   ./sync-from-lab.sh diff       show what changed vs. the committed reference/
#   ./sync-from-lab.sh apply      copy staged files into reference/ (after reviewing diff)
#
# Requires SSH access to the lab VM over the host-only network.

set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

LAB_HOST="${LAB_HOST:-192.168.175.10}"
LAB_USER="${LAB_USER:-labadmin}"
STAGING="${ROOT}/.sync-staging"

RED=$'\033[31m'; GRN=$'\033[32m'; DIM=$'\033[2m'; RST=$'\033[0m'

case "${1:-}" in

fetch)
  mkdir -p "$STAGING"
  echo "Packaging configuration on ${LAB_USER}@${LAB_HOST}"

  # Package on the VM. nginx -T dumps the fully-resolved config including all includes,
  # which is what should be reviewed — not the fragment files in isolation.
  ssh "${LAB_USER}@${LAB_HOST}" 'sudo bash -s' <<'REMOTE'
set -e
TMP=$(mktemp -d)
mkdir -p "$TMP"/{nginx,apache,php-fpm,systemd}
cp -a /etc/nginx/nginx.conf /etc/nginx/conf.d/. "$TMP/nginx/" 2>/dev/null || true
cp -a /etc/nginx/sites-available/. "$TMP/nginx/sites-available/" 2>/dev/null || true
nginx -T > "$TMP/nginx/RESOLVED-nginx-T.conf" 2>/dev/null || true
cp -a /etc/apache2/apache2.conf /etc/apache2/ports.conf "$TMP/apache/" 2>/dev/null || true
cp -a /etc/apache2/sites-available/. "$TMP/apache/sites-available/" 2>/dev/null || true
cp -a /etc/apache2/conf-available/. "$TMP/apache/conf-available/" 2>/dev/null || true
(apache2ctl -S || apachectl -S) > "$TMP/apache/RESOLVED-vhosts.txt" 2>&1 || true
cp -a /etc/php/*/fpm/pool.d/. "$TMP/php-fpm/" 2>/dev/null || true
cp -a /etc/php/*/fpm/php.ini "$TMP/php-fpm/" 2>/dev/null || true
# Never package key material.
find "$TMP" -name '*.key' -o -name '*-key.pem' -delete 2>/dev/null || true
tar czf /tmp/lab-config.tar.gz -C "$TMP" .
sha256sum /tmp/lab-config.tar.gz | cut -c1-16
rm -rf "$TMP"
REMOTE

  REMOTE_SUM=$(ssh "${LAB_USER}@${LAB_HOST}" 'sha256sum /tmp/lab-config.tar.gz' | cut -c1-16)
  scp -q "${LAB_USER}@${LAB_HOST}:/tmp/lab-config.tar.gz" "$STAGING/"
  LOCAL_SUM=$(sha256sum "$STAGING/lab-config.tar.gz" | cut -c1-16)

  printf 'remote %s\nlocal  %s\n' "$REMOTE_SUM" "$LOCAL_SUM"
  if [ "$REMOTE_SUM" != "$LOCAL_SUM" ]; then
    printf '%schecksum mismatch — transfer is not byte-identical, stopping%s\n' "$RED" "$RST"
    exit 1
  fi
  printf '%schecksum ok%s\n' "$GRN" "$RST"

  rm -rf "${STAGING:?}/extracted"; mkdir -p "$STAGING/extracted"
  tar xzf "$STAGING/lab-config.tar.gz" -C "$STAGING/extracted"
  ssh "${LAB_USER}@${LAB_HOST}" 'rm -f /tmp/lab-config.tar.gz'

  echo
  echo "Auditing extracted configuration before it goes anywhere near reference/"
  mapfile -t EXTRACTED < <(find "$STAGING/extracted" -type f)
  "${ROOT}/scripts/audit-sanitize.sh" "${EXTRACTED[@]}" || {
    printf '%saudit failed — redact on the VM, not in the repo, then re-fetch%s\n' "$RED" "$RST"
    exit 1
  }
  echo "→ ${STAGING}/extracted   (review, then: $0 diff)"
  ;;

diff)
  [ -d "$STAGING/extracted" ] || { echo "nothing fetched — run: $0 fetch"; exit 1; }
  diff -ruN --color=always reference/ "$STAGING/extracted/" || true
  printf '\n%sReview above. Anything unexpected is either drift on the VM or an\n' "$DIM"
  printf 'undocumented change — resolve it before applying.%s\n' "$RST"
  ;;

apply)
  [ -d "$STAGING/extracted" ] || { echo "nothing fetched — run: $0 fetch"; exit 1; }
  rsync -a --delete "$STAGING/extracted/" reference/
  # Restore the directory notes the sync would otherwise wipe.
  for d in nginx apache php-fpm tls; do
    [ -d "reference/$d" ] || mkdir -p "reference/$d"
  done
  echo "reference/ updated from ${LAB_HOST}"
  echo "Next: annotate changed directives (threat / verification), then run pre-commit."
  ;;

*)
  sed -n '3,22p' "$0" | sed 's/^# \?//'
  exit 2 ;;
esac
