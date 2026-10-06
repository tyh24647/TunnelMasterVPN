# Validation and remaining device tests

## Executed in the generation environment

`python3 Tests/test_core.py`: **8 tests passed**. Tests compile the bundled PCRE2 10.49 and actual DNS C files rather than a reimplementation.

1. PCRE2 lookahead, lookbehind, backreference, recursion, nonmatch and syntax failure.
2. Pathological regex stops under match budget.
3. DNS A replacement, configurable sink, blocked AAAA/HTTPS/SVCB NODATA, SERVFAIL.
4. IPv4/IPv6 packet extraction, reverse port mapping and UDP checksum validity.
5. Malformed/truncated/fragmented packet rejection, DNS name compression-pointer rejection.
6. Three-device limit, existing device renewal and unlimited family policy.
7. Calendar referral month rollover/leap year and username-derived code format.
8. Expired/revoked/upgraded/wrong-bundle/unknown-product entitlement rejection; shared ownership is not purchaser ownership.

App-owned Swift files passed a tree-sitter Swift syntax parse. Python source passed bytecode compilation. Plists/StoreKit JSON and project source references were checked. These checks do not substitute for Swift type checking, linking, signing or OS execution.

`python3 Tests/test_service.py`: **5 tests passed** against the local HTTP app, with mail delivery mocked: one-time email confirmation, PKCE/replay handling, unpaid-family invitation rejection, self/repeat referral rejection, and disabled commercial catalog by default. No messages or provider requests were sent. Combined total: **13 portable tests passed**.

## Not executed here

No Xcode/macOS SDK is installed. No iPhone VPN session, WireGuard Go bridge build, Swift type-check, App Store sandbox purchase, provider login, SMTP delivery, iCloud round trip, server provisioning, throughput benchmark or leak test was performed. The source is not claimed to be an installable or production-verified binary.

## Required Mac pass

```sh
python3 Scripts/generate-project.py
xcodebuild -project TunnelMasterVPN.xcodeproj -scheme TunnelMasterVPN \
  -sdk iphonesimulator -configuration Debug CODE_SIGNING_ALLOWED=NO build
```

Then enable signing and build for your physical iPhone/iPad. For WireGuard, regenerate with `--wireguard`, install a compatible Go toolchain, and verify both device and simulator bridge builds. Resolve any Swift/SDK issues before distributing.

## Functional matrix

- First launch privacy disclosure, accessibility/Dynamic Type, VoiceOver, phone/iPad layout, light/dark/auto, custom accent.
- Native IKEv2: valid credentials, wrong remote ID, expired/untrusted certificate, rejected EAP, disconnect, network handover, sleep/wake, captive portal.
- IPsec: PSK/group/XAuth failures, network handover and IPv6-only access networks.
- WireGuard: parse errors never log private keys, valid peer handshake, DNS/allowed IPs, MTU, endpoint resolution, Wi-Fi/cellular changes, sleep/wake, stopped engine cleanup.
- DNS: A/AAAA/HTTPS/SVCB, allow precedence, wildcard anchoring, PCRE2 limits, upstream failures, response spoofing, cache, encrypted DNS bypass, memory pressure and 128-request bound. Implement and test TCP fallback and fragmented packets before calling it production-ready.
- Verify public IPv4/IPv6, DNS paths, remote route enforcement, reconnection leaks and simultaneous VPN replacement. Do not infer encryption from a UI badge alone.
- iCloud: two devices on the same Apple Account, network outage, opt-out, signed-out mode, simultaneous edits, size limit, credential absence after sync.
- Logs: filters/export/clear, no secrets/hostnames, hide view, Mail unavailable, support address absent, user cancels composer.
- Purchases: localized prices, eligible/ineligible trials, cancellation, pending/Ask to Buy, replay, refund, expiration, upgrade/downgrade, lifetime restoration, family owner versus shared recipient, account binding and retry after provisioning failure.
- Backend: PKCE mismatch/state replay, rejected broker identity, email-code replay/expiry, registration races, spoofed transaction, production rejecting sandbox, family invitation idempotency, gateway revocation, referral abuse, account deletion/recovery.

A physical device, real test gateway, configured Apple developer organization and working service integrations are necessary for these checks.
