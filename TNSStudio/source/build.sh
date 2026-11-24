#!/bin/bash
set -euo pipefail
src_dir="$(cd "$(dirname "$0")" && pwd)"
build_dir="${1:-$src_dir/../build}"
mkdir -p "$build_dir"
build_dir="$(cd "$build_dir" && pwd -P)"
export MACOSX_DEPLOYMENT_TARGET=13.0
mkdir -p "$build_dir/Luna" "$build_dir/Lua"
/bin/cp -R -X "$src_dir/third-party/Luna/." "$build_dir/Luna/"
/bin/cp -R -X "$src_dir/third-party/Lua/." "$build_dir/Lua/"
make -C "$build_dir/Luna" CC=clang
make -C "$build_dir/Lua/src" CC=clang MYCFLAGS=-DLUA_USE_POSIX all
app_dir="$build_dir/TNS Studio.app"
mkdir -p "$app_dir/Contents/MacOS" "$app_dir/Contents/Helpers" "$app_dir/Contents/Resources" "$build_dir/swift-cache"
swift_cache="$(cd "$build_dir/swift-cache" && pwd -P)"
swiftc -O -target "$(uname -m)-apple-macos13.0" -module-cache-path "$swift_cache" -framework Cocoa -framework PDFKit -framework Vision "$src_dir/Core.swift" "$src_dir/App.swift" "$src_dir/main.swift" -o "$app_dir/Contents/MacOS/TNSStudio"
cp "$build_dir/Luna/luna" "$build_dir/Lua/src/luac" "$app_dir/Contents/Helpers/"
cp "$src_dir/resources/Info.plist" "$app_dir/Contents/Info.plist"
cp "$src_dir/resources/notes.lua" "$src_dir/resources/AppIcon.icns" "$src_dir/../LICENSE.txt" "$src_dir/../Third-Party Notices.txt" "$app_dir/Contents/Resources/"
"$app_dir/Contents/MacOS/TNSStudio" --self-test
"$build_dir/Lua/src/lua" "$src_dir/tests/reader_test.lua" "$src_dir/resources/notes.lua"
codesign --force --sign - "$app_dir/Contents/Helpers/luna"
codesign --force --sign - "$app_dir/Contents/Helpers/luac"
codesign --force --sign - "$app_dir"
codesign --verify --deep --strict "$app_dir"
printf '\nBuilt: %s\n' "$app_dir"
