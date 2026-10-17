# QuantLib Integration Implementation Plan

> Implementation status (2026-10-17): implemented across all three stages. Full suite:248 tests passed; independent review findings fixed and rechecked; universal Release packaging and public3M/6M source/bootstrap checks passed. The copied app starts with an in-memory portfolio. Intel execution, interactive real-portfolio validation and network-denied startup remain unverified (the latter is blocked by nested macOS sandbox initialization). Commit and push of the completed work on the feature branch were explicitly authorized on 2026-10-17; no merge is authorized. Original step-by-step checklists below are retained as the design/TDD instructions; execution evidence and rulings are in `.superpowers/sdd/2026-10-16-quantlib-integration/progress.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Integrate QuantLib, bootstrap forward curves from source data, and support fixed, zero, floating and fixed-to-floating bond forecasts while preserving portfolio history and exports.

**Programme sequence:** This file contains Stage 1 (native fixed/zero engine). Then execute [Stage 2: market data and curve bootstrap](2026-10-16-quantlib-market-data.md), followed by [Stage 3: floating and fixed-to-floating](2026-10-16-quantlib-floating-forecasts.md). All three stages are required for the expanded user request; fixed/zero cutover alone is not completion.

**Architecture:** For Stage 1, keep `BondSchedule.preview(trade:terms:from:)` as the public application seam. A narrow C interface implemented in Objective-C++ calls statically linked QuantLib; Swift retains business validation, entitlement, identities and persistence. Delete superseded financial arithmetic after cutover; no runtime engine toggle, instrument catalogue or silent fallback.

**Tech Stack:** Swift 5 language mode, SwiftUI/Core Data, Objective-C++, C++20, QuantLib 1.44, Boost 1.88.0 headers, CMake, Xcode/macOS 15.0, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-16-quantlib-integration-design.md` (proposed scope; read together with this plan).

## Global Constraints

- No instrument-specific branches, ISIN lookup tables, issuer URLs or bundled instrument records in application code or configuration.
- macOS deployment target 15.0; Swift language mode 5.0; native bridge C++20; universal arm64 and x86_64 local app.
- Pin QuantLib 1.44 and Boost 1.88.0; static linking; no Python, server, Homebrew library, network or package installation required to run the delivered app.
- Stage 1 supports EUR fixed annual/semiannual/quarterly and zero coupons with ICMA/TARGET/Following. Stages 2-3 add sourced curves and EURIBOR floating phases; do not ship Stage 1 as the completed programme.
- Preserve explicit confirmed Fixed overrides and their constant-rate warning; genuine floating/fixed-to-floating remains unsupported only until Stage 3 is complete.
- Missing provider facts remain missing. Confirmed instrument terms are saved once per normalized ISIN; each purchase keeps its own trade and schedule.
- Contractual accrual dates stay unadjusted; payment adjustment adds no interest. Keep the original contractual maturity and actual redemption percentage.
- Unknown first-coupon dates and ambiguous rolls must not silently become guessed approvals. Preserve the historical-opening exclusion when neither possible opening payment enters the forecast.
- Stage 1 preserves legacy/native formats. Stage 3 versions native sidecar metadata with backward reading of version 1. Preserve approval/activation/history; no automatic startup/import approval.
- No silent fallback to the old financial engine after a native failure. Report errors per ISIN and allow other instruments to complete.
- Retain the existing Estimated YTM formula and label in this release; do not reinterpret purchase cost as a clean or dirty quote.

## Review Focus

1. A reference boundary before accrual start can change the ICMA denominator: Task 2 tests unknown roll rejection and both confirmed amounts.
2. A holiday can move an already-past contractual coupon into today's payment window: Task 3 tests pending payment inclusion without extra accrual.
3. Native exceptions or capacity errors must not crash the app or return partial success: Task 1 tests boundary failure and Task 4 tests per-ISIN isolation.
4. A changed engine must not alter already recorded money or duplicate a receipt: Task 4 tests history/event identities and read-only loading.
5. A local app must run on a Mac without developer libraries or internet: Task 5 tests both architecture slices, dynamic dependencies and copied-app offline operation.

---

## Execution context and file map

Active worktree inspected: `/Users/olivierelamine/.codex/worktrees/bond-terms-schedules/MyBondManager`, branch `codex/bond-terms-schedules`, HEAD `f1afab407c0b10592899921307c716c5890eade4` plus uncommitted reviewed fixes. Most recent full suite: 173 passing tests. Implementation must record a fresh baseline; this count is not evidence for a later checkout.

