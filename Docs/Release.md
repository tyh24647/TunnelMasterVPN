# Release gates

Do not publish or charge users until these concrete gaps are addressed.

- Apple App Review guideline 5.4 requires VPN apps to use NEVPNManager and be offered by developers enrolled as organizations; verify current territorial VPN licensing obligations and distribution rules.
- Finish Xcode builds, signing, real-device network/leak tests and accessibility checks. Add a final AppIcon and marketing assets. Bundle identity/team currently require developer configuration.
- Commission/operate real gateways; configure secure certificate issuance, per-device credentials, IPv6 policy, DNS, forwarding, capacity and free-versus-premium bandwidth enforcement. The client alone cannot make paid servers faster.
- Complete protocol engines you intend to advertise. Optional WireGuard needs its Go build and dependency audit. OpenVPN/SSTP, JIT helper, native Mac app and remote per-domain bypass are not implemented.
- Complete DNS TCP fallback, robust packet handling, resource/performance testing and documented encrypted-DNS limitations.
- Complete commercial lifecycle in Service-Setup.md, including signed notifications, refunds, family ownership binding, purchase recovery, account deletion and provider revocation.
- Publish accurate privacy, terms, support and retention policies. Update the privacy manifest/App Store privacy responses for the actually deployed identity/mail/gateway services. The bundled manifest describes the local base build and is not a statement that a deployed account backend collects no data.
- Configure all eight App Store products, subscription-group levels, US price points, family sharing, seven-day recurring trials, offers and server notifications. Validate existing subscriber transitions before release. Lifetime has no automatic conversion from the separate trial.
- Configure sign-in provider consent screens, email sender authentication/delivery and support contact. Do not infer Apple family member addresses.
- Maintain explicit opt-in invitation recipients; handle deferred payments server-side before promising automatic invitations when the app is closed.
- Add device management/removal, meaningful gateway session caps and abuse policy for unlimited-family-device use.
- Resolve anonymous hosted access and Mac support if those are advertised. Current anonymous mode supports local DNS and personal configurations on iPhone/iPad.
- Supply App Review with functioning test access, real service infrastructure and an accurate explanation of all nonobvious VPN/IAP behavior.

The default `COMMERCIAL_READY=false` keeps purchases unavailable. It is a release gate, not an inconvenience to remove before the remaining work is done.
