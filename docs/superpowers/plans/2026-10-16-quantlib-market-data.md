# QuantLib Market Data and Curve Bootstrap Implementation Plan

> Implementation status (2026-10-17): implemented across all three stages. Full suite:248 tests passed; independent review findings fixed and rechecked; universal Release packaging and public3M/6M source/bootstrap checks passed. The copied app starts with an in-memory portfolio. Intel execution, interactive real-portfolio validation and network-denied startup remain unverified (the latter is blocked by nested macOS sandbox initialization). Commit and push of the completed work on the feature branch were explicitly authorized on 2026-10-17; no merge is authorized. Original step-by-step checklists below are retained as the design/TDD instructions; execution evidence and rulings are in `.superpowers/sdd/2026-10-16-quantlib-integration/progress.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Fetch dated EURIBOR inputs, bootstrap usable projection curves locally, and preserve immutable snapshots for offline and reproducible floating forecasts.

**Architecture:** Port Bridge's source parsing and bootstrap recipe into native MyBondManager components; do not call Bridge at runtime or embed Python/Postgres. A small file catalogue stores financial input snapshots, while the native bridge calculates forwards from raw quotes. Importing dated JSON quote/fixing files remains an alternative to online refresh.

**Tech Stack:** URLSession, XMLParser, Codable/CryptoKit, QuantLib1.44 C++20 static bridge from Stage1, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-16-quantlib-integration-design.md`; prerequisite `2026-10-16-quantlib-integration.md` Tasks1-5.

## Global Constraints

- No instrument-specific branches, ISIN lookup tables, issuer URLs or bundled instrument records in application code or configuration.
- Pin QuantLib1.44/Boost1.88.0; run locally without Python or Bridge services.
- Source dates, units, index tenor and bootstrap method are explicit; no curve cloning between indices.
- Keep immutable raw financial inputs and calibration diagnostics, not serialized QuantLib objects or guessed future fixings.
- Source refresh does not approve terms or change portfolio forecasts/history.
- Feed failures preserve the last successful snapshot. No mixed-date fixing/swap bundle is silently published.
- Two TARGET business days defines stale; no silent curve extrapolation.
- Offline JSON import is retained; live API reachability remains an execution-time check.

## Review Focus

1. Percent-versus-decimal confusion: Task1 fixture parsing asserts2.642% becomes0.02642 exactly once.
2. Two source feeds on different days: Task1 rejects the combined bundle and preserves the current snapshot.
3. A bootstrap can succeed while not repricing inputs: Task2 asserts every deposit/swap residual and Bridge forward references.
4. Missing/negative fixings and future-dated records: Tasks1-2 allow negative rates but reject future published observations and missing dates.
5. Refresh interrupts offline use or overwrites an unchanged snapshot: Task3 tests failure preservation, content identity and explicit adoption only.

---

## Reference and file map

Read-only Bridge evidence: `/Users/olivierelamine/Developer/bridge-app` at HEAD7e288ac7460dd7d1662bc5b573a39d2db84b4d1e. Use services/external_sources_client.py, euribor_curve_source.py, bundesbank_client.py, ql/euribor_bootstrap.py, domain/market_data.py and tests/test_euribor_bootstrap*.py. Do not edit Bridge or use its .env, database, login session or runtime market cache.

Create `MyBondManager/MarketDataTypes.swift`, `MarketDataSources.swift`, `MarketDataClient.swift`, `MarketDataStore.swift`, `MarketDataView.swift`, `CurveBootstrap.hpp`, `CurveBootstrap.cpp`, and resource `MarketDataSources.plist`. Modify the native C bridge and Swift adapter. Add `MarketDataTests.swift`, `CurveBootstrapTests.swift`, `MarketDataStoreTests.swift`, and recorded public fixture JSON/XML under MyBondManagerTests. Add a Market Data entry in MainTabView. No Core Data model change.

The native bridge never accepts an ISIN. The file catalogue contains market indices/quotes only. Profiles in Stage3 embed selected snapshot values, not machine-specific file paths.

## Task 1: Fetch, parse and validate source quotes and historical fixings

**Files:** MarketDataTypes.swift, MarketDataSources.swift, MarketDataClient.swift, MarketDataSources.plist, MarketDataTests.swift and recorded source fixtures.

**Interfaces:** Define these Codable/Equatable/Sendable values. All dates are MarketDay and all rates are decimals unless named spreadBps.