Use this worktree as the baseline; do not start from clean main and lose the pending fixes. Preserve all unrelated changes. Do not commit the entire dirty tree. If isolation is needed, use using-git-worktrees and include the authorized working state before implementing. The current request is planning only.

| File | Responsibility |
| --- | --- |
| `scripts/build-quantlib.sh` | Fetch/verify pinned dependencies; build universal static library and installed headers. |
| `scripts/verify-quantlib-build.sh` | Check versions, both architecture slices and offline link dependencies. |
| `Vendor/quantlib-versions.env` | Source versions/checksums; no instrument facts. |
| `Vendor/ThirdPartyNotices.txt` | QuantLib and Boost license notices, copied into app resources. |
| `.gitignore` | Ignore generated `Vendor/QuantLib/` and dependency caches only. |
| `MyBondManager/QuantLibBridge.h` | C-only request/result structs, version, payment generation and Following functions. |
| `MyBondManager/QuantLibBridge.mm` | Local QuantLib objects, date validation and exception translation. |
| `MyBondManager/MyBondManager-Bridging-Header.h` | Import the one C header. |
| `MyBondManager/QuantLibBondMath.swift` | Typed dates/results and safe C-buffer ownership. |
| `MyBondManager/BondSchedule.swift` | Existing eligibility and app flow mapping; delegate financial calculations. |
| `MyBondManager/TargetCalendar.swift` | Compatibility facade delegating to the same native TARGET implementation. |
| `MyBondManager.xcodeproj/project.pbxproj` | Static library/headers, bridge header, C++ runtime, notices resource. |
| `MyBondManagerTests/QuantLibBondMathTests.swift` | Real bridge and numeric fixtures; no mocked QuantLib. |
| `MyBondManagerTests/BondScheduleTests.swift` | Existing schedule contract plus cutover assertions. |
| `MyBondManagerTests/BondTermsReviewTests.swift` | Explicit apply, independent failures and no startup writes. |
| `MyBondManagerTests/BondTermsEventTests.swift` | Stable receipt identities and no rewritten history. |
| `MyBondManagerTests/BondTransferTests.swift` | Native and legacy compatibility. |
| `docs/quantlib-build.md`, `docs/portfolio-safeguards.md` | Build procedure, scope, warnings and operational limitations. |

### Verification commands used throughout

Run from the active worktree. No concurrent Xcode builds against the same derived-data path.

```sh
xcodebuild -project MyBondManager.xcodeproj -scheme MyBondManager   -configuration Debug -destination 'platform=macOS'   -derivedDataPath /tmp/MyBondManager-quantlib   CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= test
```

For a targeted RED run, add `-only-testing:MyBondManagerTests/QuantLibBondMathTests` before `test`. A compile failure for a newly introduced interface is an initial RED, but exception/capacity and numerical tests must also demonstrate behavioural RED against a linked implementation before completion. Run the complete suite at each task's GREEN gate. Use requesting-code-review for each task gate when the selected execution workflow requires it. Implement no production code in this planning turn.

## Task 1: Embed the pinned native library and prove the boundary is safe

**Files:** Create the two scripts, version lock, notices, bridge files, bridging header, Swift adapter and QuantLibBondMathTests; modify project settings and `.gitignore`.

**Interfaces:**
- Consumes: real calendar components; no Core Data or instrument identifiers.
- Produces: `QuantLibBondMath.version: String`, `QuantLibBondMath.following(_ day: MarketDay) throws -> MarketDay`, and the C contract below. Declare the payment function in this task; implement it in Task 2.

- [ ] **Step 1: Add the boundary tests.**

```swift
import XCTest
@testable import MyBondManager
final class QuantLibBondMathTests: XCTestCase {
    func testLinkedVersionAndFollowing() throws {
        XCTAssertEqual(QuantLibBondMath.version, "1.44")
        XCTAssertEqual(try QuantLibBondMath.following(MarketDay("2026-04-03")).rawValue, "2026-04-07")
        XCTAssertThrowsError(try QuantLibBondMath.following(MarketDay("1900-01-01")))
        XCTAssertThrowsError(try QuantLibBondMath.following(MarketDay("2200-01-01")))
    }
}
```

- [ ] **Step 2: Run the targeted tests and record RED.** Expected: missing adapter/native symbols; do not start by linking a dummy always-success function.

