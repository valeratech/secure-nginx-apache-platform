# Scope — release one

Locked. Anything not listed under "In scope" is deferred, including good ideas. The primary
risk to this project is scope, not relevance.

## In scope

**Build stages**

1. Provision the small server VM (2 vCPU / 2 GB / thin 20–30 GB).
2. Apache installed, one site, one explicit VirtualHost, own logs.
3. Second VirtualHost introduced temporarily to study default selection.
4. Return to the clean single-site state.
5. Apache moved to `Listen 127.0.0.1:8080`.
6. nginx placed on the host-only edge, bound to an explicit address.
7. Client-IP restoration configured correctly for a private-network client.
8. Two-tier private CA built; TLS terminated at nginx.
9. PHP-FPM configured; request-body limits set coherently across all four layers.
10. Minimal second tenant: separate Unix user, separate pool, cross-read denial proved.
11. One synthetic domain compared against a fresh control-panel trial installation.
12. Clean reference configuration plus `scripts/validate.sh`.

**Five break/fix labs**

| # | Lab | Boundary it exercises |
|---|---|---|
| 01 | Apache default VirtualHost selection | host selection |
| 02 | `RemoteIPTrustedProxy` vs `RemoteIPInternalProxy`; XFF forgery and replacement | trust |
| 03 | Apache-down 502 vs PHP-FPM-down 503, plus three-step `proxy_intercept_errors` | proxy ownership |
| 04 | Four-layer request-body limit mismatch | request-body enforcement |
| 05 | Unknown Host rejection via nginx catch-all `default_server` | edge rejection |

Tenant isolation is a focused verification case (stage 10), not a sixth lab.

## Explicitly deferred

Release two or later. Not blockers for a complete, publishable release one.

- Full multi-tenant implementation: permissions matrix, `open_basedir` layering, writable
  and session/temp directory isolation, per-tenant resource accounting, CageFS comparison
- PHP-FPM capacity calculation and the OOM exercise (VM is provisioned to support it)
- Upstream keepalive analysis (`upstream` + `proxy_http_version 1.1`, loopback packet capture)
- HTTP/2, compression, caching
- Rate limiting on authentication paths
- Real application deployment and a genuinely validated CSP
- PROXY protocol as a standalone comparison against HTTP forwarding headers
- Full panel template analysis beyond the single synthetic domain
- Diagrams, `ARCHITECTURE.md`, threat/control matrix — **derived after the build**
- Any automated test framework or CI beyond `scripts/validate.sh`

## Done criteria for release one

- Twelve stages complete, each with a matching snapshot and stage-boundary commit.
- Five lab entries written from captured evidence, predictions intact including wrong ones.
- `reference/` reflects the actual running configuration, every non-obvious directive
  annotated with what it mitigates and how that was verified.
- `validate.sh` passes on a fresh revert to the final snapshot, including its negative
  assertions.
- Panel comparison table complete for one synthetic domain.
- `ARCHITECTURE.md` and the threat/control matrix derived from the above.

## Verification standard

`nginx -t` and `apachectl configtest` prove the configuration parsed. They do not prove a
mitigation works. Syntax checks belong in `validate.sh`; the threat documentation requires
the attack demonstrated failing — a forged Host header rejected, a directory request
returning 403, a cross-tenant read denied by the kernel, a banner grab showing nothing.
