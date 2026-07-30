# Break/fix labs

Controlled failures, one per file, written from [TEMPLATE.md](TEMPLATE.md). Each entry
records its prediction before the fault was introduced, and keeps that prediction unedited
even when it was wrong.

| # | Lab | Boundary | Status |
|---|---|---|---|
| 01 | Apache default VirtualHost selection | host selection | not started |
| 02 | Client identity: `TrustedProxy` vs `InternalProxy`, and XFF forgery | trust | not started |
| 03 | Apache-down 502 vs PHP-FPM-down 503, and error interception | proxy ownership | not started |
| 04 | Four-layer request-body limit mismatch | request-body enforcement | not started |
| 05 | Unknown Host rejection at the nginx edge | edge rejection | not started |

## What each one is for

**01 — default VirtualHost selection.** Omit `ServerName`, vary configuration load order,
send an unknown `Host` directly to Apache. Establishes how Apache selects a vhost from
address, port, and Host header, and why the first-loaded vhost becomes the default. Run
before nginx exists, so the behavior is attributable to Apache alone.

**02 — client identity.** Two failures in one boundary. First, `mod_remoteip` configured
with the wrong proxy trust class: `RemoteIPTrustedProxy` refuses to promote RFC1918
addresses, so a private-network lab client silently never appears in `%a` despite the module
being loaded and configured. Second, forge `X-Forwarded-For` from the client and observe
what reaches Apache under the appending form (`$proxy_add_x_forwarded_for`) versus the
replacing form (`$remote_addr`). The reference configuration replaces, because there is
exactly one proxy hop and no legitimate chain to preserve.

**03 — proxy ownership.** Stop PHP-FPM: Apache cannot reach its FastCGI backend and
generates a valid 503, which nginx passes through as a normal upstream response. Stop
Apache: nginx's own upstream connection fails and nginx generates 502, while Apache logs
nothing at all. Same symptom class, two codes, two logs, two components at fault. Then the
three-step interception sequence: `proxy_intercept_errors on` alone (no visible change,
because it needs a matching `error_page`), then with `error_page 503`, then with
`error_page 503 =200` — documented as a demonstration of what is possible, not a pattern to
ship, since returning success for a failed backend misleads monitoring and clients alike.

**04 — request-body limits.** Four controls, tested with each in turn as the smallest:
nginx `client_max_body_size`, Apache `LimitRequestBody`, PHP `post_max_size`, PHP
`upload_max_filesize`. The `post_max_size` case is the reason this lab exists — PHP can
discard the body, leave `$_POST` and `$_FILES` empty, and the application returns HTTP 200
with no error anywhere. Silent success with missing data is the failure that arrives as an
unreproducible ticket rather than a clean infrastructure error.

**05 — unknown Host.** A catch-all `default_server` returning 444, verified adversarially
rather than assumed safe because `server_name` is set. Includes the SNI-versus-Host
distinction over TLS, and confirmation that no application content leaks through the
catch-all.