```swift
struct SwapMarketQuote: Codable, Equatable, Sendable { let years: Int; let rate: Double }
struct PublishedFixing: Codable, Equatable, Sendable { let day: MarketDay; let rate: Double }
struct CurveMarketQuotes: Codable, Equatable, Sendable {
    let indexTenorMonths: Int
    let quoteDay: MarketDay
    let depositRate: Double
    let swaps: [SwapMarketQuote]
}
struct MarketDataPayload: Codable, Equatable, Sendable {
    let formatVersion: Int // 1
    let method: String // euribor-singlecurve-v1
    let sourceName: String
    let quotes: CurveMarketQuotes
    let historicalFixings: [PublishedFixing]
}
struct CurveCalibrationDiagnostics: Codable, Equatable, Sendable {
    let quantLibVersion: String
    let maxDepositResidual: Double
    let maxSwapResidual: Double
    let lastCurveDay: MarketDay
}
struct MarketDataSnapshot: Codable, Equatable, Sendable {
    let id: String // SHA256 of canonical payload + calibration; excludes retrieval time
    let payload: MarketDataPayload
    let calibration: CurveCalibrationDiagnostics
    let retrievedAt: Date // excluded from financial content identity
}
struct ParsedPublicRates: Equatable, Sendable {
    let quoteDay: MarketDay
    let decimalRatesByMonths: [Int: Double]
}
```

`MarketDataClient.parseRates(_ bytes: Data) throws -> ParsedPublicRates`, `.parseFixings(_ bytes: Data, pricingDay: MarketDay) throws -> [PublishedFixing]`, and `.fetch(indexTenorMonths: Int, pricingDay: MarketDay) async throws -> MarketDataPayload` use an injected URLSession and source configuration. Expose `.decodeImport(_ bytes: Data, pricingDay: MarketDay) throws -> MarketDataPayload` for the same normalized financial contract.

- [ ] **Step1: Add the parser RED tests using captured public responses.**

```swift
func testPublicRateUnitsAndDateArePreserved() throws {
    let bytes = Data(#"{"PreviousDayDate":"2026-10-08","Rates":[{"LengthInMonths":3,"PreviousDay":"2.642"}]}"#.utf8)
    let parsed = try MarketDataClient.parseRates(bytes)
    XCTAssertEqual(parsed.quoteDay.rawValue, "2026-10-08")
    XCTAssertEqual(try XCTUnwrap(parsed.decimalRatesByMonths[3]), 0.02642, accuracy: 1e-12)
}
func testNegativeFixingIsNotFloored() throws {
    let bytes = Data(#"{"PreviousDayDate":"2026-10-08","Rates":[{"LengthInMonths":3,"PreviousDay":"-0.5"}]}"#.utf8)
    XCTAssertEqual(try MarketDataClient.parseRates(bytes).decimalRatesByMonths[3], -0.005)
}
```

Run the Stage1 xcodebuild test command with `-only-testing:MyBondManagerTests/MarketDataTests`; record the missing-interface/parser failure.

- [ ] **Step2: Implement source configuration and HTTP clients.** Defaults are a provider configuration, not an instrument catalogue:

| Purpose | Default URL/feed |
| --- | --- |
| Fixing/deposit quotes | https://cf.com/public-api/public-rates/eurlibor.json/ |
| 3M swap quotes | https://cf.com/public-api/public-rates/euriborswap.json/ |
| 6M swap quotes | https://cf.com/public-api/public-rates/euribor6monthswap.json/ |
| Historical3M | https://api.statistiken.bundesbank.de/rest/data/BBIG1/D.D0.EUR.MMKT.EURIBOR.M03.BID._Z |
| Historical6M | same path with M06; M01/M12 used for manually sourced1M/12M curves |

Keep endpoint URLs editable, HTTPS only, no embedded credentials. Apply15-second request timeouts and10MB response caps. Match Bridge's JSON Accept/Accept-Language/browser user-agent/Origin/Referer requirements for public feeds; do not follow redirects into HTML or login pages. Return actionable HTTP/timeout/format errors. XMLParser disables external entity resolution; read SDMX ObsDimension and ObsValue, skip observations with no published value, sort dates and reject conflicting duplicate observations. Import has the same rules as fetch and reports the offending field/date.

