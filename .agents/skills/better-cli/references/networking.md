# Networking

## Source basis

Adapted from [Networking](https://bettercli.org/design/cli-networking/), one of the
most developed upstream articles. Exact proxy, certificate, and transport behavior
depends on the selected runtime/library; consult current official documentation.

## One coherent policy

Centralize configuration so business requests, authentication, update checks, and
authorized telemetry do not silently follow different routing or trust policies.
Replacing a network library can alter compatibility despite passing basic API
tests. Preserve representative environment tests.

Prefer proven networking facilities and support actual user environments. Do not
promise every enterprise authentication scheme or build a custom HTTP stack for
hypothetical deployments.

## Proxies and trust

- Check supported `http_proxy`/`HTTP_PROXY`, `https_proxy`/`HTTPS_PROXY`, and
  `no_proxy`/`NO_PROXY` behavior. Case precedence and exclusion matching are not
  universal; document selected-stack behavior, including conflicts.
- `HTTPS_PROXY` selects routing for HTTPS requests; its URL may use HTTP. Do not
  require an `https://` proxy URL for all HTTPS destinations.
- Distinguish tunneling TLS from terminating and inspecting TLS. Custom trust roots
  may be needed for legitimate enterprise interception.
- Support configured certificate authorities and, where required, client
  certificates/mTLS through the runtime. Keep peer verification enabled normally.
- Consider credential-based authentication and 407 challenges. NTLM, Kerberos, and
  integrated authentication require explicit support decisions; an external proxy
  bridge may be more appropriate than native implementation.
- Debug routing/trust configuration without exposing proxy URL credentials or
  authentication headers.

An insecure TLS bypass is a product decision, not a mandatory flag. If provided,
make it explicit and visible, explain safer trust configuration, and keep it from
becoming the routine repair for connection failure. Never silently disable trust
verification to make a request succeed.

## Deployment compatibility

Check IPv4-only, IPv6-only, and dual-stack assumptions where relevant, including
the service. For WebSockets, SSH, and other transports, consider feasible HTTPS
fallbacks without sacrificing required semantics or security.

Document contacted hosts, protocols, and ports, including optional services.
Where mirrors/reverse proxies are needed, offer an explicit shared endpoint
override. Extension: define which credentials may reach overridden endpoints;
redirects or alternate hosts must not accidentally leak authentication data.

Use a recognizable client identifier such as product/version in User-Agent.
Include platform details only when justified, never personal data.

## Verification (extension)

Use controlled fixtures for direct access, proxy routing/exclusions, conflicting
case variants, custom CA success, untrusted certificate failure, authentication
failure, timeouts, and unavailable optional services. Select supported scenarios.
Report unsupported cases rather than inferring support from an environment
variable's presence or a library option.
