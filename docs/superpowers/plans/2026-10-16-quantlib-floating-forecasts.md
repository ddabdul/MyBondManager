# QuantLib Floating and Fixed-to-Floating Forecasts Implementation Plan

> Implementation status (2026-10-17): implemented across all three stages. Full suite:248 tests passed; independent review findings fixed and rechecked; universal Release packaging and public3M/6M source/bootstrap checks passed. The copied app starts with an in-memory portfolio. Intel execution, interactive real-portfolio validation and network-denied startup remain unverified (the latter is blocked by nested macOS sandbox initialization). Commit and push of the completed work on the feature branch were explicitly authorized on 2026-10-17; no merge is authorized. Original step-by-step checklists below are retained as the design/TDD instructions; execution evidence and rulings are in `.superpowers/sdd/2026-10-16-quantlib-integration/progress.md`.

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Forecast genuine EURIBOR floating and fixed-to-floating coupons from confirmed contract terms, exact published fixings and locally bootstrapped projection curves.

**Architecture:** Extend the existing per-ISIN terms with structured floating-phase data and pass a frozen ProjectionContext through the shared preview. The native engine chooses request-local historical fixings or index forwards explicitly; no global fixing registry and no conversion of a real floating bond into a fixed bond. Profiles embed reproducible input snapshots; native transfer metadata is versioned while legacy webapp JSON remains compatible.

**Tech Stack:** Existing SwiftUI/Core Data app, optional Codable metadata, Stage1 native bridge, Stage2 CurveBootstrap and MarketDataSnapshot, XCTest.

**Spec:** `docs/superpowers/specs/2026-10-16-quantlib-integration-design.md`. Requires both the native-engine plan and `2026-10-16-quantlib-market-data.md` complete.

## Global Constraints

- No instrument-specific rules or invented missing contract facts.
- Confirmed Fixed overrides remain an explicit constant-rate assumption, separate from genuine floating forecasts.
- Missing past/today fixings are not replaced with forwards. Future resets use the matching tenor's index value/maturity dates.
- Forecasts have a pinned valuation day and source snapshot; rendering/launch never silently changes approved money.
- No global IndexManager fixing mutations. All native calls share the bootstrap mutex and restore Settings through RAII.
- Preserve historical rows, event identities and prospective activation. Projected coupons never become recorded receipts merely because time passed.
- Preserve legacy bonds.json keys; support native version1 reads and version2 metadata for actual floating profiles.
- Negative market rates/net coupons remain signed; no implicit zero floor.
- No rate-in-arrears, capped/floored/averaged/overnight or callable valuation in this programme; incomplete/non-vanilla terms remain Needs review.

## Review Focus

1. A fixed-to-floating transition can duplicate/omit a coupon: Task2 tests contiguous accrual and one redemption at the boundary.
2. Fixing date is not the index deposit value date: Task2 tests the2-TARGET-day distinction around Easter.
3. A past projected fixing cannot be treated as actual after a clock advance: Tasks2-3 pin valuation/source provenance and receipt blocking.
4. Updating data can reset approval/activation or alter recorded cash: Task3 tests explicit refresh preserves approval/activation and rejects history corrections.
5. Native transfer without matching market inputs cannot be reproducible: Task3 tests versioned/digest-checked embedded snapshots and legacy JSON compatibility.

---

## File map and ownership

Modify `BondTerms.swift`, `BondTermsFields.swift`, `BondTermsReview.swift`, `BondTermsReviewView.swift`, `BondTermsStore.swift`, `BondSchedule.swift`, `BondEligibility.swift`, `AddBondView.swift`, `BondTableView.swift`, `BondTransfer.swift`, `ImportManager.swift`, `ExportManager.swift`, `LaunchEventProcessor.swift`, `LaunchNotifier.swift` and the native/Swift calculation bridge. Add focused `FloatingBondTerms.swift`, `FloatingBondMath.cpp/.hpp` and `ProjectionContext.swift` rather than putting source/network/state logic into BondSchedule. Add `FloatingBondTermsTests.swift`, `FloatingBondMathTests.swift`, `FloatingProjectionTests.swift`; extend current review/event/transfer tests.