- [ ] **Step 3: Implement the dependency build.** Commit `Vendor/quantlib-versions.env` with these literal pins:

```sh
QUANTLIB_TAG=v1.44
QUANTLIB_COMMIT_PREFIX=ab4cb47
BOOST_VERSION=1.88.0
BOOST_ARCHIVE=boost_1_88_0.tar.gz
BOOST_SHA256=3621533e820dcab1e8012afd583c0c73cf0f77694952b81352bf38c1488f9cb4
```

Use `set -eu` and paths rooted in the script location. Download Boost from `https://archives.boost.io/release/1.88.0/source/boost_1_88_0.tar.gz`, check the literal SHA256 before extraction, and use its unpacked headers. Clone QuantLib from `https://github.com/lballabio/QuantLib.git` at the locked tag into an ignored cache. Check the resolved commit begins with the locked prefix, record its full SHA in the generated build manifest, and fail if an existing cache is dirty or on a different revision. Never reset a user's checkout. Build from source with these options for each architecture:

```sh
cmake -S "$ql_source" -B "$build_dir"   -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=20   -DCMAKE_OSX_DEPLOYMENT_TARGET=15.0 -DCMAKE_OSX_ARCHITECTURES="$arch"   -DCMAKE_INSTALL_PREFIX="$install_dir" -DBOOST_ROOT="$boost_source"   -DBUILD_SHARED_LIBS=OFF -DQL_BUILD_EXAMPLES=OFF -DQL_BUILD_TEST_SUITE=OFF   -DQL_INSTALL_EXAMPLES=OFF -DQL_INSTALL_TEST_SUITE=OFF   -DQL_USE_STD_SHARED_PTR=ON
cmake --build "$build_dir" --parallel 4
cmake --install "$build_dir"
```

The script loops `arch` over `arm64 x86_64`; `ql_source`, `boost_source`, `build_dir` and `install_dir` are absolute script-local paths under the ignored cache. Combine the two installed archives with `xcrun lipo -create`; require both installed public header trees to compare equal before copying one to `Vendor/QuantLib/include`. If architecture-dependent generated headers differ, stop and resolve that packaging problem; do not copy an incompatible config header. Output `Vendor/QuantLib/lib/libQuantLib.a` and a version/compiler/SDK manifest. Copy QuantLib LICENSE.TXT and Boost LICENSE_1_0.txt into the notices resource. Do not add an implicit network build phase to Xcode: developers run this script explicitly once; a missing artifact gives an actionable build error.

- [ ] **Step 4: Implement the C boundary and link it to Swift.** Use this complete public ABI; no C++ objects cross it:

```c
#ifndef MBM_QUANTLIB_BRIDGE_H
#define MBM_QUANTLIB_BRIDGE_H
#include <stddef.h>
#include <stdint.h>
#ifdef __cplusplus
extern "C" {
#endif
typedef struct {
    int32_t structure; /* 0 fixed, 1 zero */
    int32_t startDay, maturityDay, firstCouponDay; /* YYYYMMDD; first 0 means unknown */
    int32_t frequency; /* 1, 2, 4; ignored for zero */
    int32_t roll; /* 0 day-of-month, 1 month-end, 2 unknown */
    double nominal, annualRate, redemptionPercent; /* rate is decimal */
} MBMQLRequest;
typedef struct {
    int32_t kind; /* 0 interest, 1 redemption */
    int32_t contractualDay, paymentDay;
    double amount;
} MBMQLPayment;
const char *MBMQLVersion(void);
int MBMQLFollowing(int32_t day, int32_t *output, char *error, size_t errorCapacity);
int MBMQLPayments(const MBMQLRequest *request, MBMQLPayment *output,
                  size_t capacity, size_t *count, char *error, size_t errorCapacity);
#ifdef __cplusplus
}
#endif
#endif
```

Status values: `0` success, `1` invalid/unsupported terms, `2` insufficient capacity, `3` unexpected native failure. Always set count to zero before work; write results only after calculating and validating the entire vector. Error buffers are caller-owned and NUL-terminated when capacity > 0. Validate null pointers, finite doubles, positive nominal/redemption, actual calendar dates and year limits before QuantLib construction. Catch `std::exception` and unknown C++ exceptions at every C entry point; return a diagnostic, never a partial vector. `MBMQLVersion` returns `QL_VERSION`. `MBMQLFollowing` uses `TARGET().adjust(date, Following)` with explicit input/output year limits. Stage 1 calls never read or set an evaluation date. Stage 2 adds a shared native mutex plus SavedSettings for bootstrap; all later entries use that same guard.

