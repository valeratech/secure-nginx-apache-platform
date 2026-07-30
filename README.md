# secure-nginx-apache-platform

A hand-built nginx → Apache → PHP-FPM hosting stack, constructed in a private VMware
Workstation lab, plus a set of controlled-failure exercises that examine the request path,
proxy boundaries, trust model, and shared-hosting isolation.

## Why this exists

I administer an nginx-in-front-of-Apache stack through a control panel in production. That
gives me the operational context but not the underlying mechanics — the panel generates the
configuration and I operate the result. This project rebuilds the same architecture by hand
on a clean VM so I can examine the request flow, isolation boundaries, failure modes, and
configuration decisions the panel abstracts away.

The overlap with my production experience is not incidental; it is the premise. The most
distinctive part of the project is the comparison between the configuration I wrote by hand
and the configuration a control panel generates for an equivalent site, and the reasoning
about where and why they diverge.

This is a **de-abstraction project**. The lab is the work; the repository is the record.

## Safety boundaries

- Built entirely in an isolated VMware Workstation host-only network. No bridged adapter.
- Synthetic hostnames only (`site-a.lab`, `site-b.lab`) and disposable credentials.
- The control-panel comparison is performed against a **fresh trial installation** with
  synthetic domains, created for this purpose.
- No employer or production configuration, customer domain, real IP, license identifier,
  internal path layout, or custom template appears anywhere in this repository.
- Private keys and CA state are generated in the lab and never committed.
- Destructive tests (memory exhaustion, pool saturation) run only in this lab, only after
  a snapshot.

## Repository layout

```text
SCOPE.md                   locked release-one scope and explicit deferrals
ENVIRONMENT.md             lab topology, VM sizing, addressing, snapshot names
lab/                       break/fix exercises — the deliberate failures
reference/                 the clean authoritative configuration set
plesk-comparison/          hand-built vs panel-generated configuration, and why
scripts/validate.sh        stack assertions, positive and negative
scripts/capture.sh         live evidence capture per exercise
scripts/sync-from-lab.sh   pulls reference/ off the running VM — never hand-authored
scripts/audit-sanitize.sh  sensitive-content gate, tuned to this project's leak surface
scripts/lint-labs.sh       lab entry structure and status-table integrity
```

`reference/` is populated **only** by `sync-from-lab.sh`, never by typing configuration
into the repo. It claims to be what is actually running on the VM, and hand-authored
config stops being true within days.

## Commit gates

Four layers, described in the portfolio's `WORKFLOW.md`: redact at the source → custom
audit → pre-commit hooks → CI full-history gitleaks scan.

```bash
pre-commit install          # once
./scripts/audit-sanitize.sh # before staging anything
pre-commit run --all-files
```

`.audit-denylist` (gitignored) holds employer, customer, and production strings that must
never be committed — create it before the first real commit. A committed list of things
you must not commit would itself be the leak.

`reference/` is the prescriptive final state. `lab/` contains the mistakes. They are kept
separate on purpose.

## Method

Each exercise records a prediction before the fault is introduced, then compares it against
what actually happened. Incorrect predictions stay in the record — the gap between the
predicted and observed behavior is the learning, and editing it away would remove the only
interesting part.

Architecture documentation and the threat/control matrix are derived at the end, from what
was actually built and verified.

## Status

| Stage | State |
|---|---|
| 1. Server VM provisioned | |
| 2. Apache single-site baseline | |
| 3. Second vhost / default selection study | |
| 4. Return to clean single site | |
| 5. Apache moved to `127.0.0.1:8080` | |
| 6. nginx on the host-only edge | |
| 7. Client-IP restoration (RFC1918-correct) | |
| 8. Private CA + TLS termination at nginx | |
| 9. PHP-FPM and request-body limits | |
| 10. Second tenant + filesystem isolation proof | |
| 11. Panel comparison, one synthetic domain | |
| 12. Reference state + validation script | |

Break/fix progress is tracked in [lab/README.md](lab/README.md).