No Core Data entity/model migration is required: existing termsData/termsDraftData carry optional Codable additions and a frozen snapshot value. Do not serialize QuantLib objects. Each purchase embeds the snapshot used by its projection; this bounded duplication avoids a cross-machine catalogue-reference migration.

## Task 1: Add complete, editable floating contract terms

**Files:** FloatingBondTerms.swift, BondTerms.swift, BondTermsFields.swift, ProjectionContext.swift, BondTermsReview.swift and FloatingBondTermsTests.swift.

**Interfaces:**

```swift
enum FloatingResetTiming: String, Codable, Sendable { case inAdvance, inArrears }
enum FloatingAccrualAdjustment: String, Codable, Sendable { case unadjusted, modifiedFollowing }
enum FloatingPaymentAdjustment: String, Codable, Sendable { case following, modifiedFollowing }
enum FloatingDayCount: String, Codable, Sendable { case actual360, actual365Fixed, actualActualICMA }
enum FloatingResetAnchor: String, Codable, Sendable { case contractualAccrualStart, adjustedAccrualStart }
enum FloatingPayoff: String, Codable, Sendable { case plain, cappedOrFloored, other }
struct FloatingBondTerms: Codable, Equatable, Sendable {
    var indexTenorMonths: Int?
    var spreadBps: Double?
    var gearing: Double?
    var resetLagTARGETDays: Int?
    var resetTiming: FloatingResetTiming?
    var resetAnchor: FloatingResetAnchor?
    var dayCount: FloatingDayCount?
    var frequency: Int?
    var firstFloatingCoupon: MarketDay?
    var accrualAdjustment: FloatingAccrualAdjustment?
    var paymentAdjustment: FloatingPaymentAdjustment?
    var roll: CouponRoll?
    var payoff: FloatingPayoff?
    var confirmedFields: Set<String> = []
}
struct FloatingCalculationWindow: Equatable, Sendable {
    let acquisitionDay: MarketDay
    let paymentFrom: MarketDay
}
struct ProjectionContext: Codable, Equatable, Sendable {
    let valuationDay: MarketDay
    let marketData: MarketDataSnapshot
}
```

Add `var floatingTerms: FloatingBondTerms?` to BondTerms, retaining existing floatingStart for a fixed-to-floating transition. Fixed phase uses existing couponRate/frequency/conventions; a pure floating bond does not use its current quoted coupon as a permanent rate. Default optional fields decode nil; do not infer spreads or absence of caps/floors from a name/ISIN. Confirming payoff.plain is an explicit contract input.

Expose `FloatingBondTerms.assessment(structure: BondStructure, transition: MarketDay?, accrualStart: MarketDay?, maturity: MarketDay?) -> TermsAssessment`. Validate tenor in1/3/6/12, finite spread/gearing, gearing>0, lag0...10, frequency1/2/4/12, resetTiming.inAdvance, payoff.plain, explicit confirmed resetAnchor/dayCount/adjustment/roll and transition strictly between accrual start/maturity for fixedToFloating. Unknown terms remain missing; defaults may be displayed as assumed values but are not silently confirmed. Store spreads in bps, not percent. Support only confirmed dayCount.actual360 in this stage; persist other selections but report them unsupported. The existing root ICMA convention applies only to the fixed phase. Require confirmation of either contractualAccrualStart or adjustedAccrualStart reset anchor; both are supported. Missing fields never inherit an implicit ACT/360 or reset anchor. Validate fixed-to-floating phase alignment in the native schedule assessment before Ready: transition must lie on the fixed grid anchored to final contractual maturity, using fixed frequency/roll. Reject off-grid transitions with "Off-grid fixed-to-floating transition is not supported; verify the phase schedule." Do not treat transition as a new fixed-grid anchor.

- [ ] **Step1: Write RED validation/decoding tests.**

