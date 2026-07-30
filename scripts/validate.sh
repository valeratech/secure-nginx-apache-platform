#!/usr/bin/env bash
#
# validate.sh — release-one validation for the secure nginx/Apache platform lab.
#
# Deliberately one script, not a test framework. Syntax checks prove the config parsed;
# the assertions that matter are the negative ones — that Apache is NOT reachable, that an
# unknown Host is NOT served, that a tenant CANNOT read another tenant's files.
#
# Usage:
#   ./validate.sh server     run on the web platform VM (default)
#   ./validate.sh client     run on the client VM
#
# Exits non-zero if any check fails.

set -uo pipefail

# ----------------------------------------------------------------------------------------
# Lab configuration — update to match ENVIRONMENT.md
# ----------------------------------------------------------------------------------------
SERVER_IP="192.168.92.10"
CLIENT_IP="192.168.92.20"
SITE_A="site-a.lab"
SITE_B="site-b.lab"
APACHE_BACKEND_PORT="8080"
CA_BUNDLE="/usr/local/share/ca-certificates/lab-root-ca.crt"

# Paths — adjust for the distribution in use (Debian/Ubuntu layout assumed)
APACHE_ACCESS_LOG="/var/log/apache2/${SITE_A}.access.log"
STATIC_ASSET="/static/lab.css"
DYNAMIC_PATH="/index.php"

ROLE="${1:-server}"

# ----------------------------------------------------------------------------------------
# Harness
# ----------------------------------------------------------------------------------------
PASS=0; FAIL=0; SKIP=0
GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; DIM=$'\033[2m'; RESET=$'\033[0m'

