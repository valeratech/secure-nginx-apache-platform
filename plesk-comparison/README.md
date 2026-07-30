# Hand-built vs panel-generated

Comparison against a **fresh trial installation** on a separate VM, using synthetic domains
(`site-a.lab`). No employer or production configuration, customer domain, real IP, license
identifier, internal path layout, or custom template is used or reproduced here.

Scope for release one is one synthetic domain: the generated nginx server block and the
generated Apache VirtualHost, next to the hand-written equivalents.

| Area | Hand-built | Panel-generated | Divergence, and why |
|---|---|---|---|
| Public nginx listener | | | |
| Apache backend vhost | | | |
| Static-file routing | | | |
| PHP handler wiring | | | |
| Include hierarchy | | | |
| Per-domain overrides | | | |
| TLS placement | | | |
| Log layout | | | |

For each divergence, state whether it is intentional, educational, environment-specific, or
a simplification — and what the panel plus CloudLinux solve that this lab does not.
