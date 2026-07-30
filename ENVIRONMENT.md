# Lab environment

Private VMware Workstation lab. Two VMs on an isolated host-only network.

> Addresses below are placeholders — replace with the actual lab values once the vmnet is
> configured, and keep them consistent across `reference/`, `scripts/validate.sh`, and every
> lab entry.

## Topology

```text
                VMware Workstation host-only network (vmnetN)

        ┌──────────────────────────┐        ┌──────────────────────────────┐
        │ Client VM                │        │ Web Platform VM              │
        │ 192.168.92.20            │───────▶│ 192.168.92.10                │
        │ .21 (alias, IP testing)  │        │                              │
        │                          │        │ nginx  192.168.92.10:80,:443 │
        │ curl, openssl            │        │ Apache 127.0.0.1:8080        │
        │ testssl.sh               │        │ PHP-FPM  unix socket         │
        │ browser, load tools      │        │ site-a.lab, site-b.lab       │
        │ lab root CA in trust     │        │                              │
        └──────────────────────────┘        └──────────────────────────────┘
```

Request path: `Client → nginx (TLS terminated) → Apache over loopback HTTP → PHP-FPM over
unix socket → application`.

## VM sizing

| | Server | Client |
|---|---|---|
| vCPU | 2 | 2 |
| RAM | **2 GB** | 2 GB |
| Disk | 20–30 GB thin | 20 GB thin |

The 2 GB allocation on the server is deliberate, not a constraint. On an oversized VM,
PHP-FPM pool exhaustion is hard to reach with synthetic load, memory arithmetic is
theoretical, and OOM behavior never materializes. At 2 GB the ceiling is reachable and the
measured-RSS calculation is real.

## Network adapters

Both VMs keep **two adapters permanently attached**:

- **Host-only** — all lab traffic between client and server.
- **NAT** — package installation and updates.

Adapters are not attached and detached between exercises; that changes what is present at
boot and silently invalidates assumptions between labs. Instead, services are bound
explicitly, so listener scope is part of the architecture rather than a consequence of an
unplugged virtual cable:

```nginx
listen 192.168.92.10:80;
listen 192.168.92.10:443 ssl;
```

```apache
Listen 127.0.0.1:8080
```

### Addressing must be static

Two reasons:

1. VMware's host-only DHCP will eventually hand out a different address, breaking
   `/etc/hosts`, the certificate SANs' associated expectations, and the validation script.
2. nginx with an explicit `listen <address>` **fails to start** if that address is not yet
   configured — a bind error, not a warning.

Configure a static address (netplan or distribution equivalent) outside the vmnet DHCP pool,
or disable DHCP on the vmnet entirely. If a boot-time race still appears, the correct fix is
unit ordering (`After=network-online.target`), not `net.ipv4.ip_nonlocal_bind`.

## Name resolution

`/etc/hosts` on the client is sufficient:

```text
192.168.92.10   site-a.lab
192.168.92.10   site-b.lab
```

For adversarial Host testing, control resolution and the Host header independently so that
"nginx rejected the Host" is never confused with "the name did not resolve":

```bash
curl --resolve site-a.lab:443:192.168.92.10 https://site-a.lab/
curl -H 'Host: attacker.invalid' http://192.168.92.10/
```

Note that over TLS, SNI selection happens before the encrypted HTTP `Host` header is
processed — the two can disagree, and that distinction belongs in the lab notes.

## Diagnostic endpoint

A minimal header-echo page is built early (stage 2, alongside the first vhost) because it
makes the client-IP and forwarded-protocol work visible from the client rather than only in
server logs:

```php
<?php
foreach (['REMOTE_ADDR','HTTP_X_FORWARDED_FOR','HTTP_X_FORWARDED_PROTO','HTTP_HOST'] as $k) {
    printf("%s=%s\n", $k, $_SERVER[$k] ?? '(unset)');
}
```

Not `phpinfo()`. In the reference state this endpoint is removed or access-restricted, and
the reasoning is recorded — an unrestricted debug endpoint left in place is its own finding.

## Snapshots

Stage boundaries only, matching the build stages in `SCOPE.md`:

```text
00-base-os-clean
01-apache-single-vhost-clean
02-apache-vhost-behavior-clean
03-nginx-proxy-boundary-clean
04-client-ip-and-tls-clean
05-php-upload-path-clean
06-two-tenant-isolation-clean
```

Architectural snapshots: powered off, for consistency. Pathological runtime states
(saturation, memory pressure): taken running, with memory state, so a revert restores that
exact condition instantly and the state can be re-entered as many times as the write-up needs.

Linked clones are used for branches likely to leave the VM unusable — aggressive exhaustion
testing, experimental TLS work, and the separate panel-comparison VM.

## Private CA

Two-tier, generated in the lab:

```text
lab root CA  ──signs──▶  intermediate CA  ──signs──▶  site-a.lab leaf
```

The client VM trusts the root. nginx is served a chain file containing **leaf +
intermediate**; the root is not sent, because it is already in the client's trust store —
which is exactly the lesson `ssl_certificate` teaches when given a bare leaf instead.

Leaf certificates **must** carry `subjectAltName`. Modern clients ignore `CN` for hostname
matching entirely, so a SAN-less leaf fails validation even with a fully trusted chain. That
makes an excellent deliberate mini-test and a miserable accident, so it is done on purpose:

```ini
subjectAltName = @alt_names

[alt_names]
DNS.1 = site-a.lab
DNS.2 = site-b.lab
```

Lifetime is not a concern here — the 398-day cap applies to publicly trusted chains, not to
locally installed roots.

For `testssl.sh`, pass the lab CA (`--add-ca`) so private-trust complaints do not bury the
protocol and cipher findings that are actually under test.

## Memory-exhaustion testing (deferred to release two)

Swap must be off first, or the result is disk thrashing rather than an observable OOM kill:

```bash
sudo swapoff -a && swapon --show && free -h
```

This is a lab control for determinism, not a production recommendation, and the write-up
says so. The exercise distinguishes pool saturation, request queuing, system memory
pressure, swap thrashing, and kernel OOM intervention — five different symptoms that all
present initially as "the site is slow."