Set the app target's `SWIFT_OBJC_BRIDGING_HEADER` to `MyBondManager/MyBondManager-Bridging-Header.h`; import QuantLibBridge.h there. Set app header search path to `$(SRCROOT)/Vendor/QuantLib/include`, library search path to `$(SRCROOT)/Vendor/QuantLib/lib`, linker flags to inherited flags plus `-lQuantLib -lc++`, and C++20/std-shared-ptr/config macros consistently with the built archive. Headers from the QuantLib install supply the configuration; do not invent a competing config header. The project uses filesystem-synchronized app sources, so verify .mm/header target membership rather than adding duplicate source entries.

In Swift, wrap the version with `String(cString: MBMQLVersion())`; convert dates through integer YYYYMMDD and `MarketDay`, never epoch offsets. Use `withUnsafeMutableBufferPointer` for 512-byte error buffers and native outputs; convert nonzero statuses to `PortfolioError` with the native diagnostic. Put no C pointer in persisted data.

- [ ] **Step 5: Add and run failure tests against the linked code.** Call `MBMQLFollowing` with `20260231`, a null output pointer and a one-byte error buffer; assert nonzero status and bounded writes. Retain a sentinel byte after the writable buffer and assert unchanged. Add a test that changes the process timezone from UTC to Pacific/Auckland and obtains the same `2026-04-07` answer. Restore the environment after the test. Run `bash scripts/verify-quantlib-build.sh` to check `lipo -archs` contains both slices and `QuantLibBondMath.version` is exactly 1.44; run the full suite.

```swift
func testMalformedNativeDateDoesNotOverwriteErrorBufferSentinel() {
    var result: Int32 = 0
    var bytes: [CChar] = [42, 99]
    let status = bytes.withUnsafeMutableBufferPointer { buffer in
        MBMQLFollowing(20260231, &result, buffer.baseAddress, 1)
    }
    XCTAssertNotEqual(status, 0)
    XCTAssertEqual(bytes[0], 0)
    XCTAssertEqual(bytes[1], 99)
}
```


- [ ] **Step 6: Review and commit only Task 1 files.**

```sh
git add scripts/build-quantlib.sh scripts/verify-quantlib-build.sh Vendor/quantlib-versions.env Vendor/ThirdPartyNotices.txt .gitignore MyBondManager/QuantLibBridge.h MyBondManager/QuantLibBridge.mm MyBondManager/MyBondManager-Bridging-Header.h MyBondManager/QuantLibBondMath.swift MyBondManagerTests/QuantLibBondMathTests.swift MyBondManager.xcodeproj/project.pbxproj
git commit -m "build: embed pinned QuantLib behind a safe native boundary"
```

Before staging any pre-existing modified file, inspect its diff and stage only the QuantLib changes; never include unrelated signing/scheme edits or earlier pending work accidentally.

## Task 2: Generate generic coupon legs and typed Swift payments

**Files:** Modify bridge/adapter and QuantLibBondMathTests.

**Interfaces:**
- Consumes: Task 1 C ABI, `BondTerms`, `MarketDay`.
- Produces: `struct QuantLibPayment: Equatable { let kind: BondPayment.Kind; let contractualDay: MarketDay; let paymentDay: MarketDay; let amount: Double }`; `QuantLibBondMath.payments(terms: BondTerms, nominal: Double) throws -> [QuantLibPayment]`.

- [ ] **Step 1: Add the numerical tests below and run targeted RED.**

```swift
func testLongFirstCouponAndLaterRegularCoupon() throws {
    var t = try BondTermsFixtures.fixed(frequency: 2, maturity: "2031-05-31", next: "2026-11-30")
    t.accrualStart = try MarketDay("2026-05-13")
    t.firstCoupon = try MarketDay("2026-11-30")
    t.couponRate = 6.875; t.roll = .endOfMonth
    let coupons = try QuantLibBondMath.payments(terms: t, nominal: 100000).filter { $0.kind == .interest }
    XCTAssertEqual(coupons.count, 10)
    XCTAssertEqual(try XCTUnwrap(coupons.first).amount, 3777.4725274725274, accuracy: 1e-8)
    XCTAssertEqual(coupons[1].amount, 3437.5, accuracy: 1e-8)
    XCTAssertEqual(coupons[1].contractualDay.rawValue, "2027-05-31")
}
```

