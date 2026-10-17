#!/bin/bash
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
. "$root/Vendor/quantlib-versions.env"
cmake_bin=${CMAKE_BIN:-cmake}
command -v "$cmake_bin" >/dev/null || { echo "Install CMake or set CMAKE_BIN to its executable." >&2; exit 1; }
cache="$root/Vendor/QuantLib/cache"
mkdir -p "$cache"
ql_source="$cache/QuantLib"
boost_source="$cache/boost_1_88_0"
if [ ! -d "$ql_source/.git" ]; then
    git clone --depth 1 --branch "$QUANTLIB_TAG" https://github.com/lballabio/QuantLib.git "$ql_source"
fi
[ "$(git -C "$ql_source" rev-parse HEAD)" = "$QUANTLIB_COMMIT" ] || { echo "QuantLib revision differs from lock" >&2; exit 1; }
[ -z "$(git -C "$ql_source" status --porcelain)" ] || { echo "QuantLib source cache is dirty" >&2; exit 1; }
archive="$cache/$BOOST_ARCHIVE"
if [ ! -f "$archive" ]; then
    curl --fail --location --retry 3 "https://archives.boost.io/release/$BOOST_VERSION/source/$BOOST_ARCHIVE" -o "$archive.part"
    mv "$archive.part" "$archive"
fi
printf '%s  %s\n' "$BOOST_SHA256" "$archive" | shasum -a 256 -c -
if [ ! -d "$boost_source" ]; then tar -xzf "$archive" -C "$cache"; fi
for arch in arm64 x86_64; do
    build_dir="$cache/build-$arch"
    install_dir="$cache/install-$arch"
    "$cmake_bin" -S "$ql_source" -B "$build_dir" -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=20 \
        -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DCMAKE_OSX_ARCHITECTURES="$arch" \
        -DCMAKE_INSTALL_PREFIX="$install_dir" -DBOOST_ROOT="$boost_source" \
        -DBUILD_SHARED_LIBS=OFF -DQL_BUILD_EXAMPLES=OFF -DQL_BUILD_TEST_SUITE=OFF \
        -DQL_INSTALL_EXAMPLES=OFF -DQL_INSTALL_TEST_SUITE=OFF -DQL_USE_STD_SHARED_PTR=ON
    "$cmake_bin" --build "$build_dir" --parallel "${BUILD_JOBS:-4}"
    "$cmake_bin" --install "$build_dir"
done
diff -qr "$cache/install-arm64/include" "$cache/install-x86_64/include"
mkdir -p "$root/Vendor/QuantLib/lib" "$root/Vendor/QuantLib/include"
cp -R "$cache/install-arm64/include/" "$root/Vendor/QuantLib/include/"
# QuantLib public headers depend on Boost headers at compile time only.
cp -R "$boost_source/boost" "$root/Vendor/QuantLib/include/"
xcrun lipo -create "$cache/install-arm64/lib/libQuantLib.a" "$cache/install-x86_64/lib/libQuantLib.a" -output "$root/Vendor/QuantLib/lib/libQuantLib.a"
{ cat "$ql_source/LICENSE.TXT"; printf '\nBoost headers\n'; cat "$boost_source/LICENSE_1_0.txt"; } > "$root/Vendor/ThirdPartyNotices.txt"
cp "$root/Vendor/ThirdPartyNotices.txt" "$root/MyBondManager/ThirdPartyNotices.txt"
{ printf 'QuantLib %s\nBoost %s\n' "$QUANTLIB_COMMIT" "$BOOST_VERSION"; xcrun clang --version; xcrun --show-sdk-version; } > "$root/Vendor/QuantLib/build-manifest.txt"
bash "$root/scripts/verify-quantlib-build.sh"
