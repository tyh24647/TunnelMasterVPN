# TunnelMaster VPN - [⇅] - Free • Custom • Unlimited

Native project: `TunnelMasterVPN.xcodeproj`. iOS may truncate the long display name under its icon.

A native SwiftUI VPN development project styled to match Tyler Hostager's DevTools and RegexDojo: rounded material cards, capsule badges, purple accents, native forms, and light/dark/system appearance. Source uses expanded K&R blocks and documents nontrivial behavior.

**This is a development implementation, not a launched VPN service or a tested App Store binary.** The project includes an actual native VPN controller and local DNS engine, an optional WireGuard adapter, StoreKit integration, and a reference service. It does not contain purchased/operated VPN gateways. Some requested protocol engines and commercial lifecycle work remain unfinished. See the status table below before deploying.

## Open in Xcode

1. Unzip, then open `TunnelMasterVPN.xcodeproj` on a Mac with Xcode supporting iOS 17 or later. The generated **base project** has no package downloads and includes PCRE2 C source.
2. Copy `Configuration/Developer.xcconfig.example` to `Configuration/Developer.xcconfig`. Enter your team and unique bundle prefix. Leave service URL/support email empty until configured. Re-run `python3 Scripts/configure.py` only if changing generated metadata.
3. Register the app and `.PacketTunnel` extension IDs. Enable Personal VPN for the app, Network Extensions / Packet Tunnel for both relevant targets, shared Keychain access, and iCloud key-value storage for the app. Match provisioning profiles to entitlements.
4. Select the `TunnelMasterVPN` scheme and a physical iPhone/iPad. Build and run. Approve the VPN configuration prompt when connecting. The simulator can show UI but does not validate a VPN session.
5. Add your own IKEv2/IPsec profile, or try DNS Shield. No real credentials are included. Certificate trust verification is kept enabled.

Xcode compilation and device execution have **not** been performed in the generation environment. The checked-in project was generated and its source files/metadata checked; the C engine was compiled and exercised on Linux.

## Optional WireGuard build

Upstream WireGuard Apple source is bundled at commit `2fec12a6e1f6e3460b6ee483aa00ad29cddadab1` (GitHub mirror). Its Go module is pinned by upstream `go.mod`/`go.sum`. This is an integration baseline, not a claim that the bundled dependency versions are current or release-audited.

```sh
python3 Scripts/generate-project.py --wireguard
open TunnelMasterVPN.xcodeproj
```

Install Go on the Mac first. The packet target's build phase invokes the upstream Makefile, builds `libwg-go.a`, and patches a private Go runtime copy for sleep-aware timers. Upstream's patch must be validated against the Go version you select; an incompatible patch deliberately fails the build. The device/simulator bridge has not been built here. For a base build with no Go requirement, regenerate without `--wireguard`.

The optional build uses actual WireGuardKit adapter/start/stop code and the upstream wg-quick parser, with private configuration in shared device-only Keychain. The base build disables WireGuard connection and explains the prerequisite. Neither build pretends unsupported engines are connected.

## What is implemented

| Feature | Status |
|---|---|
| Matching visual style, appearance, accent color, iPhone/iPad UI | Implemented |
| Custom profiles, editing/deletion, secure imported configurations | Implemented; import stores files, not every protocol can run |
| Native IKEv2 with EAP credentials | Implemented, needs real gateway/device validation |
| Native IPsec/IKEv1 PSK + extended authentication | Implemented, needs real gateway/device validation |
| WireGuard | Adapter and source bundled; opt-in Go build/device verification required |
| OpenVPN and SSTP | Configuration/help only; engines not implemented |
| PPTP | Deliberately unavailable: no native modern iOS support, obsolete security |
| StosVPN / LocalDevVPN / JIT | Explained, not implemented; local tunnels do not enable JIT |
| TCP/UDP | Correctly modeled as transports; OpenVPN choice stored for future engine |
| Local AdBlock DNS | Actual UDP DNS packet engine, IPv4/IPv6, exact/wildcard/PCRE2 rules, configurable IPv4 sink |
| Full PCRE2 interpreter | Bundled 10.49, Unicode/case-insensitive, lookarounds/backreferences/recursion, bounded resources |
| DNS production completeness | TCP fallback, fragmentation, encrypted DNS handling, and device/leak validation outstanding |
| Remote VPN domain whitelist | Saved intent only; native connections refuse nonempty lists instead of silently ignoring them |
| Multi-hop | UI and provisioning contract; needs operator-provisioned compatible gateway routes |
| Eight countries/free and premium tiers | Clearly labeled preview locations, not live servers |
| Server metrics/purpose recommendations | Displays only service-published data; no fabricated speed/anonymity ratings |
| iCloud preferences | Implemented using ubiquitous key-value store, opt-in with account; no secrets/logs synced |
| Apple/Microsoft/Discord/GitHub/Facebook | Secure browser + PKCE client and broker-backed reference endpoints; provider setup required |
| Email signup/confirmation | One-time confirmation-code flow and SMTP outbox worker; email provider setup required |
| Anonymous use | Personal profiles/DNS work without account, preferences remain device-only; hosted provisioning currently requires account |
| 3-device individual / unlimited family policy | Service logic included; gateway enforcement must be completed |
| IAP, restore, transaction observation | StoreKit 2; production purchasing disabled by default |
| Recurring 7-day trials | Local StoreKit catalog; must configure App Store Connect eligibility |
| Lifetime trial | Separate 7-day service trial; no automatic non-consumable charge; family trial sharing not implemented |
| Family notification emails | Explicit recipient entry, payment verification, owner check, idempotent outbox; no Apple family email discovery |
| Discount/referral codes | Apple offer-code sheet; username-derived unique referral and one service-month credit policy |
| Event logs | Timestamp/filter/verbose/hide/clear/text export/reviewable Mail composer; in-memory operational events |
| Native Mac app | Not included; iPad supported. A Mac target/extension needs a separate implementation and signing pass |

## Requested US pricing

| Membership | Weekly | Monthly | Yearly | Lifetime |
|---|---:|---:|---:|---:|
| Individual | $0.99 | $2.99 | $24.99 | $69.99 |
| Family | $2.99 | $9.99 | $49.99 | $199.99 |

Recurring products share a subscription group to prevent simultaneous subscriptions and repeated introductory trials. Family products have Family Sharing enabled in the local catalog; production settings must be configured separately. A family means Apple's eligible group, up to six people, with no app-imposed device cap; it does not mean unlimited people. Prices localize through StoreKit.

## Included documentation

- `Docs/Architecture.md`: boundaries, sensitive data, protocol decisions.
- `Docs/Service-Setup.md`: reference backend, provider setup, gateway API.
- `Docs/Protocol-Engines.md`: protocol status and integration requirements.
- `Docs/Testing.md`: executed checks and device test matrix.
- `Docs/Release.md`: remaining release requirements.
- `Docs/Sources.md`: technical sources.

Run the portable tests with `python3 Tests/test_core.py`. They compile and exercise the bundled C implementation with a system C compiler; no network calls or emails are made.