`fetch` selects the deposit quote matching the requested tenor and its own swap feed. Require swap maturities1,2,3,5,7,10,15,30years. Reject missing/nonfinite quotes, duplicate pillars and mismatched quote dates; do not use a12M deposit quote instead of the1Y swap. Reject quote/fixing dates later than pricingDay. Date provenance remains in the payload. Automatic1M/12M quote refresh reports 'No automatic quote source; import matching quotes'; it never substitutes3M/6M.

Normalized JSON import is a MarketDataPayload object with formatVersion1, method euribor-singlecurve-v1, sourceName, quotes and historicalFixings. Publish example JSON generated from the public test fixtures. Reject unknown versions/index tenors, duplicate dates and unit ambiguity; the schema mandates decimal values. It imports market inputs, never holdings or instrument terms.

- [ ] **Step3: Test failure and mixed-date paths through URLProtocol fixtures.** Copy only public raw fixture bodies from Bridge's test fixtures into MyBondManager tests. Send fixing quoteDay2026-10-08 with swap quoteDay2026-10-07 and assert fetch throws before returning a payload. Assert redirect301, HTML200, malformed XML, empty required swap list, unexpected JSON keys/types and timeout cannot return a successful payload. Historical XML with a missing holiday observation must skip that row, while duplicate date/different rate must fail. These tests exercise the real parser/client below an HTTP fixture, not a mocked fetch method.

- [ ] **Step4: Run full suite, review and commit Task1 files only.**

```sh
git add MyBondManager/MarketDataTypes.swift MyBondManager/MarketDataSources.swift MyBondManager/MarketDataClient.swift MyBondManager/MarketDataSources.plist MyBondManagerTests/MarketDataTests.swift MyBondManagerTests/Fixtures
git commit -m "feat: fetch and import dated EURIBOR market inputs"
```

## Task 2: Bootstrap the full native curve using Bridge's recipe

**Files:** CurveBootstrap.hpp/.cpp, QuantLibBridge.h/.mm, QuantLibBondMath.swift, CurveBootstrapTests.swift and fixtures.

**Interfaces:** Native C++ `buildProjectionCurve(const MBMQLCurveRequest&) -> QuantLib::ext::shared_ptr<QuantLib::YieldTermStructure>` is declared in CurveBootstrap.hpp for reuse by Stage3. Its input arrays live only for the call.

```c
typedef struct { int32_t years; double rate; } MBMQLSwapQuote;
typedef struct {
    int32_t quoteDay, indexTenorMonths;
    double depositRate;
    const MBMQLSwapQuote *swaps;
    size_t swapCount;
} MBMQLCurveRequest;
typedef struct { int32_t fixingDay; } MBMQLForwardProbe;
typedef struct { int32_t fixingDay, valueDay, indexEndDay; double rate; } MBMQLForwardResult;
typedef struct {
    double maxDepositResidual, maxSwapResidual;
    int32_t lastCurveDay;
} MBMQLCurveDiagnostics;
int MBMQLCurveForwards(const MBMQLCurveRequest *request,
    const MBMQLForwardProbe *probes, size_t probeCount,
    MBMQLForwardResult *output, size_t capacity, size_t *count,
    MBMQLCurveDiagnostics *diagnostics, char *error, size_t errorCapacity);
```

Swift produces `ForwardObservation(fixingDay: MarketDay, valueDay: MarketDay, indexEndDay: MarketDay, rate: Double)` and `CurveCalculationResult { let observations: [ForwardObservation]; let calibration: CurveCalibrationDiagnostics }`. `QuantLibBondMath.forwards(quotes: CurveMarketQuotes, fixingDays: [MarketDay]) throws -> CurveCalculationResult` returns both. An empty fixingDays request validates/reprices the curve and returns diagnostics without probes; permit a null output pointer only for that zero-probe case. No extrapolation flag is exposed. All C calls use one shared mutex; bootstrap sets evaluationDate under SavedSettings and restores it even after errors. Never populate global IndexManager fixing histories.

- [ ] **Step1: Write RED tests using the public Bridge2026-10-08 inputs.** Define `MarketDataFixtures.quotes3M()` and `.quotes6M()` in test utilities with these literal decimal rates:

