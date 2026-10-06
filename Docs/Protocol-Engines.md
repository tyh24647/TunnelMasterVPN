# Protocol integration

## Native IKEv2 / IPsec

EAP username/password for IKEv2, PSK + XAuth for IKEv1. Certificate identity is required for IKEv2, certificate validation remains enabled. Authentication secrets use persistent Keychain references. Certificate/PKCS#12 import, managed-device policies, on-demand routing and a complete kill-switch policy are not implemented.

## WireGuard

The optional project compiles bundled upstream Swift/C files into the extension, plus the upstream wg-quick parser. The app stores the config under `<profile UUID>.import`; the extension retrieves it using the shared Keychain group. The Go bridge Makefile links `libwg-go.a`. The extension cannot expose key-bearing raw engine logs.

Generate with `python3 Scripts/generate-project.py --wireguard`. Install and verify a compatible Go toolchain on the Mac. The upstream runtime patch may need updating for newer Go; it must not be bypassed without validating sleep/wake behavior. The pinned Apple mirror has old transitive Go versions; run a dependency/security audit and migrate to current compatible official upstream versions before release. This integration has not been compiled against Apple SDKs here.

Profiles must specify their intended allowed IPv4/IPv6 ranges, peers, endpoint, DNS and private key. No automatic mutation of supplied routes occurs. Default/full tunnel versus split tunnel therefore follows the configuration. A tunnel-up status does not establish that IPv6/DNS are leak-free.

## OpenVPN / SSTP

Not implemented. Add a supported, licensed engine in a packet-tunnel adapter. Preserve key handling, authentication, certificate validation, MTU, reconnection, DNS and IPv6 semantics. OpenVPN licensing must be compatible with distribution. SSTP requires certificate validation and PPP/tunnel implementation; TLS on port 443 alone is not SSTP. Do not enable their capability flags until tested on-device.

## PPTP and developer VPNs

PPTP is not implemented and should not be sold as secure. Modern iOS lacks native PPTP VPN support. StosVPN/LocalDevVPN are application/workflow names rather than interchangeable internet VPN protocols. No JIT enabler is included. A network tunnel does not confer entitlements to execute unsigned/JIT code.

## Regex engine

PCRE2 10.49 source is vendored with attribution and archive digest. Generic portable configuration enables 8-bit Unicode matching and disables JIT. The actual source is compiled into both targets, with separate binary copies. The bridge currently compiles each pattern for each evaluation; before very large production lists, use a bounded compiled-pattern cache and benchmark extension memory consumption. Limits are 4 KB per pattern, 253-byte hostname, 100,000 match steps, depth 200 and 1 MB match heap. This supports PCRE2 semantics within resource limits, not every possible syntax of every regex dialect.