```swift
func testIncompleteFloatingContractDoesNotBecomeReady() throws {
    let terms = FloatingBondTerms()
    XCTAssertFalse(terms.assessment(structure: .floating, transition: nil, accrualStart: MarketDay("2026-01-15"),
        maturity: MarketDay("2031-01-15")).supported)
}
func testOldFixedTermsDecodeWithoutInventingFloatingFields() throws {
    let bytes = try JSONEncoder().encode(BondTermsFixtures.fixed())
    let decoded = try JSONDecoder().decode(BondTerms.self, from: bytes)
    XCTAssertNil(decoded.floatingTerms)
}
```

Add a valid fixture helper `FloatingFixtures.plain3M()` setting tenor3, spread15bps, gearing1, lag2, inAdvance, confirmed contractualAccrualStart reset anchor, confirmed actual360 day count, frequency4, unadjusted accrual, Following payment, dayOfMonth roll, payoff.plain. Test negative spread is valid, unknown/missing payoff is not, inArrears/cappedOrFloored remain unsupported and a6M market snapshot cannot satisfy3M terms. Test missing/unconfirmed dayCount and resetAnchor fail readiness; confirmed actual365Fixed/actualActualICMA are unsupported; changing floating day count does not change fixed ICMA. Test both confirmed reset anchors remain preserved through draft save, provider refresh and native transfer. Run targeted RED before implementation.

- [ ] **Step2: Implement fields and per-ISIN shared edits.** Show a Floating terms section only for Floating/Fixed-to-floating selections; include explicit units, phase-specific day-count and reset-anchor controls with confirmation and required-field errors. Fixed-to-floating adds transition date and separate floating coupon frequency. Keep the Fixed override warning visible when Fixed is selected despite provider metadata. Extend preservingConfirmed/preservingSafeguards for nested confirmed fields without losing approvals or overwriting user-confirmed values on ING refresh. ING collection does not supply absent reset/spread/payoff metadata or select a curve automatically.

- [ ] **Step3: Preserve the chosen context through drafts.** Add optional projectionContext to BondTermsDraft and optional context parameter to BondSchedule.preview with defaultnil. Selecting a snapshot and valuation day updates the current draft; Save draft/preview freezes that context across sibling purchases. A later catalogue refresh never replaces it silently. In Add Bond, selecting a genuinely floating instrument requires a valid context; Fixed/zero entry remains unchanged.

- [ ] **Step4: Run all tests, review and commit.**

```sh
git add MyBondManager/FloatingBondTerms.swift MyBondManager/ProjectionContext.swift MyBondManager/BondTerms.swift MyBondManager/BondTermsFields.swift MyBondManager/BondTermsReview.swift MyBondManagerTests/FloatingBondTermsTests.swift
git commit -m "feat: capture complete floating bond contracts as shared data"
```

## Task 2: Calculate known and projected coupons, including transitions

**Files:** FloatingBondMath.cpp/.hpp, QuantLibBridge.h/.mm, QuantLibBondMath.swift, BondSchedule.swift, FloatingBondMathTests.swift.

**Interfaces:**
- `enum CouponRateSource: String, Codable, Sendable { case fixed, publishedFixing, projected }`.
- Define `QuantLibFloatingPayment` with `payment: QuantLibPayment`, `rateSource: CouponRateSource`, `fixingDay: MarketDay?`, `indexRate: Double?`, `effectiveCouponRate: Double?`. Add optional `rateSource`, `fixingDay`, `indexRate` and `effectiveCouponRate` to BondPayment; missing old metadata is not interpreted as a published floating fixing.
- `QuantLibBondMath.floatingPayments(terms: BondTerms, nominal: Double, context: ProjectionContext, window: FloatingCalculationWindow) throws -> [QuantLibFloatingPayment]`, where QuantLibFloatingPayment wraps the existing native payment plus the four provenance fields.
- Rate selection is internal to FloatingBondMath.cpp and tested through the real native payment interface: exact published date on/before valuation, otherwise projected. A fixing for another date never qualifies. Do not add a second Swift rate resolver used only by tests.

