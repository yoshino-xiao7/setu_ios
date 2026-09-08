# Native Pixiv transport

Rust/C adapter directly using the MIT-licensed rhttp network client vendored in Pixez (pinned source and adaptations in vendor/rhttp-native/UPSTREAM.md) for optional enhanced connections and verified image delivery. OAuth exchange/refresh and works API requests are routed by PixivDirectHTTPTransport after credential-free connection probes: ECH gets a short head start, with an isolated system URLSession alternative. Same-device checks found ECH succeeds without VPN while the system route requires the user's proxy. Selection is short-lived and invalidated on failure; only safe GET requests may retry once on a newly validated different route, never OAuth or mutations. No Flutter runtime or GPL application code is included. Swift owns per-account credentials in Keychain; this library never stores credentials or cookies.

## Build before SwiftPM or XcodeGen

Requires full Xcode, Python 3 and Rust 1.98.1 via rustup. The generated XCFramework is intentionally ignored by Git. On a clean checkout:

```sh
rustup toolchain install 1.98.1 --profile minimal
rustup target add --toolchain 1.98.1 aarch64-apple-darwin x86_64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios
RUSTUP_TOOLCHAIN=1.98.1 bash Native/PixivTransport/build.sh
swift test
xcodegen generate
```

The build uses Cargo.lock and emits arm64 iOS plus universal arm64/x86_64 simulator and macOS slices. Existing output is moved aside before replacement. `CARGO_HOME`, `RUSTUP_HOME` and `CARGO_TARGET_DIR` can point to an isolated development toolchain/cache.

`notices.py` collects dependency license texts from the locked Apple graph into `build/ThirdPartyNotices.txt`, bundled by Xcode. ZIPFoundation's notice is included separately in app resources. Production additions are Rustls/Reqwest and their locked dependencies for ECH, and ZIPFoundation for bounded animation archive extraction. MP4 encoding uses Apple's AVFoundation.

## Constraints and validation

- Native API TLS requires ECH; the system alternative uses standard TLS with default certificate validation. Neither path falls back to accepting invalid certificates. Image connections omit SNI while retaining certificate-chain and requested-host validation.
- Fixed Pixiv API/origin hosts plus the selected image mirror. API redirects are refused; configured mirror redirects must stay on the exact HTTPS host. Only registered image paths can be rewritten by Swift. Image requests accept only Referer, User-Agent, Accept and Range; no request body, cookies, Authorization, Setu SID or HMAC.
- Four concurrent Swift workers, bounded responses and DNS cache, connection/request deadlines, cancellation checks during reads. Async requests stop on cancellation; the optional login bridge has separate deadlines.
- Uses device routing; does not alter VPN settings or force Wi-Fi. The Mac diagnostic probe can bind a physical interface to distinguish VPN routing from server reachability.
- The login WebView defaults to standard WebKit. The optional enhanced connection uses an authenticated, loopback-only CONNECT bridge with a per-session certificate, exact WebView-scoped pinning, fixed host/port allowlist and fully verified ECH upstream TLS. No system certificate is installed. The seven exact proxy hosts need ATS exceptions for manual anchor trust; HTTP web resources are explicitly blocked. Other domains retain ATS defaults. This requires an App Store exception justification.
- `connectionStage` exposes only fixed numeric connection stages. The DEBUG public-page probe records no credentials or page input values. Actual account authorization and token refresh still require separate device validation.
- Run `RUSTFLAGS="--cfg reqwest_unstable" cargo test --manifest-path Native/PixivTransport/Cargo.toml` for transport boundary tests. Swift tests cover per-account PKCE, refresh isolation, media/cursor lifetime and actual MP4 frame timing.

Protocol investigation references: [Pixez network configuration](https://github.com/Notsfsssf/pixez-flutter/blob/master/lib/network/pixez_network_settings.dart), [OAuth flow](https://github.com/Notsfsssf/pixez-flutter/blob/master/lib/network/oauth_client.dart). OAuth and app configuration are protocol references; the separately licensed rhttp Rust client is embedded with its license and third-party notices.

Image origins are resolved through bounded HTTPS DNS queries to Cloudflare's fixed bootstrap addresses with normal certificate verification. The three origin image hostnames use this path; private/reserved DNS answers are rejected, and per-host node pools follow DNS TTL (at most 600 seconds, at most 12 addresses). Failed DNS lookups may briefly use known official Pixiv origin nodes. Image header timeouts can rotate nodes once; OAuth/API requests are not replayed by this logic. All response-size and total-time limits remain in force.

The iOS image settings select the built-in `i.pixiv.re` mirror by default, the original host, or a user-configured HTTPS image hostname. Mirrors use normal verified HTTPS/SNI without a proxy. Custom hosts resolve to public IPs only, and the validated addresses are pinned to the client for 60 seconds to prevent DNS rebinding; at most four custom clients are retained. Static image paths from `i.pximg.net` and `i-cf.pximg.net` are preserved; API/OAuth, s.pximg.net assets and animation archives retain their existing route. Mirror failure is visible and can be retried or switched in image settings. The existing binding-private 64 MiB / 256 item cache is shared across image hosts.

`-ui-testing-pixiv-image-speed-probe` is an explicit DEBUG-only UI using a fixed public fixture. It compares the production built-in and custom-host transport paths without account credentials, writing only round/variant/status/bytes/duration to `pixiv-image-speed-probe.txt`. Native public-fixture differential variants are also opt-in and cannot use caller URLs, bodies or headers.