- [ ] **Step 2: Implement the native fixed-leg core.** Convert only validated inputs. This is the core API construction, not a price/yield engine:

```cpp
const Period tenor(12 / frequency, Months);
Schedule schedule;
if (first == maturity) {
    const bool regular = NullCalendar().advance(maturity, -tenor, Unadjusted, endOfMonth) == start;
    schedule = Schedule(std::vector<Date>{start, maturity}, NullCalendar(),
                        Unadjusted, Unadjusted, tenor, DateGeneration::Backward,
                        endOfMonth, std::vector<bool>{regular});
} else {
    schedule = Schedule(start, maturity, tenor, NullCalendar(),
                        Unadjusted, Unadjusted, DateGeneration::Backward,
                        endOfMonth, first);
}
ActualActual dayCount(ActualActual::ISMA, schedule);
Leg coupons = FixedRateLeg(schedule)
    .withNotionals(nominal)
    .withCouponRates(annualRate, dayCount)
    .withPaymentCalendar(TARGET())
    .withPaymentAdjustment(Following);
```

Use each Coupon's accrualEndDate for contractualDay, `date()` for paymentDay and `amount()` for amount. Add one separate redemption payment at contractual maturity, adjusted independently with TARGET, amount nominal * redemptionPercent / 100. Zero structure skips Schedule/FixedRateLeg entirely, ignoring coupon metadata and returning redemption only. Check number of periods before publishing, maximum 1,201 output payments, finite amounts and chronological contractual dates. Do not attach a pricing engine.

Validate supplied firstDate against a separate backward regular grid constructed with the same maturity/tenor/roll before permitting it as a stub. For unknown roll, compare day-of-month and month-end candidate schedules, relevant reference boundaries and resulting coupon amounts; reject with 'Confirm the coupon month-end roll' when they differ. Do not collapse unknown roll to false. Reject unsupported frequency, invalid structure, nonfinite values and contradictory first dates at the bridge, even if Swift also checks them.

Build native output in a local vector, then validate capacity and copy once. Swift allocates 1,201 MBMQLPayment values, passes a capacity/count pair and accepts only a success status with count in 0...1201; convert unknown native kinds or malformed dates into an error. Map the validated fixed `terms.couponRate / 100` into annualRate; for zero structure send rate0, start0 and first0, ignoring unused coupon metadata. Never divide by 100 a second time. Do not pass ISIN, rawStructure, source URL, UUID or bank to native code.

- [ ] **Step 3: Add independent fixture rows to QuantLibBondMathTests and run GREEN.** Each row is an assertion on the real bridge. Use the existing fixture helper to set fields, with these literal expectations:

| Frequency | Accrual start | First coupon | Maturity | Annual % | Roll | First amount per 100000 |
| --- | --- | --- | --- | --- | --- | --- |
| 1 | 2025-05-23 | 2026-02-23 | 2036-02-23 | 4.625 | dayOfMonth | 3497.2602739726026 |
| 2 | 2024-02-15 | 2024-08-31 | 2026-08-31 | 6 | endOfMonth | 3230.7692307692305 |
| 4 | 2023-11-15 | 2024-03-31 | 2025-03-31 | 6 | endOfMonth | 2250 |
| 2 | 2024-12-15 | 2025-02-28 | 2025-02-28 | 6 | endOfMonth | 3000 * 75 / 181 |
| 2 | 2024-12-15 | 2025-02-28 | 2025-02-28 | 6 | dayOfMonth | 3000 * 75 / 184 |

The last two rows directly construct a single-period input; repeat with unknown roll and assert a confirmation error. Add a first-at-maturity long-period fixture (start2026-05-13, first/maturity2026-11-30, rate6.875%, semiannual, end-of-month): assert exactly one interest payment3777.4725274725274 and one redemption100000, with no phantom May coupon. Test first == accrualStart and first beyond maturity are rejected. Test a zero coupon with redemption105% returns one105000 payment despite nonsense frequency/next metadata. Test native capacity zero with a sentinel output buffer returns status2/count0 and leaves it untouched. Test 1,201 coupon periods are rejected. Add a concurrent 32-call test with different dates and assert identical independent output; it must not depend on Settings or a shared cache.