Extend the C header with these concrete transport types. Fixed C ABI stays unchanged; only floating requests carry a calculation window. Generate the complete contractual date schedule for checkpoint validation separately from resolving coupon amounts. Add `QuantLibBondMath.floatingCouponDays(terms: BondTerms) throws -> [MarketDay]` and a matching `MBMQLFloatingCouponDays(const MBMQLFloatingRequest *request, int32_t *output, size_t capacity, size_t *count, char *error, size_t errorCapacity)` that validates schedule fields only and needs no curve/fixings/window. This path returns all contractual coupon ends; the money path returns only eligible payments.

```c
typedef struct { int32_t day; double rate; } MBMQLPublishedFixing;
typedef struct {
    int32_t startDay, maturityDay, firstCouponDay, transitionDay, firstFloatingCouponDay;
    int32_t fixedFrequency, floatingFrequency, indexTenorMonths, resetLagDays;
    int32_t fixedRoll, floatingRoll, accrualAdjustment, paymentAdjustment;
    int32_t floatingDayCount; /* 0 ACT/360; all other values rejected */
    int32_t resetAnchor; /* 0 contractual start, 1 adjusted start */
    int32_t acquisitionDay, paymentFromDay; /* required inclusive calendar-day bounds */
    int32_t valuationDay; /* 0 invalid; distinct from curve quote day */
    double nominal, fixedAnnualRate, spreadBps, gearing, redemptionPercent;
} MBMQLFloatingRequest;
typedef struct {
    MBMQLPayment payment;
    int32_t rateSource; /* 0 fixed/redemption, 1 published fixing, 2 projected */
    int32_t fixingDay; /* 0 only for fixed/redemption */
    double indexRate, effectiveCouponRate;
} MBMQLFloatingPayment;
int MBMQLFloatingPayments(const MBMQLFloatingRequest *request,
    const MBMQLCurveRequest *curve, const MBMQLPublishedFixing *fixings, size_t fixingCount,
    MBMQLFloatingPayment *output, size_t capacity, size_t *count,
    char *error, size_t errorCapacity);
```

Transport conventions: roll0 dayOfMonth/1 EOM/2 unknown; accrual0 unadjusted/1 ModifiedFollowing; payment0 Following/1 ModifiedFollowing. transitionDay0 means pure floating; otherwise fixed before transition and floating from transition. Keep the regular fixed grid anchored to final maturity, then truncate it at an on-grid transition; never pass transition as a replacement maturity anchor. Off-grid transitions fail schedule readiness before any payments are emitted. Native rejects unknown enum values, inapplicable dates, mismatched tenors and nonfinite numbers; Swift validates all required terms before transport. Contract restrictions/caps/arrears are rejected before this function, not silently passed as plain coupons.

- [ ] **Step1: Add known/missing/future-fixing RED tests.**

```swift
func testPublishedFixingWinsAndMissingPastFixingNeverUsesForward() throws {
    let terms = try FloatingFixtures.singlePeriodTerms(start: "2026-10-15", end: "2027-01-15")
    let fixing = try PublishedFixing(day: MarketDay("2026-10-13"), rate: 0.025)
    let context = try FloatingFixtures.context(valuation: "2026-10-16", fixings: [fixing])
    let payments = try QuantLibBondMath.floatingPayments(terms: terms, nominal: 1000000, context: context,
        window: FloatingFixtures.window(start: terms.accrualStart!, from: terms.accrualStart!))
    let coupon = try XCTUnwrap(payments.first { $0.payment.kind == .interest })
    XCTAssertEqual(coupon.rateSource, .publishedFixing)
    XCTAssertEqual(coupon.indexRate, 0.025)
    XCTAssertEqual(coupon.payment.amount, 6772.222222222222, accuracy: 1e-8)
    let missing = try FloatingFixtures.context(valuation: "2026-10-16", fixings: [])
    XCTAssertThrowsError(try QuantLibBondMath.floatingPayments(terms: terms, nominal: 1000000, context: missing,
        window: FloatingFixtures.window(start: terms.accrualStart!, from: terms.accrualStart!)))
}
func testFutureFixingIsLabelledProjected() throws {
    let terms = try FloatingFixtures.singlePeriodTerms(start: "2027-01-15", end: "2027-04-15")
    let context = try FloatingFixtures.context(valuation: "2026-10-16", fixings: [])
    let payments = try QuantLibBondMath.floatingPayments(terms: terms, nominal: 1000000, context: context,
        window: FloatingFixtures.window(start: terms.accrualStart!, from: terms.accrualStart!))
    let coupon = try XCTUnwrap(payments.first { $0.payment.kind == .interest })
    XCTAssertEqual(coupon.rateSource, .projected)
    XCTAssertEqual(coupon.fixingDay?.rawValue, "2027-01-13")
}
```

