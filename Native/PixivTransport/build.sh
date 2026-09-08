#!/bin/bash
set -euo pipefail
root="$(cd "$(dirname "$0")" && pwd)"
cargo_cmd="${CARGO_HOME:-$HOME/.cargo}/bin/cargo"
if [[ ! -x "$cargo_cmd" ]]; then cargo_cmd="$(command -v cargo)"; fi
target_dir="${CARGO_TARGET_DIR:-$root/target}"
export CARGO_TARGET_DIR="$target_dir"
# Required by the vendored Pixez rhttp HTTP/3 dependency (also used by upstream).
export RUSTFLAGS="${RUSTFLAGS:-} --cfg reqwest_unstable"
for target in aarch64-apple-darwin x86_64-apple-darwin aarch64-apple-ios aarch64-apple-ios-sim x86_64-apple-ios; do
  case "$target" in
    aarch64-apple-ios) export SDKROOT="$(xcrun --sdk iphoneos --show-sdk-path)" ;;
    aarch64-apple-ios-sim|x86_64-apple-ios) export SDKROOT="$(xcrun --sdk iphonesimulator --show-sdk-path)" ;;
    *) export SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" ;;
  esac
  IPHONEOS_DEPLOYMENT_TARGET=17.0 MACOSX_DEPLOYMENT_TARGET=14.0 "$cargo_cmd" build --locked --release --manifest-path "$root/Cargo.toml" --target "$target"
done
mkdir -p "$root/build"
python3 "$root/notices.py" "$cargo_cmd"
mkdir -p "$root/build/macos" "$root/build/simulator"
lipo -create "$target_dir/aarch64-apple-darwin/release/libsetu_pixiv_transport.a" "$target_dir/x86_64-apple-darwin/release/libsetu_pixiv_transport.a" -output "$root/build/macos/libsetu_pixiv_transport.a"
lipo -create "$target_dir/aarch64-apple-ios-sim/release/libsetu_pixiv_transport.a" "$target_dir/x86_64-apple-ios/release/libsetu_pixiv_transport.a" -output "$root/build/simulator/libsetu_pixiv_transport.a"
output="$root/build/SetuPixivTransport.xcframework"
if [[ -e "$output" ]]; then mv "$output" "$root/build/previous-$(date +%s).xcframework"; fi
xcodebuild -create-xcframework \
  -library "$root/build/macos/libsetu_pixiv_transport.a" -headers "$root/include" \
  -library "$target_dir/aarch64-apple-ios/release/libsetu_pixiv_transport.a" -headers "$root/include" \
  -library "$root/build/simulator/libsetu_pixiv_transport.a" -headers "$root/include" \
  -output "$output"