- [ ] **Step 4: Run the full suite, review and commit this task's bridge/adapter/tests.**

```sh
git add MyBondManager/QuantLibBridge.mm MyBondManager/QuantLibBondMath.swift MyBondManagerTests/QuantLibBondMathTests.swift
git commit -m "feat: calculate fixed and zero coupon payments with QuantLib"
```

## Task 3: Cut over the shared preview without changing app contracts

**Files:** Modify BondSchedule.swift, TargetCalendar.swift, BondScheduleTests.swift and TargetCalendarTests.swift. Preserve structs/signatures used by callers.

**Interfaces:**
- Consumes: `QuantLibBondMath.payments(terms:nominal:)` and `.following(_:)`.
- Produces: existing `BondSchedule.preview(trade: BondTrade, terms: BondTerms, from: MarketDay) throws -> BondSchedulePreview`, with identical event-key and flow-nature contracts; TargetCalendar.following retains its signature; remove the internal-only isBusinessDay helper after verifying its callers.

- [ ] **Step 1: Add targeted cutover tests and record RED.**

```swift
func testNativePreviewRejectsUnrepresentableDateExplicitly() throws {
    var t = try BondTermsFixtures.fixed(frequency: 1, maturity: "1900-12-31", next: "1900-12-31")
    t.accrualStart = try MarketDay("1900-01-01")
    t.checkpointObservedOn = try MarketDay("1900-06-01")
    let trade = BondTrade(id: UUID(), isin: t.isin, nominal: 100000, cost: 99000,
                          acquisitionDay: try MarketDay("1900-01-01"), bank: "Fixture")
    let p = try BondSchedule.preview(trade: trade, terms: t, from: MarketDay("1900-06-01"))
    XCTAssertFalse(p.assessment.supported)
    XCTAssertTrue(p.assessment.reasons.contains { $0.contains("1901") })
}
```

Also extend the existing contradictory-checkpoint test to require the diagnostic to name supplied checkpoint, expected checkpoint and observation day. This fails before replacing the current generic error; use anonymous dates from BondTermsFixtures.

- [ ] **Step 2: Replace only the financial kernel.** Keep input/structure/convention checks, missing-field handling, call/deferral/Fixed-override warnings and purchase validation in Swift. Before bridge invocation, return unsupported reasons for dates outside1901...2199. Obtain native payments with:

```swift
let calculated = try QuantLibBondMath.payments(terms: terms, nominal: trade.nominal)
let coupons = calculated.filter { $0.kind == .interest }
let payments = calculated.filter {
    $0.contractualDay >= trade.acquisitionDay && $0.paymentDay >= from
}
```

For Stage1, keep the source native coupon list before entitlement filtering. Stage3 splits full contractual-date generation from windowed amount/fixing resolution so irrelevant historical floating coupons need no fixings. Keep the full contractual-date list to validate `first(where: contractualDay >= checkpointObservedOn)` against terms.nextCoupon. Supply an actionable mismatch diagnostic with actual/expected/observed dates; do not silently update a user's confirmed checkpoint. If firstCoupon is missing and the start is off-grid, retain the existing conservative two-potential-opening-payment exclusion and warnings using native contractual/payment dates. Test those excluded payments against both acquisition and adjusted payment windows before discarding; do not let QuantLib's inferred stub become an approved payment. Use the existing historical-opening regression cases as acceptance tests.

Map each result into the existing BondPayment and ProjectedFlow types; create exactly the current event keys `UUID|interest|YYYY-MM-DD` and `UUID|maturity|YYYY-MM-DD`. Keep the current principal/gain/loss and expectedProfit decomposition in Swift. Keep acquisition-cost and Estimated YTM semantics and labels. Delete openingYearFraction and the old maturity stepping/coupon-amount loops after the cutover; do not keep a runtime fallback.

Replace TargetCalendar.following with a direct call to QuantLibBondMath.following and remove its internal-only isBusinessDay and Easter computus helpers. Inspection found no external callers of isBusinessDay; confirm this with `rg` before deletion. Keep `.following(_:)` throwing; no extra native calendar interface is needed. No calendar date arithmetic should remain duplicated in Swift; MarketDay retains representation/conversion/month utilities needed outside finance.

- [ ] **Step 3: Run the existing schedule/calendar suite unchanged except documented diagnostic/range updates.** Assert annual/semiannual/quarterly regular amounts, short/long first periods, mid-period purchases, zero structure, redemption not100%, genuine floating rejection and explicit Fixed override warning. Add the following payment-window test:

```swift
func testPastContractualCouponDelayedByTARGETRemainsPayable() throws {
    var t = try BondTermsFixtures.fixed(frequency: 1, maturity: "2027-01-01", next: "2027-01-01")
    t.accrualStart = try MarketDay("2026-01-01")
    t.checkpointObservedOn = try MarketDay("2026-12-31")
    let p = try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: t, from: MarketDay("2027-01-02"))
    let interest = try XCTUnwrap(p.payments.first { $0.kind == .interest })
    XCTAssertEqual(interest.contractualDay.rawValue, "2027-01-01")
    XCTAssertEqual(interest.paymentDay.rawValue, "2027-01-04")
    XCTAssertEqual(interest.amount, 3375, accuracy: 1e-8)
}
```

- [ ] **Step 4: Full-suite GREEN, inspect every direct preview caller listed in the spec's file map, review and commit the cutover only.**

```sh
git add MyBondManager/BondSchedule.swift MyBondManager/TargetCalendar.swift MyBondManager/QuantLibBridge.h MyBondManager/QuantLibBridge.mm MyBondManager/QuantLibBondMath.swift MyBondManagerTests/BondScheduleTests.swift MyBondManagerTests/TargetCalendarTests.swift
git commit -m "refactor: route bond previews through QuantLib"
```

## Task 4: Pin review, persistence, transfer and history behaviour

**Files:** Modify BondTermsReviewTests, BondTermsEventTests, BondTransferTests and portfolio-safeguards.md; change production store/review/transfer code only for a reproduced incompatibility.

**Interfaces:** Consumes the unchanged preview and existing `BondTermsReview.collect/edit/apply`, `BondTransfer.snapshot/encode/prepare`, `ImportManager.applyBonds` and `LaunchEventProcessor.stage`. Produces no new storage format or schema.

- [ ] **Step 1: Extend the existing long-first-coupon integration test with a third, unsupported instrument.** Use two purchases of one anonymous ISIN with manually saved firstCoupon2026-11-30 and a second anonymous ISIN with start1900-01-01. Apply both ISINs; assert exactly the supported two purchase IDs in report.appliedHoldingIDs and only the invalid ISIN in report.failures. Ensure load alone saves no drafts or profiles. Use the current service now closure fixed to2026-10-16T12:00:00Z; retain purchase-specific nominal/cost/acquisition fixtures.

- [ ] **Step 2: Pin the money/history outcomes with literal assertions.** Extend the existing native roundtrip/event tests rather than creating another persistence abstraction:

```swift
XCTAssertEqual(report.appliedHoldingIDs.count, 2)
XCTAssertEqual(report.failures.count, 1)
XCTAssertEqual(rows.count, 2)
XCTAssertEqual(rows.reduce(0) { $0 + ($1.interestReceived?.doubleValue ?? 0) },
               7554.945054945055, accuracy: 1e-8)
XCTAssertTrue(try LaunchEventProcessor.stage(context: reader, since: importedAt, until: until).isEmpty)
```

Here `rows` are fetched after first-coupon recording on the imported in-memory destination, `importedAt` is2026-10-17T12:00:00Z and `until` is2026-12-01T12:00:00Z. Verify source history row count and values remain byte-for-byte/logically unchanged before and after explicit approval. Native transfer preserves confirmed fields, source metadata, deferral and activation. Legacy export retains its exact existing key set and ignores additional native calculation details. Reopening/refreshing/reapplying must not duplicate receipts. Deferrable payments still produce no automatic receipt.

- [ ] **Step 3: Reproduce failures before any persistence production fix.** If these tests pass immediately, they characterize compatibility and justify leaving production persistence unchanged. If any fail, name the exact failing assertion and fix only its caller; do not rewrite fixtures to match new engine output. Treat a changed historical amount as an error requiring explicit review, never an automatic correction.

- [ ] **Step 4: Run the complete suite, update safeguards to say QuantLib is active for fixed/zero schedules while YTM remains estimated, review and commit.**

```sh
git add MyBondManagerTests/BondTermsReviewTests.swift MyBondManagerTests/BondTermsEventTests.swift MyBondManagerTests/BondTransferTests.swift docs/portfolio-safeguards.md
git commit -m "test: preserve portfolio history and transfer contracts with QuantLib"
```