Define test-only `FloatingFixtures.window(start:from:)` returning acquisitionDay=start/paymentFrom=from. Define test-only FloatingFixtures.singlePeriodTerms(start:end:) using the complete plain3M contract from Task1, root structure.floating, start/maturity from parameters, firstFloatingCoupon=end, nominal supplied to the API and redemption100. FloatingFixtures.context(valuation:fixings:) wraps MarketDataFixtures.quotes3M() and supplied published observations into a validated snapshot/context, using the real Stage2 empty-probe bootstrap for calibration diagnostics and the same fingerprint encoder; no production fixture builders. Repeat fixingDay==valuationDay with missing publication and require a Pending fixing error. For a known92-day ACT/360 period with nominal1,000,000, published index2.5%, spread15bps and gearing1, native coupon amount must be6772.222222222222. Negative index-0.5% with the same spread gives-894.4444444444445; assert no implicit floor. Expectations are hand-derived, not computed from the native engine under test.

- [ ] **Step2: Implement native phase schedules and rates.** Use QuantLib Schedule for each phase with its own frequency/roll and confirmed first date. The fixed phase ends exactly at transition; floating starts exactly there. Use the existing fixed day count on a schedule retaining the final-maturity regular anchor; reject off-grid transitions instead of reanchoring. Reuse Stage1 date/day-count primitives, not its maturity-anchored complete-bond call with transition substituted for maturity; do not emit fixed-phase redemption. Generate only one principal payment at final maturity. Contractual coupon ends remain the identity dates; the selected accrual adjustment governs floating accrual boundaries and selected payment adjustment governs payment dates separately.

Build all contractual dates first and validate the observation-day checkpoint against that complete list. Before resolving rates or amounts, apply the existing purchase entitlement predicate using acquisitionDay and retain only payments whose adjusted paymentDay >= paymentFromDay. Use this same filter for fixed-phase coupons and redemption. Do not demand fixings or curve coverage for excluded periods; purchase inside an accrual period still receives the complete entitled coupon without ownership proration. A contractual coupon before paymentFromDay stays eligible if its adjusted payment remains pending. Normal preview passes trade acquisition day and its from day; receipt reconciliation passes the original activation day as paymentFrom. Full-date validation never evaluates historical coupon money.

For each eligible floating period, choose the reset anchor explicitly: contractualAccrualStart uses the unadjusted start; adjustedAccrualStart first applies the selected accrual adjustment. Compute the reset day by moving backward resetLagTARGETDays TARGET business days from that anchor, with no preliminary business-day adjustment of an unadjusted contractual anchor. Zero lag requires a TARGET business-day anchor or an actionable unsupported-input error. Both published-fixing lookup and future projection use exactly this reset day. The selected tenor's Euribor index supplies benchmark valueDate(fixingDay) and maturityDate(valueDate). On/before valuation day, require the request-local published rate for exactly that reset day. For future days, build the matching full projection curve once per request with Stage2 buildProjectionCurve and query simple ACT/360 over the index's value/maturity dates, checking coverage. Never use start=fixingDay as a shortcut.

