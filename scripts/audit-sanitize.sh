#!/usr/bin/env bash
#
# audit-sanitize.sh — project-tuned sensitive-content audit.
#
# gitleaks catches secret SHAPES (keys, tokens). This catches the things that actually
# leak from an infrastructure lab documented by someone with a production job:
# employer identifiers, customer domains, production addressing, license keys, internal
# path layouts, and host-machine details.
#
# Matches are CLASSIFIED, not just listed — approved lab placeholders pass silently, and
# only genuinely undecided items are surfaced for a human call.
#
# Usage:
#   ./audit-sanitize.sh              audit tracked + staged files
#   ./audit-sanitize.sh --all        audit every file in the working tree
#   ./audit-sanitize.sh <paths...>   audit specific paths
#
# Exit 0 = CLEAN. Exit 1 = decisions required. Exit 2 = usage error.

set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 2

# ----------------------------------------------------------------------------------------
# Approved placeholders — the lab's own values. Edit to match ENVIRONMENT.md.
# ----------------------------------------------------------------------------------------
LAB_SUBNET_RE='192\.168\.(92|175)\.[0-9]{1,3}'

# Address literals that are never a leak: loopback, the lab subnet, link-local,
# RFC 5737 documentation ranges, wildcards and netmasks.
# NOTE: other RFC1918 space (10.x, 172.16-31.x, other 192.168.x) is deliberately NOT
# auto-approved — a stray 10.x is exactly what a production paste looks like.
IP_OK_RE="^(127\.[0-9.]+|${LAB_SUBNET_RE}|169\.254\.[0-9.]+|192\.0\.2\.[0-9]+|198\.51\.100\.[0-9]+|203\.0\.113\.[0-9]+|0\.0\.0\.0|255\.[0-9.]+|8\.8\.8\.8)$"  # audit-ok

# Domains that legitimately appear in technical documentation.
DOMAIN_OK_RE='(\.lab|\.invalid|\.test|\.local|\.example|example\.(com|org|net)|httpd\.apache\.org|apache\.org|nginx\.org|nginx\.com|php\.net|mozilla\.org|wiki\.mozilla\.org|letsencrypt\.org|github\.com|githubusercontent\.com|ubuntu\.com|debian\.org|openssl\.org|kernel\.org|ietf\.org|rfc-editor\.org|cloudlinux\.com|plesk\.com|testssl\.sh|owasp\.org)$'

# Committed allowlist of extra approved strings, one per line (optional).
ALLOWFILE="${ROOT}/.audit-allow"

# GITIGNORED denylist: employer, customer, and production strings that must never appear.
# Keeping it out of git is the point — the denylist itself would be a leak.
DENYFILE="${ROOT}/.audit-denylist"

# ----------------------------------------------------------------------------------------
RED=$'\033[31m'; YEL=$'\033[33m'; GRN=$'\033[32m'; DIM=$'\033[2m'; RST=$'\033[0m'
FINDINGS=0

report() { # report <severity> <class> <file:line> <detail>
  local sev="$1" cls="$2" loc="$3" det="$4" col="$YEL"
  [ "$sev" = HIGH ] && col="$RED"
  printf '%s  %-4s%s  %-22s %s\n' "$col" "$sev" "$RST" "$cls" "$loc"
  printf '        %s%s%s\n' "$DIM" "$det" "$RST"
  FINDINGS=$((FINDINGS+1))
}

allowed() { # allowed <string> — true if listed in .audit-allow
  [ -r "$ALLOWFILE" ] || return 1
  grep -qxF -- "$1" "$ALLOWFILE" 2>/dev/null
}

# ----------------------------------------------------------------------------------------
# Build the file list
# ----------------------------------------------------------------------------------------
case "${1:-}" in
  --all) mapfile -t FILES < <(git ls-files 2>/dev/null || find . -type f -not -path './.git/*') ;;
  "")    if git rev-parse --git-dir >/dev/null 2>&1; then
           mapfile -t FILES < <( { git ls-files; git diff --cached --name-only; } 2>/dev/null | sort -u )
         else
           printf '%snot a git repository — auditing the whole working tree%s\n' "$YEL" "$RST"
           mapfile -t FILES < <(find . -type f -not -path './.git/*')
         fi ;;
  -h|--help) sed -n '3,20p' "$0" | sed 's/^# \?//'; exit 2 ;;
  *)     FILES=("$@") ;;
