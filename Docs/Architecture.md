# Architecture

## Components

- SwiftUI application: configuration editing, purchase UI, accounts, logs, FAQ, appearance.
- NEVPNManager: native IKEv2 and IPsec. The OS performs negotiation/certificate checks.
- NETunnelProviderManager + PacketTunnelProvider: local DNS engine, optional WireGuard engine. A profile chooses one engine; no simultaneous independent VPNs.
- PCRE2 C bridge: full interpreter, not Safari content-blocking syntax. JIT is disabled; advanced regex does not require iOS executable-code JIT.
- Reference FastAPI control plane: identity broker, email verification, device registrations, Apple purchase verification, family mail queue, referral credits, gateway provisioning boundary.
- Operator gateways: not supplied or deployed. They must enforce peers, expirations, quotas, speed tiers, IP forwarding/NAT, IPv6 policy, multi-hop and health reporting.

## Data boundaries

App profile metadata and preferences live in UserDefaults and optionally iCloud KVS. The iCloud document uses a last-modified-wins merge: simultaneous edits can overwrite one another. Rules/profiles have stable UUIDs but no per-record conflict resolution. Settings remain in a local device document on sign-out; an Apple Account's iCloud is distinct from the service account. Separate service-account namespaces and merging UI are future work for shared-device deployments.

Credentials, imported wg-quick files, session tokens and installation IDs are in a shared device-only Keychain access group. They are not exported in profiles, sent to iCloud, or included in logs. A remotely synced profile requires re-entering credentials on that device. Uninstall does not guarantee Keychain removal; add an explicit wipe workflow before a consumer release.

Logs are a bounded in-memory operational stream. Exports are device-protected temporary text files; sharing is user-initiated. No domain browsing logs or raw WireGuard debug output are recorded. Hidden logs remain collected until the app session ends or the user clears them.

The reference service stores sessions/code hashes, identities, registrations, transaction metadata and referral relationships in SQLite. Outbox mail is explicit transactional mail; confirmation bodies are erased after sending. A retention/cleanup job and secret management are deployment requirements.

## Truthful status

A connected badge derives from NEVPNConnection.status. DNS mode says 'DNS filter active', never claims encryption or a foreign exit IP. Server cards stay offline until a real service publishes them. Performance/anonymity claims are not fabricated. Unavailable engine selection never runs a fake timer or displays a successful connection.

## Local DNS limits

Only virtual DNS IP routes enter the local extension; ordinary traffic is not tunneled. Queries are validated and forwarded over UDP to the selected resolver, or answered locally with the chosen IPv4 sink. AAAA/SVCB/HTTPS matches receive empty responses. Allow rules have precedence. A regex evaluation error returns SERVFAIL. Forwarded replies must match the ID and question; request count and time are bounded.

The development implementation rejects IP fragments/extensions, malformed queries, oversized/truncated responses and unsupported non-UDP traffic. It does **not** implement DNS-over-TCP fallback, DNSSEC synthesis, CNAME-chain reinspection, encrypted DNS interception, page cosmetics or comprehensive leak prevention. Some sites can fail or evade filtering. Use the documented release tests before relying on it.

## Multi-hop and routing

Multi-hop is an entry-to-exit route provisioned by an operator. It is not an arbitrary pair of protocol strings or two iOS profiles simultaneously connected. Each gateway catalog entry publishes eligible exits. The backend verifies compatibility and entitlement before asking the private provisioner for a configuration.

A DNS allow rule is not a VPN split-tunnel rule. Native NEVPNProtocol does not provide arbitrary per-domain traffic exclusions. Such profile intent is saved, but connections fail with a clear explanation while unsupported bypass rules are present. No host is silently sent directly.
