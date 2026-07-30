#!/usr/bin/env bash
# Proves audit-sanitize.sh can still FAIL. A gate that only ever passes is not a gate.
#
# Exists because a real bug shipped: grep omits the filename prefix when given exactly
# one file, so the field parse shifted and every pattern silently missed. The audit
# reported CLEAN on a file holding a production address and a real email — and
# single-file is precisely how pre-commit invokes it.
#
# NOTE ON CONSTRUCTION: the fixtures are ASSEMBLED at runtime, never written literally.
# A file containing a literal key header or plausible address is itself a finding, so a
# naive version of this script trips the audit, detect-private-key, and gitleaks all at
# once. Allowlisting it would blunt three gates to test one. Joining the pieces below
# keeps the committed file clean while the generated fixtures are genuinely bad.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 2

TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
sp=' '
octets=(10 42 7 99)
bad_ip="$(IFS=.; printf '%s' "${octets[*]}")"
bad_domain="$(printf '%s%s%s' realcorp . com)"
bad_email="$(printf '%s@%s' admin "$bad_domain")"
dashes="$(printf -- '-%.0s' 1 2 3 4 5)"
key_header="${dashes}BEGIN RSA PRIVATE${sp}KEY${dashes}"

printf 'production host %s\ncustomer domain %s\ncontact %s\n' \
  "$bad_ip" "$bad_domain" "$bad_email" > "$TMP/bad-identifiers.txt"
printf '%s\n' "$key_header" > "$TMP/bad-keymaterial.txt"

fails=0
for f in "$TMP/bad-identifiers.txt" "$TMP/bad-keymaterial.txt"; do
  if ./scripts/audit-sanitize.sh "$f" >/dev/null 2>&1; then
    printf 'FAIL: audit passed a file it must reject: %s\n' "$(basename "$f")"; fails=1
  fi
done

# Both together — the multi-file path parses grep output differently from single-file.
if ./scripts/audit-sanitize.sh "$TMP"/bad-*.txt >/dev/null 2>&1; then
  printf 'FAIL: audit passed multi-file known-bad input\n'; fails=1
fi

# Control: a file with only approved lab values must still PASS, or the audit is
# simply rejecting everything and the tests above prove nothing.
printf 'lab server 192.168.92.10 serving site-a.lab\n' > "$TMP/good.txt"
if ! ./scripts/audit-sanitize.sh "$TMP/good.txt" >/dev/null 2>&1; then
  printf 'FAIL: audit rejected a file containing only approved lab values\n'; fails=1
fi

[ "$fails" -eq 0 ] && { printf 'negative control PASS — audit rejects known-bad, accepts known-good\n'; exit 0; }
exit 1