esac

# Drop deleted paths and binaries
KEEP=()
for f in "${FILES[@]}"; do
  [ -f "$f" ] || continue
  if file -b --mime "$f" 2>/dev/null | grep -q 'charset=binary'; then
    report HIGH "binary-committed" "$f" "binary files carry metadata and are blocked by policy — see WORKFLOW.md"
    continue
  fi
  KEEP+=("$f")
done
FILES=("${KEEP[@]}")

# An empty file list is a failure, not a pass. A gate that reports CLEAN after
# checking nothing is worse than no gate — it teaches misplaced trust.
[ ${#FILES[@]} -eq 0 ] && { printf '%sERROR%s — no files matched; refusing to report CLEAN\n' "$RED" "$RST"; exit 2; }

printf 'Auditing %d files\n\n' "${#FILES[@]}"

# ----------------------------------------------------------------------------------------
# 1. Denylist — employer / customer / production strings (highest severity)
# ----------------------------------------------------------------------------------------
if [ -r "$DENYFILE" ]; then
  while IFS= read -r term; do
    [ -z "$term" ] && continue
    case "$term" in \#*) continue ;; esac
    while IFS=: read -r f n _; do
      [ -n "${f:-}" ] && report HIGH "denylisted-term" "${f}:${n}" "matched a term from .audit-denylist (term not echoed here by design)"
    done < <(grep -rHInF -- "$term" "${FILES[@]}" 2>/dev/null | grep -v 'audit-ok')
  done < "$DENYFILE"
else
  printf '%s  note%s  no .audit-denylist present — create one (gitignored) listing employer,\n' "$YEL" "$RST"
  printf '        customer, and production strings that must never be committed.\n\n'
fi

# ----------------------------------------------------------------------------------------
# 2. Network addressing
# ----------------------------------------------------------------------------------------
while IFS=: read -r f n rest; do
  [ -z "${f:-}" ] && continue
  for ip in $(grep -oE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' <<<"$rest" | sort -u); do
    [[ "$ip" =~ $IP_OK_RE ]] && continue
    allowed "$ip" && continue
    # Version-like strings can look like addresses; they still surface for a decision.
    report HIGH "unapproved-ip" "${f}:${n}" "$ip — approved: loopback, ${LAB_SUBNET_RE}, RFC5737 doc ranges"
  done
done < <(grep -rHInE '\b([0-9]{1,3}\.){3}[0-9]{1,3}\b' "${FILES[@]}" 2>/dev/null | grep -v 'audit-ok')

# ----------------------------------------------------------------------------------------
# 3. Hostnames and domains
# ----------------------------------------------------------------------------------------
while IFS=: read -r f n rest; do
  [ -z "${f:-}" ] && continue
  for d in $(grep -oiE '\b([a-z0-9](-?[a-z0-9])*\.)+[a-z]{2,24}\b' <<<"$rest" | tr '[:upper:]' '[:lower:]' | sort -u); do
    [[ "$d" =~ $DOMAIN_OK_RE ]] && continue
    allowed "$d" && continue
    # Ignore obvious filenames (script.sh, config.d, README.md)
    [[ "$d" =~ \.(sh|md|conf|d|log|txt|yml|yaml|json|png|jpg|php|css|js|crt|pem|key|toml|ini|gz|tar|py|sql|csv|html|tpl)$ ]] && continue
    # systemd units and similar dotted non-hostnames
    [[ "$d" =~ \.(service|socket|target|timer|mount|slice|device|path|swap)$ ]] && continue
    report HIGH "unapproved-domain" "${f}:${n}" "$d — lab hosts must be *.lab; docs use example.com / *.invalid"
  done
done < <(grep -rHInE '\b([a-zA-Z0-9](-?[a-zA-Z0-9])*\.)+[a-zA-Z]{2,24}\b' "${FILES[@]}" 2>/dev/null | grep -v 'audit-ok')

# ----------------------------------------------------------------------------------------
# 4. Credentials and key material
# ----------------------------------------------------------------------------------------
while IFS=: read -r f n _; do
  [ -n "${f:-}" ] && report HIGH "private-key" "${f}:${n}" "PEM private key block — CA and leaf keys never leave the lab"
done < <(grep -rHIn -- '-----BEGIN .*PRIVATE KEY-----' "${FILES[@]}" 2>/dev/null | grep -v 'audit-ok') # audit-ok

while IFS=: read -r f n rest; do
  [ -n "${f:-}" ] && report HIGH "license-key" "${f}:${n}" "$(cut -c1-60 <<<"$rest")"
done < <(grep -rHInE '\b(PLSK|CLN)\.[A-Z0-9]{6,}' "${FILES[@]}" 2>/dev/null | grep -v 'audit-ok')

while IFS=: read -r f n rest; do
  [ -n "${f:-}" ] && report HIGH "credential-literal" "${f}:${n}" "$(cut -c1-60 <<<"$rest")"
done < <(grep -rHInE "(password|passwd|secret|api[_-]?key|token|DB_PASSWORD)[[:space:]]*[:=][[:space:]]*['\"]?[A-Za-z0-9!@#\$%^&*_+-]{8,}" "${FILES[@]}" 2>/dev/null | grep -viE '(changeme|placeholder|example|redacted|<[a-z-]+>|\$\{|xxxx|your-)' | grep -v 'audit-ok')

# ----------------------------------------------------------------------------------------
# 5. Host machine and hypervisor identifiers
# ----------------------------------------------------------------------------------------
while IFS=: read -r f n rest; do
  [ -n "${f:-}" ] && report WARN "mac-address" "${f}:${n}" "$(grep -oE '([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}' <<<"$rest" | head -1)"
done < <(grep -rHInE '\b([0-9a-fA-F]{2}:){5}[0-9a-fA-F]{2}\b' "${FILES[@]}" 2>/dev/null | grep -v 'audit-ok')

while IFS=: read -r f n rest; do
  [ -n "${f:-}" ] && report WARN "vmware-identifier" "${f}:${n}" "$(cut -c1-60 <<<"$rest")"
done < <(grep -rHInE '\.(vmx|vmdk|nvram|vmsn)\b|vmware-[0-9]+\.log' "${FILES[@]}" 2>/dev/null | grep -v 'audit-ok')

while IFS=: read -r f n rest; do
  [ -n "${f:-}" ] && report WARN "absolute-home-path" "${f}:${n}" "$(grep -oE '(/home/|/Users/|C:\\Users\\)[A-Za-z0-9._-]+' <<<"$rest" | head -1)"
done < <(grep -rHInE '(/home/|/Users/|C:\\Users\\)[A-Za-z0-9._-]+' "${FILES[@]}" 2>/dev/null | grep -viE '/home/(user|lab|site-[ab])\b' | grep -v 'audit-ok')

# ----------------------------------------------------------------------------------------
# 6. Personal data
# ----------------------------------------------------------------------------------------
while IFS=: read -r f n rest; do
  [ -z "${f:-}" ] && continue
  for e in $(grep -oiE '[a-z0-9._%+-]+@[a-z0-9.-]+\.[a-z]{2,}' <<<"$rest" | sort -u); do
    [[ "$e" =~ (\.lab|\.invalid|example\.(com|org))$ ]] && continue
    allowed "$e" && continue
    report HIGH "email-address" "${f}:${n}" "$e"
  done
done < <(grep -rHInE '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}' "${FILES[@]}" 2>/dev/null | grep -v 'audit-ok')

# ----------------------------------------------------------------------------------------
printf '\n'
if [ "$FINDINGS" -eq 0 ]; then
  printf '%sCLEAN%s — no items requiring a decision\n' "$GRN" "$RST"
  exit 0
fi
printf '%s%d item(s) require a decision.%s\n' "$RED" "$FINDINGS" "$RST"
printf 'Redact at the source, or add a deliberate approval to .audit-allow with a reason.\n'
exit 1
