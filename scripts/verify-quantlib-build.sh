#!/bin/bash
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
lib="$root/Vendor/QuantLib/lib/libQuantLib.a"
[ -f "$lib" ] || { echo "Run scripts/build-quantlib.sh first." >&2; exit 1; }
for arch in arm64 x86_64; do xcrun lipo "$lib" -verify_arch "$arch"; done
printf 'Universal QuantLib archive verified: '
xcrun lipo -archs "$lib"

if [ "$#" -gt 0 ]; then
    app="$1"
    executable="$app/Contents/MacOS/MyBondManager"
    [ -f "$executable" ] || { echo "App executable is missing: $executable" >&2; exit 1; }
    for arch in arm64 x86_64; do xcrun lipo "$executable" -verify_arch "$arch"; done
    [ -s "$app/Contents/Resources/ThirdPartyNotices.txt" ] || { echo "Third-party notices are missing." >&2; exit 1; }
    dependencies=$(xcrun otool -L "$executable")
    unexpected=$(printf '%s\n' "$dependencies" | awk '/^[[:space:]]/ { if ($1 !~ /^\/System\/Library\// && $1 !~ /^\/usr\/lib\//) print $1 }')
    [ -z "$unexpected" ] || { printf 'External runtime dependencies:\n%s\n' "$unexpected" >&2; exit 1; }
    codesign --verify --deep --strict "$app"
    printf 'Self-contained universal app verified: %s\n' "$app"
fi