pass() { printf '%s  PASS%s  %s\n' "$GREEN" "$RESET" "$1"; PASS=$((PASS+1)); }
fail() { printf '%s  FAIL%s  %s\n' "$RED" "$RESET" "$1"; [ $# -gt 1 ] && printf '%s        %s%s\n' "$DIM" "$2" "$RESET"; FAIL=$((FAIL+1)); }
skip() { printf '%s  SKIP%s  %s\n' "$YELLOW" "$RESET" "$1"; SKIP=$((SKIP+1)); }
section() { printf '\n%s\n' "$1"; printf '%s\n' "$(printf '%*s' "${#1}" '' | tr ' ' '-')"; }
have()  { command -v "$1" >/dev/null 2>&1; }

# curl helper: prints status code, pins resolution so DNS is never a variable
code() {  # code <host> <scheme> <path> [extra curl args...]
  local host="$1" scheme="$2" path="$3"; shift 3
  local port=80; [ "$scheme" = https ] && port=443
  curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
       --resolve "${host}:${port}:${SERVER_IP}" \
       ${CA_BUNDLE:+--cacert "$CA_BUNDLE"} \
       "$@" "${scheme}://${host}${path}" 2>/dev/null
}

# ----------------------------------------------------------------------------------------
# Server-side checks
# ----------------------------------------------------------------------------------------
server_checks() {

  section "Configuration syntax"

  if nginx -t >/dev/null 2>&1; then pass "nginx -t"; else fail "nginx -t" "$(nginx -t 2>&1 | tail -2)"; fi

  local apachectl=apachectl; have apache2ctl && apachectl=apache2ctl
  if $apachectl configtest >/dev/null 2>&1; then pass "$apachectl configtest"
  else fail "$apachectl configtest" "$($apachectl configtest 2>&1 | tail -2)"; fi

  section "Listener scope"

  local listeners; listeners="$(ss -ltnH 2>/dev/null)"

  if grep -qE "(^|[[:space:]])${SERVER_IP}:80([[:space:]]|$)" <<<"$listeners"; then
    pass "nginx listening on ${SERVER_IP}:80"
  else fail "nginx listening on ${SERVER_IP}:80"; fi

  if grep -qE "(^|[[:space:]])${SERVER_IP}:443([[:space:]]|$)" <<<"$listeners"; then
    pass "nginx listening on ${SERVER_IP}:443"
  else fail "nginx listening on ${SERVER_IP}:443"; fi

  # Negative: nginx must not be bound to every interface (the NAT adapter stays attached)
  if grep -qE '(0\.0\.0\.0|\*):(80|443)([[:space:]]|$)' <<<"$listeners"; then
    fail "nginx is bound to all interfaces" "explicit listen <address> expected; see ENVIRONMENT.md"
  else pass "nginx not bound to all interfaces"; fi

  # Negative: Apache is loopback-only
  if grep -qE "(^|[[:space:]])127\.0\.0\.1:${APACHE_BACKEND_PORT}([[:space:]]|$)" <<<"$listeners"; then
    pass "Apache listening on 127.0.0.1:${APACHE_BACKEND_PORT}"
  else fail "Apache listening on 127.0.0.1:${APACHE_BACKEND_PORT}"; fi

  if grep -qE "(0\.0\.0\.0|\*|${SERVER_IP}):${APACHE_BACKEND_PORT}([[:space:]]|$)" <<<"$listeners"; then
    fail "Apache is reachable off-loopback on :${APACHE_BACKEND_PORT}" "must be 127.0.0.1 only"
  else pass "Apache not bound off-loopback"; fi

  section "Information disclosure"

  local hdrs; hdrs="$(curl -sI --max-time 5 "http://127.0.0.1:${APACHE_BACKEND_PORT}/" 2>/dev/null)"
  if grep -qiE '^server:.*apache/[0-9]' <<<"$hdrs"; then
    fail "Apache leaks its version" "ServerTokens Prod expected"
  else pass "Apache Server header carries no version"; fi

  if grep -qiE '^server:.*nginx/[0-9]' <<<"$(curl -sI --max-time 5 "http://${SERVER_IP}/" 2>/dev/null)"; then
    fail "nginx leaks its version" "server_tokens off expected"
  else pass "nginx Server header carries no version"; fi

  section "Client identity in backend logs"

  # After a request from the client VM, Apache must log the client address, not loopback.
  if [ -r "$APACHE_ACCESS_LOG" ]; then
    if tail -50 "$APACHE_ACCESS_LOG" | grep -q "^${CLIENT_IP}"; then
      pass "Apache logs the real client address (%a)"
    elif tail -50 "$APACHE_ACCESS_LOG" | grep -q '^127\.0\.0\.1'; then
      fail "Apache is logging the proxy peer, not the client" \
           "check RemoteIPInternalProxy (not TrustedProxy — it rejects RFC1918) and %a in LogFormat"
    else
      skip "no recent client requests in $APACHE_ACCESS_LOG — generate traffic first"
    fi
  else skip "Apache access log not readable at $APACHE_ACCESS_LOG"; fi

  section "Tenant isolation"

  local a_user="${SITE_A%%.*}" b_user="${SITE_B%%.*}"
  local b_secret="/srv/www/${SITE_B}/private/secret.txt"

  if id "$a_user" >/dev/null 2>&1 && [ -e "$b_secret" ]; then
    if sudo -n -u "$a_user" cat "$b_secret" >/dev/null 2>&1; then
      fail "tenant ${a_user} can read ${b_secret}" "kernel-level denial expected"
    else pass "tenant ${a_user} denied read of ${b_user} private file"; fi
  else skip "second tenant not yet built (stage 10)"; fi

  # Pools must run as distinct identities, not all as www-data
  if have php-fpm8.3 || have php-fpm; then
    local pool_users; pool_users="$(ps -eo user:20,args | awk '/php-fpm: pool/ {print $1}' | sort -u | tr '\n' ' ')"
    if [ -n "${pool_users// /}" ]; then
      printf '%s        pool identities: %s%s\n' "$DIM" "$pool_users" "$RESET"
      if grep -qw 'www-data' <<<"$pool_users" && [ "$(wc -w <<<"$pool_users")" -eq 1 ]; then
        skip "all pools share one identity — expected until stage 10"
      else pass "PHP-FPM pools run under distinct identities"; fi
    else skip "no PHP-FPM pool workers running"; fi
  else skip "PHP-FPM not installed yet"; fi
}

# ----------------------------------------------------------------------------------------
# Client-side checks — the adversarial ones belong here, off-box
# ----------------------------------------------------------------------------------------
client_checks() {

  section "Backend must not be reachable from the client"

  if timeout 3 bash -c "cat < /dev/null > /dev/tcp/${SERVER_IP}/${APACHE_BACKEND_PORT}" 2>/dev/null; then
    fail "Apache :${APACHE_BACKEND_PORT} is reachable from the client VM" "must be loopback-only"
  else pass "Apache :${APACHE_BACKEND_PORT} refused from the client VM"; fi

  section "Known host"

  local c
  c="$(code "$SITE_A" https "$DYNAMIC_PATH")"
  if [ "$c" = 200 ]; then pass "https://${SITE_A}${DYNAMIC_PATH} → 200"
  else fail "https://${SITE_A}${DYNAMIC_PATH} → ${c} (expected 200)"; fi

  c="$(code "$SITE_A" https "$STATIC_ASSET")"
  if [ "$c" = 200 ]; then pass "static asset ${STATIC_ASSET} → 200"
  else fail "static asset ${STATIC_ASSET} → ${c} (expected 200)"; fi

  section "HTTP to HTTPS redirect"

  c="$(code "$SITE_A" http "/")"
  if [[ "$c" =~ ^30[18]$ ]]; then pass "http://${SITE_A}/ → ${c}"
  else fail "http://${SITE_A}/ → ${c} (expected 301/308)"; fi

  # Negative: the redirect must not loop. --max-redirs trips at a loop.
  if curl -s -o /dev/null --max-time 8 --max-redirs 5 -L \
        --resolve "${SITE_A}:80:${SERVER_IP}" --resolve "${SITE_A}:443:${SERVER_IP}" \
        ${CA_BUNDLE:+--cacert "$CA_BUNDLE"} "http://${SITE_A}/" 2>/dev/null; then
    pass "redirect chain terminates (no loop)"
  else fail "redirect chain did not terminate" "check X-Forwarded-Proto handling and which component owns the redirect"; fi

  section "Unknown Host rejection"

  # A 444 closes the connection with no response: curl reports exit 52 / code 000.
  local out rc
  out="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
         -H 'Host: attacker.invalid' "http://${SERVER_IP}/" 2>/dev/null)"; rc=$?
  if [ "$rc" -eq 52 ] || [ "$out" = "000" ]; then
    pass "unknown Host closed by default_server (curl exit ${rc})"
  elif [ "$out" = "421" ] || [ "$out" = "404" ] || [ "$out" = "403" ]; then
    pass "unknown Host rejected with ${out}"
  else
    fail "unknown Host returned ${out}" "catch-all default_server expected to reject"
  fi

  # And it must not serve site A's content
  if curl -s --max-time 5 -H "Host: attacker.invalid" "http://${SERVER_IP}/" 2>/dev/null | grep -qi "$SITE_A"; then
    fail "unknown Host leaked ${SITE_A} content"
  else pass "unknown Host leaks no application content"; fi

  section "TLS"

  if have openssl; then
    local s_client
    s_client="$(echo | openssl s_client -connect "${SERVER_IP}:443" -servername "$SITE_A" \
                ${CA_BUNDLE:+-CAfile "$CA_BUNDLE"} 2>/dev/null)"
    if grep -q 'Verify return code: 0 (ok)' <<<"$s_client"; then
      pass "chain verifies against the lab root CA"
    else
      fail "chain does not verify" "nginx must be served leaf + intermediate, not the bare leaf"
    fi

    if grep -qE 'DNS:'"${SITE_A//./\\.}" <<<"$(openssl x509 -noout -text 2>/dev/null <<<"$s_client")"; then
      pass "leaf carries subjectAltName for ${SITE_A}"
    else fail "leaf missing SAN for ${SITE_A}" "CN is ignored for hostname matching by modern clients"; fi
  else skip "openssl not installed"; fi

  section "Directory listing"

  c="$(code "$SITE_A" https "/static/")"
  if [ "$c" = 403 ] || [ "$c" = 404 ]; then pass "directory request → ${c} (no listing)"
  elif [ "$c" = 200 ]; then fail "directory request → 200" "Options -Indexes / autoindex off expected"
  else skip "directory request → ${c}"; fi
}

# ----------------------------------------------------------------------------------------
printf 'Lab validation — role: %s, server: %s\n' "$ROLE" "$SERVER_IP"

case "$ROLE" in
  server) server_checks ;;
  client) client_checks ;;
  *) printf 'usage: %s [server|client]\n' "$0" >&2; exit 2 ;;
esac

printf '\n%d passed, %d failed, %d skipped\n' "$PASS" "$FAIL" "$SKIP"
[ "$FAIL" -eq 0 ]