Use QuantLib Actual360.yearFraction on the adjusted accrual boundaries. Effective rate is gearing * indexRate + spreadBps /10000; coupon amount is nominal * effectiveRate * QuantLib yearFraction. This scalar multiplication is the cash amount mapping, not a replacement index/day-count engine. Preserve signed amounts. No global index.addFixing call, no last-observation carry and no stock bond name/ISIN logic. Hold the shared native mutex with SavedSettings during bootstrap; valuation-day policy is explicit and independent of the curve's quote day.

- [ ] **Step3: Wire the shared preview.** Fixed/zero and manually confirmed Fixed overrides continue through Stage1. For genuinely floating selections require structured floating terms/context, remove the unconditional unsupported branch only for supported complete contracts, and bypass the fixed couponRate>=0/current-rate validation. Fixed-to-floating still requires its initial fixed rate. Keep all unrelated restrictions, call/deferral warnings and per-trade entitlement checks. Return nil Estimated YTM for genuine floating/mixed profiles; do not extrapolate the initial rate into a fixed yield. Display known versus projected payment provenance and the context valuation/source dates.

- [ ] **Step4: Add transition/calendar/horizon tests and run GREEN.** Use a synthetic fixed-to-floating contract transitioning2027-01-15: fixed annual until that boundary, floating quarterly afterward, final maturity2028-01-15. Assert no missing/overlapping accrual, a fixed final-phase coupon on transition only once, first floating coupon2027-04-15, and exactly one redemption at final maturity. For annual May31 fixed coupons with an Aug31 transition, assert the precise off-grid rejection and no payments even if a first floating coupon is confirmed; do not claim stub support in this stage. Test missing/contradictory phase metadata. For contractual2027-01-31 (Sunday), ModifiedFollowing accrual begins2027-01-29: lag2 gives2027-01-28 from the contractual anchor and2027-01-27 from the adjusted anchor. Assert each literal reset day, known lookup and projected lookup, and the same ModifiedFollowing accrual boundaries for both anchor selections (only reset anchoring differs). Add an older floating issue purchased recently with only the fixing for its first entitled coupon: preview succeeds without earlier paid/unowned fixings; removing that required fixing fails. Check full-date checkpoint validation still sees dates before the money window, and an adjusted payment after the window is retained. Test an Easter reset where two TARGET days cross the holiday closure, and assert the derived value date separately from fixing date. Use Stage2 public Bridge quote fixtures/golden forwards to verify future rates independently of coupon arithmetic. Test tenor mismatch and a reset underlying maturity beyond curve coverage fail per instrument. Re-render with a later `from` but the same ProjectionContext; rateSource stays projected rather than magically becoming known.

- [ ] **Step5: Run the whole suite, review and commit.**

```sh
git add MyBondManager/FloatingBondMath.cpp MyBondManager/FloatingBondMath.hpp MyBondManager/QuantLibBridge.h MyBondManager/QuantLibBridge.mm MyBondManager/QuantLibBondMath.swift MyBondManager/BondSchedule.swift MyBondManagerTests/FloatingBondMathTests.swift
git commit -m "feat: calculate genuine floating and fixed-to-floating coupons"
```

## Task 3: Adopt snapshots explicitly, preserve receipts and transfer both Macs

**Files:** BondTermsStore.swift, BondTermsReview.swift/.View.swift, MarketDataView.swift, LaunchEventProcessor.swift, LaunchNotifier.swift, BondTransfer.swift, ImportManager.swift, ExportManager.swift, BondEligibility.swift, BondTableView.swift and existing event/review/transfer tests.

**Interfaces:**
- Add optional `projectionContext: ProjectionContext?` to the existing stored Profile; old fixed profiles decode nil.
- Add `context: ProjectionContext? = nil` to the shared preview and projection replacement path. Approval/rebuild validates the activation-window calculation as well as the displayed from-day projection, so adoption cannot succeed then fail to reconcile an older eligible unrecorded coupon. Native transfer validates expected displayed money with its exported projection day and reconstructs destination activation separately; no window is inferred from the destination clock. Every producer uses an explicitly selected context; every reader uses the frozen profile context, never a mutable 'latest' catalogue lookup.
- Add `BondTermsReview.refreshForecasts(ids: [UUID], context: ProjectionContext) async throws -> BondTermsApplyReport` for approved unchanged terms. It applies independently per ISIN, updates only forecast/profile data, preserves approvedAt/eventsActivateAfter and does not silently approve a draft.
- Native envelope2 adds `[String: MarketDataSnapshot]` snapshot entries and each bond entry's optional valuationDay/snapshotID reference; reconstruct a complete ProjectionContext before validating money. Use version2 only when genuine floating context is exported; fixed-only transfers can retain version1.