```swift
// 3M deposit 0.02642; swaps(year:rate):
// 1:.03037, 2:.03205, 3:.03264, 5:.03287, 7:.03327, 10:.03407, 15:.03508, 30:.03384
// 6M deposit 0.02936; swaps:
// 1:.03172, 2:.03331, 3:.03384, 5:.03395, 7:.03424, 10:.03486, 15:.03555, 30:.03383
func testThreeMonthCurveReproducesRecordedBridgeForward() throws {
    let values = try QuantLibBondMath.forwards(quotes: MarketDataFixtures.quotes3M(),
        fixingDays: [MarketDay("2026-10-08"), MarketDay("2027-04-08")])
    XCTAssertEqual(values.observations[0].valueDay.rawValue, "2026-10-12")
    XCTAssertEqual(values.observations[0].rate, 0.02642, accuracy: 1e-6)
    XCTAssertEqual(values.observations[1].valueDay.rawValue, "2027-04-12")
    XCTAssertEqual(values.observations[1].rate, 0.030998676706575447, accuracy: 1e-6)
}
```

The3M April literal was independently recomputed during implementation using Bridge's standalone PythonQuantLib1.43 recipe; the earlier approximate0.031001 was inaccurate at the specified tolerance. MonotonicLogCubic explicitly matches the wrapper's spline/monotonic defaults. These forwards correspond to the same index underlying period used by Bridge, not a date mislabeled as a fixing. Also test6M spot0.02936 and April forward0.0327148 with the same fixing/value dates. Run targeted RED before implementing.

- [ ] **Step2: Implement the actual QuantLib bootstrap.**

```cpp
SavedSettings saved;
Settings::instance().evaluationDate() = quoteDate;
auto index = ext::make_shared<Euribor>(Period(indexTenorMonths, Months));
std::vector<ext::shared_ptr<RateHelper>> helpers;
helpers.push_back(ext::make_shared<DepositRateHelper>(
    Handle<Quote>(ext::make_shared<SimpleQuote>(depositRate)), index));
for (const auto& swap : swaps) {
    helpers.push_back(ext::make_shared<SwapRateHelper>(
        Handle<Quote>(ext::make_shared<SimpleQuote>(swap.rate)), Period(swap.years, Years),
        TARGET(), Annual, ModifiedFollowing, Thirty360(Thirty360::BondBasis), index));
}
auto curve = ext::make_shared<PiecewiseYieldCurve<Discount, MonotonicLogCubic>>(
    quoteDate, helpers, Actual365Fixed());
curve->discount(curve->maxDate()); // force bootstrap before accepting the snapshot
```

Check each helper's impliedQuote against its input at absolute tolerance1e-6; fail the build if a helper does not reprice. Force calculation then freeze the piecewise curve. Hold the same mutex across construction, repricing and all forward queries; do not return live pointers to Swift or query a relative-date helper after releasing its explicit evaluation-date scope. Stage3 calls this helper inside its guarded request as well.

For each query: construct the tenor-matching Euribor with the new projection handle, then calculate valueDate(fixingDate) and maturityDate(valueDate). Query simple ACT/360 forward over that underlying period. Reject valueDate before curve reference or index maturity after maxDate; never clamp to the first rate or enable extrapolation. Preserve the full curve from quote helpers, not Bridge's121 monthly forward points. No government discount curve or bond pricing engine is needed to project coupon rates.

- [ ] **Step3: Test bootstrap/domain failures and state restoration.** Return the maximum deposit/swap repricing residual and last curve day through the diagnostic output used by the production Market Data inspector and persisted snapshot. Assert each maximum<=1e-6, and test individual pillar corruption causes explicit failure. Do not add a production method used only by tests. Assert duplicate swap years, NaN, missing1Y, impossible quote combinations and horizon beyond30Y fail. Feed negative rates that remain mathematically valid and assert no zero floor. Run32 alternating quote dates/tenors plus one throwing case and verify subsequent outputs match the same-date golden fixture; no evaluation date or market history leaks between requests. Inspect the existing Stage1 date/version calls under that concurrency test, using the same mutex.

- [ ] **Step4: Full-suite GREEN, inspect primary C++ API against the pinned release, review and commit.**

```sh
git add MyBondManager/CurveBootstrap.hpp MyBondManager/CurveBootstrap.cpp MyBondManager/QuantLibBridge.h MyBondManager/QuantLibBridge.mm MyBondManager/QuantLibBondMath.swift MyBondManagerTests/CurveBootstrapTests.swift MyBondManagerTests/MarketDataFixtures.swift
git commit -m "feat: bootstrap EURIBOR projection curves from source quotes"
```

