# Local QuantLib build

The native dependency is QuantLib1.44 at ab4cb476d35f7275834bc05b47d1324403d1823b, with Boost1.88.0 headers and C++20. Both architectures target macOS15.0. Inputs and checksums are pinned in Vendor/quantlib-versions.env.

Run `bash scripts/build-quantlib.sh` with CMake on PATH, or set CMAKE_BIN to its executable. The script verifies downloaded sources, builds arm64 and x86_64 static archives, compares installed headers, creates Vendor/QuantLib/lib/libQuantLib.a and copies the third-party notices into app resources. Generated sources/headers/builds are ignored. Xcode does not download anything during a build.

Run `bash scripts/verify-quantlib-build.sh` to check both archive architecture slices. Pass an app path to also verify its executable contains both slices, its notices resource exists, its signature verifies and its runtime dependencies use only system library locations. The app target must define HAVE_CONFIG_H so its bridge consumes the installed QuantLib configuration; otherwise its shared-pointer ABI differs from the static archive.

The C ABI takes calendar YYYYMMDD integers and financial terms, never instrument identifiers or Core Data objects. The native library supports1901 through2199 and returns bounded errors without partial output. Complete maturity-anchored regular reference schedules supply ICMA reference periods independently of payable stub schedules. This avoids reanchoring at a clamped first coupon and the sole-stub first/last ambiguity in QuantLib1.44. Regular expectations use explicit floating-point tolerance, without changing contractual expected amounts.

Native curve calls share one mutex and restore QuantLib Settings through SavedSettings; historical fixings are request-local. No IndexManager history is written. The delivered app statically links QuantLib and needs no developer tools, Python or network for existing saved forecasts. A universal archive is packaging evidence; Intel runtime execution and an offline copied Release app require separate verification.

Implementation evidence and pending gates are recorded in the plan execution ledger. Stage1 fixed/zero replacement alone does not complete floating forecasting.