- [ ] **Step1: Add the explicit-update/read-only RED test.** Approve a synthetic floating profile on snapshotA, record its terms.approvedAt and eventsActivateAfter, then save newer snapshotB into the catalogue. Assert no profile/cashflow/history changes. Explicitly call refreshForecasts on one valid ISIN and one ISIN missing its required past fixing; assert one applied/one failed, the failed profile remains unchanged, successful approval/activation timestamps stay equal to their originals, and market source/valuation timestamps update. Loading/reopening never writes either profile. Add an offline candidate snapshot that covers every current/future forecast fixing but omits one already-paid post-activation coupon fixing retained in the approved snapshot. refreshForecasts must validate each purchase from its original activation day before replacement, fail this ISIN, preserve its old context/approval/activation and leave the next real LaunchNotifier.processLaunch operational; other valid ISINs still succeed. A fresh term approval uses its proposed activation boundary, not an earlier unrelated approval window.

- [ ] **Step2: Implement frozen context and user actions.** Store contexts directly in Codable profile/draft blobs, with source hash validation at each import/explicit adoption. Reject a context valuation day before its source quote day or any included published observation day; backdated forecasts require an appropriately dated snapshot, not future knowledge. Add Rebuild selected forecasts using chosen market data as an explicit action, separate from term approval and source refresh. Apply edited terms still follows the existing explicit approval route. Preserve partial-success/window-selection behaviour. Fixed and constant-rate overrides require no market snapshot. Show stale/as-of warnings without silently deleting the last approved forecast when a source is offline. Missing required fixing prevents a new forecast adoption, never a replacement with a predicted actual.

- [ ] **Step3: Reconcile receipts from original activation, independently of launch watermark.** Revise LaunchEventProcessor's amount>0 gate: nonzero interest of either sign may be recorded only for .fixed/.publishedFixing; .projected is never recorded. Positive redemption remains separately validated. For each active profile, request preview from MarketDay(eventsActivateAfter), with its acquisition day and frozen context. Scan payments with activation < payment instant <= until, independent of `since`; retain the future-watermark guard but never let lastLaunchDate exclude an unrecorded eligible coupon. Event identities and legacy aliases prevent duplicates across the whole activation window. Preserve deferral safeguards and the original activation boundary on explicit forecast adoption. Imported profiles use destination activation; never backfill earlier receipts.

A now-past projected coupon remains unrecorded until a newly adopted snapshot contains its actual fixing. Reconciliation then finds it even after successful launches advanced lastLaunchDate. Check history conflicts across the activation window before inserting; if a published correction disagrees with an existing receipt, preserve that row and flag the conflict. Missing fixing on a later rebuild leaves the last approved profile intact.

Write an async integration test using real successive `LaunchNotifier.processLaunch(in:now:)` calls, an isolated UserDefaults suite and an in-memory container; do not substitute a stage closure or reuse an old since value. Approve Friday2027-01-08, with a short first floating period2027-01-15 through Monday2027-01-18, contractual reset anchor, lag2 and reset2027-01-13; initial context valuation is2027-01-08, so the coupon is projected. Use acquisition2027-01-08 and confirm the first floating coupon2027-01-18. Launch Tuesday2027-01-19: assert no receipt and lastLaunchDate equals Tuesday. Explicitly adopt Wednesday2027-01-20 context containing the actual fixing, preserving Friday activation. Launch Wednesday: assert exactly one correctly dated Monday receipt despite Tuesday watermark. Launch Thursday: assert no duplicate and watermark advances again. Repeat with a signed negative coupon, a legacy event alias, a payment before activation and a conflicting corrected fixing; assert negative interestReceived, alias deduplication, no pre-activation backfill and unchanged conflicting history respectively. Stage-level tests alone are insufficient for this regression.