## Task 3: Store snapshots and expose explicit source refresh/import

**Files:** MarketDataStore.swift, MarketDataView.swift, MainTabView.swift, MarketDataStoreTests.swift, docs/quantlib-market-data.md.

**Interfaces:** `MarketDataStore.save(_ payload: MarketDataPayload, retrievedAt: Date) throws -> MarketDataSnapshot`, `.load(id: String) throws -> MarketDataSnapshot`, `.list() throws -> [MarketDataSnapshot]`. Inject the catalogue directory so tests use temporary folders. Production uses Application Support/MarketData in the sandbox. Snapshot id hashes canonical sorted-key payload plus calibration diagnostics; retrieval time is metadata, so fetching identical content does not create duplicates. Snapshot files are immutable; an existing hash with different content is corruption, never overwrite it.

- [ ] **Step1: Write the catalogue RED test.**

```swift
func testIdenticalMarketInputsDoNotCreateDuplicateSnapshots() throws {
    let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: directory) }
    let store = MarketDataStore(directory: directory)
    let first = try store.save(MarketDataFixtures.payload3M(), retrievedAt: Date(timeIntervalSince1970: 1))
    let second = try store.save(MarketDataFixtures.payload3M(), retrievedAt: Date(timeIntervalSince1970: 2))
    XCTAssertEqual(first.id, second.id)
    XCTAssertEqual(try store.list().count, 1)
}
```

`MarketDataFixtures.payload3M()` wraps quotes3M with formatVersion1/method euribor-singlecurve-v1, sourceName Fixture and a sorted published-fixing list. Keep fixture constructors in test utilities, not production.

- [ ] **Step2: Implement validation-before-publication and atomic writes.** Decode/validate inputs, call `QuantLibBondMath.forwards(quotes: payload.quotes, fixingDays: [])`, retain its calibration diagnostics and only then atomically write the snapshot. Hash a sorted-key Codable fingerprint containing payload and calibration, excluding retrievedAt; verify the same fingerprint on load/import. A validation/native/HTTP error cannot publish a partly populated payload. Same-date quote corrections or added historical observations create a different hash; retain both versions. A source refresh may not replace a newer quote-date selection with older source data. Identical content produces no write. Source and fixing metadata stay inspectable and travel with exports in Stage3.

- [ ] **Step3: Add Market Data UI.** Show index, source date, retrieval time, freshness, coverage and last error; actions are Refresh source data, Import dated inputs and Inspect. Display3M/6M availability and1M/12M manual-only status. Default curve selection is not a portfolio mutation. No startup network dependency. Refresh is cancellable, caches last successful results, avoids duplicate concurrent per-index requests and throttles automatic retries15minutes if auto-refresh is later explicitly enabled. This stage adds only explicit refresh; do not add background automation.

Test: after one successful snapshot, simulate HTTP403 and malformed input and assert the catalogue/hash and all holding/profile/history data remain unchanged. Assert a quote date older than two TARGET days gets a stale label; do not count calendar weekends as business days. Import malformed JSON after a good snapshot must leave it available offline. A subsequent newer valid snapshot must appear without approving any bond.

- [ ] **Step4: Full-suite/review and source smoke test.** Verify public endpoint access with ordinary app requests, without accessing private/login-gated alternatives. If blocked, retain the dated import route and report the exact source failure; fixture tests are not live-source proof. Confirm Bridge remains unmodified. Document single-curve/no-FRA limits and that swap helpers use benchmark market conventions, which differ from a particular bond's coupon conventions.

- [ ] **Step5: Commit task files and hand off the snapshot/curve contracts to Stage3.**

```sh
git add MyBondManager/MarketDataStore.swift MyBondManager/MarketDataView.swift MyBondManager/MainTabView.swift MyBondManagerTests/MarketDataStoreTests.swift docs/quantlib-market-data.md
git commit -m "feat: manage reproducible market snapshots in the Mac app"
```

## Completion checks

- All three tasks GREEN with independent numeric fixtures and per-source errors.
- Full native curves are built from raw source quotes, not an imported finished curve or resampled monthly forwards.
- No Bridge modification/runtime dependency, credential copying or instrument-specific facts.
- Historical fixings remain distinct from curve predictions; immutable snapshots work offline.
- Stage3 is still required before floating instruments can become approved forecasts.
