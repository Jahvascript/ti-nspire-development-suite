#!/bin/bash
# Build completely offline using the included dependency sources.
set -euo pipefail
src_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="${1:-$src_dir/../build}"
mkdir -p "$build_dir"
build_dir="$(cd "$build_dir" && pwd)"
export CARGO_HOME="$build_dir/cargo-home"
export CARGO_TARGET_DIR="$build_dir/rust-target"
export MACOSX_DEPLOYMENT_TARGET=13.0
mkdir -p "$CARGO_HOME" "$build_dir/swift-cache"
swift_cache="$(cd "$build_dir/swift-cache" && pwd -P)"
# Generate the original calculator exit marker when absent.
# The binary resource is intentionally not tracked in Git.
marker="$src_dir/resources/Exit Test Mode.tns"

if [ ! -s "$marker" ]; then
    marker_source="$src_dir/resources/exit-marker.lua"
    luna_source="$src_dir/../../TNSStudio/source/third-party/Luna"
    luna_build="$build_dir/luna-marker"

    if [ ! -f "$marker_source" ] || [ ! -f "$luna_source/Makefile" ]; then
        echo "ERROR: Calculator resource generation sources missing." >&2
        exit 1
    fi

    mkdir -p "$luna_build"
    /bin/cp -R -X "$luna_source/." "$luna_build/"
    make -C "$luna_build" CC=clang

    "$luna_build/luna" "$marker_source" "$marker"
    test -s "$marker"
fi

cd "$src_dir/backend"
cargo test --locked --offline
cargo build --release --locked --offline
app_dir="$build_dir/NspireDesk.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Helpers" "$app_dir/Contents/Resources"
swiftc -O -target "$(uname -m)-apple-macos13.0" -module-cache-path "$swift_cache" -framework Cocoa "$src_dir/App.swift" -o "$app_dir/Contents/MacOS/NspireDesk"
cp "$CARGO_TARGET_DIR/release/nspiredesk-usb" "$app_dir/Contents/Helpers/"
cp "$src_dir/resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$src_dir/resources/AppIcon.icns" "$app_dir/Contents/Resources/"
cp "$src_dir/../LICENSE.txt" "$src_dir/../Third-Party Notices.txt" "$app_dir/Contents/Resources/"
mkdir -p "$build_dir/test-include"
LC_ALL=C tar -xOf "$src_dir/patches/libusb1-sys/libusb/libusb-1.0.23.tar.gz" libusb-1.0.23/libusb/libusb.h > "$build_dir/test-include/libusb.h"
clang -fsanitize=address,undefined -I"$build_dir/test-include" -I"$src_dir/patches/libnspire-sys/libnspire/src" -I"$src_dir/patches/libnspire-sys/libnspire/src/api" "$src_dir/tests/connection_test.c" "$src_dir/patches/libnspire-sys/libnspire/src/init.c" -o "$build_dir/connection-test"
"$build_dir/connection-test"
clang++ -std=c++14 -ftrivial-auto-var-init=pattern -fsanitize=address,undefined -I"$build_dir/test-include" -I"$src_dir/patches/libnspire-sys/libnspire/src" -I"$src_dir/patches/libnspire-sys/libnspire/src/api" "$src_dir/tests/cx2_wire_test.cpp" -o "$build_dir/cx2-wire-test"
"$build_dir/cx2-wire-test"
clang -fsanitize=address,undefined "$src_dir/tests/rle_test.c" -o "$build_dir/rle-test"
"$build_dir/rle-test"
clang -fobjc-arc -framework Cocoa "$src_dir/tests/layout_check.m" -o "$build_dir/layout-test"
"$build_dir/layout-test"
"$app_dir/Contents/MacOS/NspireDesk" --self-test
codesign --force --sign - "$app_dir/Contents/Helpers/nspiredesk-usb"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
printf '\nBuilt: %s\n' "$app_dir"
