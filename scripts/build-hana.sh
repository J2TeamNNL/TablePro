#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
BRIDGE_DIR="$ROOT_DIR/Native/HanaBridge"
HEADER="$ROOT_DIR/Plugins/HanaDriverPlugin/CHana/CHana.h"
LIBS_DIR="${LIBS_DIR:-$BRIDGE_DIR/lib}"
ARCH="${1:-both}"
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/deployment-target.sh"

case "$LIBS_DIR" in
    /*) ;;
    *) LIBS_DIR="$ROOT_DIR/$LIBS_DIR" ;;
esac

declared_symbols() {
    grep -oE 'tp_hana_[a-z_]+[(]' "$HEADER" | tr -d '(' | sort -u
}

verify_exports() {
    local archive="$1"
    local arch="$2"
    local exported
    exported="$(nm -arch "$arch" -gU "$archive" 2>/dev/null)"
    local symbol
    local missing=0
    while IFS= read -r symbol; do
        if ! grep -qE "[[:space:]]T _${symbol}\$" <<< "$exported"; then
            echo "$archive ($arch) does not export $symbol, which CHana.h declares" >&2
            missing=1
        fi
    done < <(declared_symbols)
    return "$missing"
}

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
    verify_exports "$output" "$arch"
}

if [ "$(declared_symbols | wc -l | tr -d ' ')" -eq 0 ]; then
    echo "No tp_hana_ symbols found in $HEADER" >&2
    exit 1
fi

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
        verify_exports "$LIBS_DIR/libhana_bridge.a" arm64
        verify_exports "$LIBS_DIR/libhana_bridge.a" x86_64
        ;;
    *)
        echo "Usage: $0 [arm64|x86_64|both]" >&2
        exit 1
        ;;
esac

file "$LIBS_DIR"/libhana_bridge*.a
