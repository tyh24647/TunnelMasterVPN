#!/bin/bash
set -euo pipefail
export PATH="$PATH:/opt/homebrew/bin:/usr/local/bin"
if ! command -v go >/dev/null; then
    echo 'error: WireGuard requires Go. Install a compatible Go toolchain or regenerate the base project without --wireguard.'
    exit 1
fi
# Upstream Makefile patches a private copy of the Go runtime for sleep-aware timers.
# A patch failure must be investigated, never ignored.
make -C "$SRCROOT/Vendor/WireGuard/Sources/WireGuardKitGo" \
    PLATFORM_NAME="$PLATFORM_NAME" \
    GOOS_iphonesimulator=ios \
    ARCHS="$ARCHS" \
    DESTDIR="$BUILT_PRODUCTS_DIR" \
    BUILDDIR="$TARGET_TEMP_DIR/wireguard-go-bridge" build