## Task 5: Deliver a self-contained local build and remove obsolete arithmetic

**Files:** Modify verify-quantlib-build.sh and notices/build documentation; inspect the cutover for unused arithmetic. No ETF changes, no new telemetry or market-data service.

**Interfaces:** Consumes generated static artifact and the app target. Produces a copied, signed local Release app and reproducible build instructions; no push, merge or live-data migration is implicit.

- [ ] **Step 1: Add script assertions before fixing packaging.** `verify-quantlib-build.sh` must fail if either architecture slice or notices resource is absent, or if `otool -L` on the executable lists `/opt/homebrew`, `/usr/local`, a build-cache absolute path or QuantLib/Boost dylib. It must inspect `lipo -archs` for both archive and executable. Check arm64/x86_64 link builds separately with `ARCHS` overrides before claiming universal build support; a slice inspection does not prove execution on the other CPU.

- [ ] **Step 2: Build and inspect the universal Release app.**

```sh
xcodebuild -project MyBondManager.xcodeproj -scheme MyBondManager   -configuration Release -destination 'generic/platform=macOS'   -derivedDataPath /tmp/MyBondManager-quantlib   ARCHS='arm64 x86_64' ONLY_ACTIVE_ARCH=NO   CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build
bash scripts/verify-quantlib-build.sh /tmp/MyBondManager-quantlib/Build/Products/Release/MyBondManager.app
codesign --verify --deep --strict /tmp/MyBondManager-quantlib/Build/Products/Release/MyBondManager.app
```

Copy the app to `/tmp/MyBondManager-QuantLib/MyBondManager.app`. Use an isolated test portfolio/container for a real copied-app launch offline; never open the user's live database just to smoke test. If the app has no existing isolated launch option, document a separate macOS test account as the manual verification route rather than adding an app configuration feature solely for this test. A second Mac test confirms deployment without CMake, Boost, Python or a compiler; record unavailable Intel execution honestly rather than equating arm64 testing with both CPUs.

- [ ] **Step 3: Run full tests and final branch review.** Ensure the Swift ICMA helper and Easter computus are removed, no native errors fall back silently, and no instrument identifiers or issuers appear in production rules. Retain current app behaviour for calls, deferrals and constant-rate overrides. Preserve the old app as rollback until the user validates the new build. Rollback changes the app binary, not history or database schema.

- [ ] **Step 4: Write docs/quantlib-build.md with the exact pinned versions, bootstrap command, generated paths, Xcode commands, dependency manifest, supported scope, date range, failure handling and local build path.** Include notices in the app and document that missing ING facts still require manual terms, and genuine floating support requires the subsequent Stage 2-3 deliverables. Record actual test/build/UI/CPU evidence separately.

- [ ] **Step 5: Commit packaging/docs after successful review.** Stage only task-owned files and inspected arithmetic deletions. Do not push or merge without the user's instruction.

```sh
git add scripts/verify-quantlib-build.sh Vendor/ThirdPartyNotices.txt docs/quantlib-build.md docs/portfolio-safeguards.md
git commit -m "build: verify self-contained QuantLib local release"
```

## Self-review and acceptance checklist

- [ ] Fixed/zero calculations use the real native library; anonymous numeric tests exercise it.
- [ ] Unknown first dates/rolls and checkpoint conflicts cannot become guessed approvals.
- [ ] Confirmed Fixed overrides, conditional-payment safeguards and per-ISIN partial success remain intact.
- [ ] No history rewrite, startup approval, schema/legacy JSON change or instrument-specific fallback.
- [ ] Both CPU slices link; actual runtime coverage is reported accurately.
- [ ] No obsolete financial kernel or implicit old-engine fallback; Estimated YTM remains honestly labelled.
- [ ] Reproducible dependency bootstrap, source/version manifest and bundled notices verified.

Planning self-review performed: file ownership, boundary signatures, five Review Focus risks and test ownership have been mapped. Production compilation, dependency bootstrap, bridge API behaviour and runtime packaging are deliberately unverified until execution. The plan and companion design are proposals for user review, not claims of an integrated QuantLib app.

## Expanded-scope self-review

The user explicitly included floating/fixed-to-floating forecasting and directed the curve build to use the Bridge repository as reference. The linked Stage 2 and Stage 3 plans implement those requirements. Preserve the native dependency and fixed-engine tasks here; the stages share named interfaces and can each be reviewed as a working deliverable. No implementation method has yet been selected.
