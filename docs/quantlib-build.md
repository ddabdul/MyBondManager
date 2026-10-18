# Local QuantLib build

The native dependency is QuantLib1.44 at ab4cb476d35f7275834bc05b47d1324403d1823b, with Boost1.88.0 headers and C++20. Both architectures target macOS15.0. Inputs and checksums are pinned in Vendor/quantlib-versions.env.

Run `bash scripts/build-quantlib.sh` with CMake on PATH, or set CMAKE_BIN to its executable. The script verifies downloaded sources, builds arm64 and x86_64 static archives, compares installed headers, creates Vendor/QuantLib/lib/libQuantLib.a and copies the third-party notices into app resources. Generated sources/headers/builds are ignored. Xcode does not download anything during a build.

Run `bash scripts/verify-quantlib-build.sh` to check both archive architecture slices. Pass an app path to also verify its executable contains both slices, its notices resource exists, its signature verifies and its runtime dependencies use only system library locations. The app target must define HAVE_CONFIG_H so its bridge consumes the installed QuantLib configuration; otherwise its shared-pointer ABI differs from the static archive.

The C ABI takes calendar YYYYMMDD integers and financial terms, never instrument identifiers or Core Data objects. The native library supports1901 through2199 and returns bounded errors without partial output. Complete maturity-anchored regular reference schedules supply ICMA reference periods independently of payable stub schedules. This avoids reanchoring at a clamped first coupon and the sole-stub first/last ambiguity in QuantLib1.44. Regular expectations use explicit floating-point tolerance, without changing contractual expected amounts.

Native curve calls share one mutex and restore QuantLib Settings through SavedSettings; historical fixings are request-local. No IndexManager history is written. The delivered app statically links QuantLib and needs no developer tools, Python or network for existing saved forecasts. A universal archive is packaging evidence; Intel runtime execution and an offline copied Release app require separate verification.

Implementation evidence and pending gates are recorded in the plan execution ledger. Stage1 fixed/zero replacement alone does not complete floating forecasting.

Purchase yields use the existing C ABI and shared mutex. The bridge builds a sorted SimpleCashFlow leg from acquisition-entitled fixed/zero payments, derives ICMA accrued interest from the same native coupon builder, adds it to clean cost, nets same-day receipts against that dirty outlay, normalizes the cash amounts, and calls CashFlows::yield with Brent, Actual365Fixed, annual compounding and an explicit acquisition valuation date. The solver stays above -100% and validates its result by repricing to the initial outlay. Undefined yields return an explicit availability flag; invalid input and convergence failures return bounded errors. No global evaluation date or fixing state is changed.


## Purchase yield verification (2026-10-17)

The pre-change macOS suite passed 258 tests. New schedule/transfer expectations failed against the approximation, then all 46 targeted tests passed with the solver. Before the clean-price correction, the complete macOS suite passed 271 tests with zero failures, covering dated purchase returns, same-day entitlement, adjusted redemption, long opening coupons, quarterly leap-year timing, deep negative yields, scaling, invalid native inputs, historical preservation and old/new native transfers. An independent read-only review found no actionable issues.

A universal Release build succeeded for arm64 and x86_64, and `scripts/verify-quantlib-build.sh` verified both architecture slices, bundled notices, signature and system-only runtime dependencies. Intel runtime execution was not performed. The standalone quick calculator remains approximate, and the investment-return convention can differ from broker market YTM.


## Clean-price correction verification (2026-10-17)

Acquisition cost was clarified as clean consideration. The prior cash-outlay-only calculation and its portfolio comparisons are superseded. Clean-price regressions failed before the correction; the corrected Carrefour fixture solves to 3.339409744% after adding ICMA accrued interest. The complete macOS suite passed 275 tests with zero failures, including long-stub accrual, same-day entitlement, native error handling and import compatibility for both prior yield conventions. Independent read-only review found no actionable issues.

The corrected universal Release build succeeded for arm64 and x86_64; the package verification script passed its architecture, signature, notices and system-dependency checks. Portfolio comparison is possible from legacy exported annual payments using explicitly inferred accrual periods, but reviewed-schedule verification requires the native terms sidecar. No local portfolio store, clean costs or historical rows were edited for the comparison.
