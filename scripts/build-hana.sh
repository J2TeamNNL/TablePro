#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE_DIR="$ROOT_DIR/Native/HanaBridge"
LIBS_DIR="${LIBS_DIR:-$BRIDGE_DIR/lib}"
ARCH="${1:-both}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/deployment-target.sh"

case "$LIBS_DIR" in
    /*) ;;
    *) LIBS_DIR="$ROOT_DIR/$LIBS_DIR" ;;
esac

build_slice() {
    local arch="$1"
    local go_arch="$arch"
    local output="$LIBS_DIR/libhana_bridge_${arch}.a"
    if [ "$arch" = "x86_64" ]; then
        go_arch=amd64
    fi
    (
        cd "$BRIDGE_DIR"
        env CGO_ENABLED=1 GOOS=darwin GOARCH="$go_arch" MACOSX_DEPLOYMENT_TARGET="$DEPLOY_TARGET" \
            go build -buildmode=c-archive -trimpath -mod=readonly -o "$output" .
    )
    nm -gU "$output" | grep 'T _tp_hana_connect' > /dev/null
}

mkdir -p "$LIBS_DIR"

case "$ARCH" in
    arm64|x86_64)
        build_slice "$ARCH"
        cp "$LIBS_DIR/libhana_bridge_${ARCH}.a" "$LIBS_DIR/libhana_bridge.a"
        ;;
    both|universal)
        build_slice arm64
        build_slice x86_64
        lipo -create \
            "$LIBS_DIR/libhana_bridge_arm64.a" \
            "$LIBS_DIR/libhana_bridge_x86_64.a" \
            -output "$LIBS_DIR/libhana_bridge.a"
        ;;
    *)
        echo "Usage: $0 [arm64|x86_64|both]" >&2
        exit 1
        ;;
esac

file "$LIBS_DIR"/libhana_bridge*.a