Ensure portfolio summaries, expectedProfit and webapp cashflow validation preserve negative interest instead of discarding it or turning it into capital loss.

- [ ] **Step4: Version native transfers without breaking the webapp.** Version1 decoder remains unchanged for old fixed portfolios. Version2 validates exact bonds.json digest, every snapshot financial/calibration fingerprint, schema/source date and calibration residual, tenor match and expected money using the exported frozen valuation/context. Reject missing, extra conflicting, tampered or unknown-version data before portfolio mutation. Embed only referenced snapshots and deduplicate by id; do not export local catalogue paths. Import reconstructs profile context directly and sets only the normal destination activation boundary. It does not require network or another machine's catalogue. No new fields are added to legacy BondCodable or cash-flow objects. Genuine floating Estimated YTM is unavailable: preserve the existing numeric0 unavailable representation in legacy JSON, retain nil in the Mac/native calculation, and document that the legacy file alone cannot express the difference between unknown yield and an actual0% yield. Do not advertise an exact/QuantLib floating yield.

Test2-purchase floating and mixed native roundtrip offline; fixed-only version1 roundtrip; version2 missing snapshot rejection with both destination holdings/history unchanged; corrupted rate/hash rejection; and exact legacy key sets. On a second Mac with current app, verify the same dated forecast amounts/provenance offline. An old app must reject version2 explicitly rather than ignore market metadata and claim Ready. Legacy webapp receives dated forecast amounts in its existing format; Mac export UI warns those floating amounts are projections.

- [ ] **Step5: Full integration test and Release gate.** In one isolated portfolio include fixed, genuine3M floating, fixed-to-floating, explicit Fixed override, deferrable and missing-fixing examples. Fetch/import public market inputs, inspect bootstrap diagnostics, explicitly apply/rebuild and compare literal known coupons and independent forward fixtures. Verify mixed failures don't block successes, known/forecast UI labels, signed interest, no duplicated principal, and no startup writes. Run full XCTest, native concurrency/state-restoration tests and Stage1 universal/offline packaging checks. Do not claim live source, Intel execution or real-portfolio verification from fixture tests. Keep Bridge untouched.

- [ ] **Step6: Document and commit only owned changes.** Update docs/portfolio-safeguards.md, docs/positions-transfer.md, docs/quantlib-market-data.md and the native transfer version contract. Explain the source bootstrap approximation, unsupported product shapes, stale/missing data behaviour and Fixed override distinction. Deliver a new local app; no merge/push or live-history migration is implicit.

```sh
git add MyBondManager/BondTermsStore.swift MyBondManager/BondTermsReview.swift MyBondManager/BondTermsReviewView.swift MyBondManager/MarketDataView.swift MyBondManager/LaunchEventProcessor.swift MyBondManager/LaunchNotifier.swift MyBondManager/BondTransfer.swift MyBondManager/ImportManager.swift MyBondManager/ExportManager.swift MyBondManager/BondEligibility.swift MyBondManager/BondTableView.swift MyBondManagerTests/FloatingProjectionTests.swift MyBondManagerTests/BondTermsEventTests.swift MyBondManagerTests/BondTransferTests.swift docs/portfolio-safeguards.md docs/positions-transfer.md docs/quantlib-market-data.md
git commit -m "feat: adopt floating forecasts with reproducible data and safe transfers"
```

## Final programme completion

Stage1 alone is insufficient. Completion requires sourced3M/6M bootstraps and offline imports, complete editable floating terms, genuine known/projected coupon differentiation, mixed-phase schedules, signed interest handling, snapshot-aware native transfer and the full Release/UI validation gates. Market data refresh is independent of term approval and history. No instrument-specific exceptions may be introduced to clear remaining review errors.
