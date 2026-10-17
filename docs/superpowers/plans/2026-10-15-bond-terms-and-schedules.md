# EUR Bond Terms and Regular Payment Schedules Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Collect and approve EUR bond terms, forecast supported regular payments with explicit conventions, preserve financial history, and transfer native terms alongside the unchanged webapp bond JSON.

**Architecture:** Extend existing purchase records with versioned optional terms and projection metadata. Use pure calendar/schedule functions for both previews and saved projections, isolated serialized writes for approval/import/event recording, and one readiness policy across all consumers. Keep `BondCodable` unchanged and place native metadata in a digest-bound sidecar.

**Tech Stack:** Swift 5.0, SwiftUI, Core Data, Foundation, CryptoKit, XCTest, macOS 15.0; no new packages or QuantLib.

**Spec:** `docs/superpowers/specs/2026-10-15-bond-terms-and-schedules-design.md` (read it with this plan).

## Global Constraints

- "QuantLib remains parked."
- "Existing financial history must not be reconstructed or silently corrected."
- "No new external dependencies."
- "Different purchases retain separate review/application state and immutable trade details."
- "Use a consistent EUR market calendar/time zone (Europe/Berlin) when materializing payment dates."
- "Keep contractual accrual dates unadjusted; moving the payment does not move the accrual boundary."
- "Buying within a coupon period does not prorate the next contractual coupon by ownership days."
- "Coupon day count" defaults to "Actual/Actual (ICMA), assumed until confirmed"; payment defaults to TARGET/Following, with no extra interest for payment delay.
- "Only conventions implemented and tested by this phase may produce Ready projections."
- "Bond-only operations never alter ETFs."
- "Preserve the existing root array, names, types, whole-second ISO-8601 dates and nested structure exactly."
- "Do not export stale unverified rows for Needs review bonds: export the holding with an empty `cashFlows` array until its projections are approved."
- "Native transfer restores terms and projections, not historical event records or another Mac's launch checkpoint."
- "Normal launches use saved approved terms. Subsequent term refreshes are manual and require review before changes are applied."
- Preserve the visual design and the user's local signing/team, scheme-version, workspace state, `.DS_Store`, and `graphify-out/` changes. No automatic source repair, reset, push, or merge.
- No product implementation until this written plan is approved and an execution method is selected. Commit steps below describe execution checkpoints, not permission to start now.

## Review Focus

1. An old Saturday coupon was already recorded, then its new TARGET payment moves to Monday: never post it again (Task 7 alias/replay tests).
2. A terms review stays open across midnight/DST or ING's next-coupon checkpoint ages: preserve contractual dates, revalidate the preview day, and never shift a coupon to the previous day (Tasks 1, 3, 5 and 6 tests).
3. A sidecar belongs to a different export with identical UUIDs: reject by exact-byte digest before any replacement (Task 9 tests).
4. An approval and a launch/import write overlap: each operation must observe the preceding committed state and reject a stale approval (Tasks 4 and 6 tests).
5. An old JSON import replaces a Ready holding while retaining its UUID: clear native readiness/terms rather than reuse stale metadata; keep the holding visible with excluded forecasts (Tasks 4, 8 and 9 tests).

---

## Repository baseline and workflow

- Planning baseline: application commit `33992ac5379b80ebb3b44d7a8c21620764880527`; design commit `d9d9647` follows it. Branch: `codex/portfolio-reliability`.
- Existing tests: 62 passed in `/tmp/mybond-followup-full.log`; this is evidence from the previous work, not a substitute for an execution baseline.
- Use the existing app-selected container, `PortfolioTransaction.run`, `TestPortfolio.make()`, and hosted in-memory test configuration. Never run the built app against the user's production store for a test.
- At execution start, use using-git-worktrees to verify/reuse isolation or create an isolated checkout at the approved feature head. Never switch a dirty checkout to main. Worktree creation must not lose the committed design or this approved plan; carry only those documents deliberately if necessary.
- The graph in `graphify-out/` predates the audit fixes. Use it for navigation, verify all facts in current source, and do not rebuild/commit it for this feature.
- Tests use `-derivedDataPath /tmp/MyBondManager-bond-terms` and `CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=`. Xcode may need approved access to its caches/test runner. Do not edit signing settings to make tests pass.
- After each production task, run its targeted tests and then the full suite. A code step is complete only after its regression has failed for the expected reason, then passed. Existing tests whose semantics change need explicit new expectations, not deletion or blanket readiness bypasses.

Full test command (use the exact command after each task):

```sh
xcodebuild -project MyBondManager.xcodeproj -scheme MyBondManager \
  -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath /tmp/MyBondManager-bond-terms \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= test \
  > /tmp/mybond-bond-terms-full.log 2>&1
```

## File map

| Files | Responsibility |
| --- | --- |
| `MyBondManager/MarketDay.swift` (new) | Validated calendar date, canonical string, explicit time-zone conversion and anchored date arithmetic |
| `MyBondManager/BondTerms.swift` (new) | Typed instrument terms, conventions, provenance and support assessment |
| `MyBondManager/TargetCalendar.swift` (new) | TARGET business days and Following adjustment, independent of UI/storage |
| `MyBondManager/BondSchedule.swift` (new) | Pure regular schedule, payment amounts, legacy decomposition and estimated yield |
| `MyBondManager/MyBondManager.xcdatamodeld/MyBondManagerV3.xcdatamodel/contents`, `.xccurrentversion` | Additive optional metadata; retain both older model versions |
| `BondEntity+CoreDataProperties.swift`, `CashFlowEntity+CoreDataProperties.swift`, `MyBondManager/BondTermsStore.swift` (new) | Typed storage mapping, readiness, activation and event aliases |
| `MyBondManager/PortfolioTransaction.swift` | Per-store write serialization while retaining a fresh context/save/rollback per operation |
| `MyBondManager/Scrapper.swift`, `BondCollection.swift` | Rich ING decoding, source validation, request identity and missing-value preservation |
| `MyBondManager/BondTermsReview.swift` (new) | Deduplicated fetch, persisted draft, immutable preview/approval and stale-input protection |
| `MyBondManager/CashFlowGenerator.swift`, `LaunchEventProcessor.swift`, `LaunchNotifier.swift` | Approved projection replacement and prospective idempotent event recording |
| `MyBondManager/BondEligibility.swift` (new), `CashFlowSelection.swift`, `PortfolioSummaryView.swift`, `BondTableView.swift`, `MaturedBondsView.swift` | Shared holdings/forecast rules and adjusted redemption maturity |
| `MyBondManager/BondTransfer.swift` (new), `ExportManager.swift`, `ImportManager.swift`, `PositionsTransferValidation.swift` | Two-file bond codec/export/import and safe all-positions interoperability |
| `MyBondManager/BondTermsReviewView.swift` (new), `BondTermsFields.swift` (new), `MainTabView.swift`, `AddBondView.swift`, `EditBondView.swift`, `ExportValidationView.swift`, `MyBondManagerApp.swift` | Review, corrections, entry, transfer controls and status/warnings |
| `MyBondManagerTests/BondTermsFixtures.swift` (new) | Small deterministic fixtures and test-only convenience builders |
| `MyBondManagerTests/*BondTerms*Tests.swift`, `MarketDayTests.swift`, `TargetCalendarTests.swift`, `BondScheduleTests.swift`, `BondTransferTests.swift`, existing migration/event/consumer tests | Real behavior and failure-path coverage |
| `docs/portfolio-safeguards.md`, `docs/positions-transfer.md` | User-facing eligibility, migration and transfer rules |

## Task 1: Typed terms and calendar dates

**Files:** Create `MyBondManager/MarketDay.swift`, `MyBondManager/BondTerms.swift`, `MyBondManagerTests/MarketDayTests.swift`, `MyBondManagerTests/BondTermsFixtures.swift`, `MyBondManagerTests/BondTermsTests.swift`.

**Interfaces:** Produces the following shared vocabulary. All structs are `Codable, Equatable, Sendable` unless otherwise stated; all enums have string raw values and the same conformances. No managed objects belong in these values.

```swift
struct MarketDay: Codable, Hashable, Comparable, Sendable {
    let rawValue: String  // validated four-digit-year YYYY-MM-DD
    init(_ value: String) throws
    init(date: Date, calendar: Calendar = Self.calendar)
    static var calendar: Calendar { get } // Gregorian, Europe/Berlin, POSIX
    var instant: Date { get } // start of this market day
    var year: Int { get }; var month: Int { get }; var day: Int { get }
    func addingDays(_ count: Int) throws -> MarketDay
    func addingMonths(_ count: Int, anchorDay: Int, endOfMonth: Bool) throws -> MarketDay
}
enum BondStructure: String, Codable, Sendable { case fixed, zero, unknown }
enum TermSource: String, Codable, Sendable { case ing, assumed, confirmed }
enum CouponRoll: String, Codable, Sendable { case dayOfMonth, endOfMonth }
struct BondConventions: Codable, Equatable, Sendable {
    var dayCount = "actualActualICMA"
    var calendar = "TARGET"
    var adjustment = "following"
    var sources: [String: TermSource] = [
        "dayCount": .assumed, "calendar": .assumed, "adjustment": .assumed
    ]
}
struct BondTerms: Codable, Equatable, Sendable {
    var isin = ""
    var currency: String?
    var structure: BondStructure = .unknown
    var rawStructure: String?
    var frequency: Int? // only 1, 2, 4 supported for fixed coupons
    var rawFrequency: String?
    var couponRate: Double?
    var maturity: MarketDay?
    var accrualStart: MarketDay?
    var issueDay: MarketDay?
    var nextCoupon: MarketDay?
    var checkpointObservedOn: MarketDay?
    var redemptionPercent: Double?
    var callable: Bool?
    var roll: CouponRoll?
    var conventions = BondConventions()
    var confirmedFields: Set<String> = []
    var restrictions: [String] = [] // retain discovered unsupported structures
    var collectedAt: Date?
    var approvedAt: Date?
}
struct TermsAssessment: Equatable, Sendable {
    let reasons: [String]
    let warnings: [String]
    var supported: Bool { reasons.isEmpty }
}
```

- [x] **Step 1: Write date and missing-value tests.** Use independently specified days, not a date formatter also used by production:

```swift
func testInvalidDaysAndOffsetPreservation() throws {
    XCTAssertThrowsError(try MarketDay("2026-02-29"))
    XCTAssertThrowsError(try MarketDay("2026-2-03"))
    XCTAssertEqual(try MarketDay("2028-02-29").rawValue, "2028-02-29")
    let decoded = try JSONDecoder().decode(MarketDay.self, from: Data(#""2026-10-25""#.utf8))
    XCTAssertEqual(decoded.rawValue, "2026-10-25")
    XCTAssertEqual(MarketDay(date: decoded.instant).rawValue, "2026-10-25")
}
func testAnchorDoesNotDriftAfterFebruary() throws {
    let jan = try MarketDay("2028-01-31")
    XCTAssertEqual(try jan.addingMonths(1, anchorDay: 31, endOfMonth: true).rawValue, "2028-02-29")
    XCTAssertEqual(try jan.addingMonths(2, anchorDay: 31, endOfMonth: true).rawValue, "2028-03-31")
    XCTAssertNil(BondTerms().frequency)
    XCTAssertNil(BondTerms().callable)
}
```

- [x] **Step 2: Run the failing tests.** Run the full test command with `-only-testing:MyBondManagerTests/MarketDayTests -only-testing:MyBondManagerTests/BondTermsTests` before `test`, logging to `/tmp/mybond-terms-types-red.log`. Missing new symbols are expected at this initial API gate; repair test typos before proceeding.
- [x] **Step 3: Implement strict date and value types.** Parse exactly ten ASCII characters with separators at positions 4/7, construct Gregorian components, and round-trip the components to reject normalized invalid dates. Encode/decode as a single string. Use `DateComponents(year:month:day:)` in the explicit calendar, not UTC slicing of an instant. Month arithmetic always starts from the original anchor plus an offset; clamp against the destination month's day range. Reject out-of-range arithmetic with `PortfolioError`, never return today's date. Add `Equatable` to the enums used by `BondTerms` and keep missing fields nil.

```swift
var calendar = Calendar(identifier: .gregorian)
calendar.timeZone = TimeZone(identifier: "Europe/Berlin")!
calendar.locale = Locale(identifier: "en_US_POSIX")
// Decoding must call the validating initializer, not synthesize unchecked rawValue.
let container = try decoder.singleValueContainer()
self = try MarketDay(container.decode(String.self))
```

- [x] **Step 4: Add cross-zone round trips.** Materialize `2026-03-29` and `2026-10-25` around DST, encode to native day strings, and assert the exact same raw values while a separate calendar is set to America/Los_Angeles or Asia/Nicosia. Do not mutate global time-zone defaults in concurrent tests. Run targeted tests, then the full suite.
- [x] **Step 5: Commit this unit.** Stage the five named files only; commit `feat: define EUR bond terms and market dates`.

## Task 2: TARGET business days and payment adjustment

**Files:** Create `MyBondManager/TargetCalendar.swift`, `MyBondManagerTests/TargetCalendarTests.swift`.

**Interfaces:** Consumes `MarketDay`. Produces `TargetCalendar.isBusinessDay(_ day: MarketDay) -> Bool` and `TargetCalendar.following(_ day: MarketDay) throws -> MarketDay`.

- [x] **Step 1: Write hand-checked holiday tests.** Include multiple consecutive closures and no substitute holiday when Christmas falls on a weekend:

```swift
func testFollowingKeepsAmountsIndependentAndCrossesHolidays() throws {
    let cases = [
        ("2026-04-03", "2026-04-07"), // Good Friday through Easter Monday
        ("2026-05-01", "2026-05-04"),
        ("2027-01-01", "2027-01-04"),
        ("2026-12-25", "2026-12-28"),
        ("2026-12-28", "2026-12-28"),
        ("1999-12-31", "2000-01-03")
    ]
    for (input, wanted) in cases {
        XCTAssertEqual(try TargetCalendar.following(MarketDay(input)).rawValue, wanted)
    }
}
```

- [x] **Step 2: Run targeted RED.** Use `-only-testing:MyBondManagerTests/TargetCalendarTests` and `/tmp/mybond-target-red.log`; missing calendar API or incorrect literal dates must fail.
- [x] **Step 3: Implement only TARGET rules.** Weekends; January 1 and December 25; from 2000 also Good Friday, Easter Monday, May 1 and December 26; December 31 of 1998, 1999 and 2001. Compute Gregorian Easter with the integer Gregorian computus and validate its date; bound supported adjustment years to 1900...2199 with a clear error. Following advances one calendar day until open, with a 14-day safety bound that throws on exhaustion. This is a small calendar, not a general scheduling framework. Reference for the rules, not a new dependency: `https://github.com/lballabio/QuantLib/blob/master/ql/time/calendars/target.cpp`.

```swift
for offset in 0..<14 {
    let candidate = try day.addingDays(offset)
    if isBusinessDay(candidate) { return candidate }
}
throw PortfolioError("No TARGET payment day could be determined.")
```

- [x] **Step 4: Test historic exceptions separately.** Assert 1999 Good Friday follows the pre-2000 rule, 2001-12-31 is closed, 2002-12-31 is open, and ordinary weekdays do not move. Run targeted tests and the full suite.
- [x] **Step 5: Commit.** Stage these two files; commit `feat: add explicit TARGET payment adjustment`.

## Task 3: Pure regular schedule and eligibility assessment

**Files:** Create `MyBondManager/BondSchedule.swift`, `MyBondManagerTests/BondScheduleTests.swift`; extend `MyBondManagerTests/BondTermsFixtures.swift`. Modify `CashFlowEntity+CoreDataProperties.swift` only to make `Nature` also `Codable, Sendable` without changing raw values.

**Interfaces:** Consumes Task 1/2 types. Produces:

```swift
struct BondTrade: Codable, Equatable, Sendable {
    let id: UUID
    let isin: String
    let nominal: Double
    let cost: Double
    let acquisitionDay: MarketDay
    let bank: String
}
struct BondPayment: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable { case interest, maturity }
    let kind: Kind
    let contractualDay: MarketDay
    let paymentDay: MarketDay
    let amount: Double
    let identity: String // bond UUID|kind|contractual YYYY-MM-DD
}
struct ProjectedFlow: Codable, Equatable, Sendable {
    let contractualDay: MarketDay
    let paymentDay: MarketDay
    let amount: Double
    let nature: CashFlowEntity.Nature
    let eventIdentity: String? // real interest/principal only
}
struct BondSchedulePreview: Equatable, Sendable {
    let assessment: TermsAssessment
    let payments: [BondPayment]
    let flows: [ProjectedFlow]
    let redemptionDay: MarketDay?
    let estimatedYTM: Double?
}
enum BondSchedule {
    static func preview(trade: BondTrade, terms: BondTerms, from: MarketDay) throws -> BondSchedulePreview
}
```

- [x] **Step 1: Add deterministic schedule fixtures and tests.** `BondTermsFixtures.fixed(frequency: Int = 2, maturity: String = "2027-01-15", next: String = "2026-07-15") throws -> BondTerms` returns EUR/fixed/3.375%, accrual `2026-01-15`, callable false, redemption 100, explicit day-of-month roll, checkpoint observed `2026-02-01`, collected at `2026-02-01T12:00:00Z`, approved nil, default conventions. `BondTermsFixtures.trade(cost: Double = 100000) throws -> BondTrade` uses a fixed UUID `00000000-0000-0000-0000-000000000001`, ISIN `DE0000000001`, nominal 100000, acquisition `2026-02-01`, bank `Bank`.

```swift
func testSemiannualBuyerReceivesFullNextCoupon() throws {
    let result = try BondSchedule.preview(trade: BondTermsFixtures.trade(),
        terms: BondTermsFixtures.fixed(), from: MarketDay("2026-02-01"))
    XCTAssertTrue(result.assessment.supported)
    let coupons = result.payments.filter { $0.kind == .interest }
    XCTAssertEqual(coupons.map { $0.contractualDay.rawValue }, ["2026-07-15", "2027-01-15"])
    XCTAssertEqual(coupons.map(\.amount), [1687.5, 1687.5])
}
func testHolidayFinalCouponAndRedemptionMoveTogetherWithoutExtraInterest() throws {
    let terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2027-01-01", next: "2027-01-01")
    var annual = terms
    annual.accrualStart = try MarketDay("2026-01-01")
    let result = try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: annual,
        from: MarketDay("2026-02-01"))
    XCTAssertEqual(result.payments.map { $0.paymentDay.rawValue }, ["2027-01-04", "2027-01-04"])
    XCTAssertEqual(result.payments.first?.amount, 3375)
    XCTAssertEqual(result.payments.last?.amount, 100000)
}
```

- [x] **Step 2: Run RED.** Use `-only-testing:MyBondManagerTests/BondScheduleTests`, log `/tmp/mybond-schedule-red.log`. Tests must fail until amount/frequency/holiday logic exists.
- [x] **Step 3: Implement validation and anchored generation.** Reject invalid trade numbers as errors. Unsupported/missing terms return named assessment reasons and empty payments/flows. Readiness requires EUR; fixed or zero; finite nonnegative rate; positive redemption; known callable flag; supported convention values; maturity not before acquisition; no retained unsupported restrictions. Fixed also requires frequency 1/2/4, accrual start and checkpoint; zero ignores frequency/checkpoint and requires zero rate. Support Actual/Actual(ICMA), TARGET and Following in this phase; other overrides are retained but need review.

Generate contractual boundaries backward from maturity using offsets `0, -12/frequency, -2*12/frequency` against the original maturity anchor, not iterative clamped dates. Cap at 1200 periods and fail with a reason on inconsistent/range overflow. Accrual start must be a boundary; otherwise identify a short/long period. If end-of-month and day-of-month rules produce different eligible dates and roll is unspecified, require explicit confirmation. Validate the next checkpoint against the first contractual boundary on/after `checkpointObservedOn`, not against today's date; an aged response is not itself a malformed schedule. Persist collection time to explain an aged checkpoint in review.

For eligible contractual dates on/after acquisition, adjust the payment separately, then filter by payment day >= `from`. Sort interest before maturity on the same payment day. Never forecast interest after contractual maturity.

```swift
let coupon = trade.nominal * rate / 100 / Double(frequency)
let redemption = trade.nominal * redemptionPercent / 100
let delta = redemption - trade.cost
let principal = delta > 0 ? trade.cost : redemption
// Emit principal plus positive gain = redemption, or principal = redemption plus signed analytical loss.
// expectedProfit = eligible projected interest + delta; never count it as cash.
let years = maturity.instant.timeIntervalSince(trade.acquisitionDay.instant) / (365 * 86400)
let estimate: Double? = years > 0
    ? ((trade.nominal * rate / 100 + delta / years) / ((redemption + trade.cost) / 2)) * 100 : nil
```

`estimate` is `Double?`: undefined duration produces nil, never a displayed zero estimate. This pure result is the sole source of derived yield for approved terms; do not retain ING yield or the previous stored estimate after a terms change.

- [x] **Step 4: Add literal coverage for all branches.** Annual 3375, quarterly 843.75; zero produces only redemption; 95% redemption yields 95000 and loss -5000 at cost 100000 with cash total 95000; 105% at cost 100000 yields principal 100000 plus gain 5000. Test first/last stubs, ambiguous February roll, unknown frequency, unknown callable, non-EUR, floating/perpetual restrictions, unsupported convention, negative/nonfinite numbers, next checkpoint before/after allowed range, DST and a response reviewed after its checkpoint date. Callable true adds a warning, not exclusion. No test compares an expected value computed with the schedule builder itself. Run full suite.
- [x] **Step 5: Commit.** Commit `feat: calculate supported regular EUR bond schedules` with the named files.

## Task 4: Additive storage, fresh serialized writes, and migration fixtures

**Files:** Create `MyBondManager/MyBondManager.xcdatamodeld/MyBondManagerV3.xcdatamodel/contents`, `MyBondManager/BondTermsStore.swift`, `MyBondManagerTests/BondTermsStorageTests.swift`; modify `.xccurrentversion`, `BondEntity+CoreDataProperties.swift`, `CashFlowEntity+CoreDataProperties.swift`, `MyBondManager/PortfolioTransaction.swift`, `MyBondManagerTests/PersistenceMigrationTests.swift`, `MyBondManagerTests/TestPortfolio.swift`.

**Interfaces:** Consumes Tasks 1-3. Produces `BondBaseline.capture(_ bond: BondEntity) -> BondBaseline`, `BondTermsStore.read(_ bond: BondEntity) throws -> BondTerms?`, `trade(_ bond: BondEntity) throws -> BondTrade`, `stageDraft(_ draft: BondTermsDraft, for bond: BondEntity) throws`, `readDraft(_ bond: BondEntity) throws -> BondTermsDraft?`, `clear(_ bond: BondEntity)`, `isReady(_ bond: BondEntity) -> Bool`, and `replaceProjections(for:terms:preview:now:acquisitionDay:legacyDateZone:context:) throws -> Void` with parameters `(BondEntity, BondTerms, BondSchedulePreview, Date, MarketDay, String, NSManagedObjectContext)` respectively. `BondBaseline` is a Codable/Equatable/Sendable snapshot of UUID, normalized ISIN, name/issuer/WKN, bank, original acquisition/maturity instants, nominal, cost, rate and current terms bytes. `BondTermsDraft` is Codable/Equatable/Sendable with `baseline: BondBaseline`, `trade: BondTrade`, `legacyDateZone: String`, `proposed: BondTerms`, `previewDay: MarketDay`; it intentionally excludes derived preview rows so resumption recalculates with the same pure engine.

- [x] **Step 1: Write migration/readiness and isolated-write tests.** Extend the existing disposable SQLite migration test to load each named source model (`MyBondManager.mom`, `MyBondManagerV2.mom`), insert a bond, one flow and a history record with raw NSManagedObject setters, close/reopen with the new current model, and assert unchanged original values/counts plus absent terms and readiness false. Add an in-memory test whose older stored rows survive while `read` returns nil.

```swift
func testLegacyPositionRemainsStoredButUnapproved() throws {
    let store = try TestPortfolio.make()
    let bond = TestPortfolio.bond(in: store.viewContext)
    let oldFlow = CashFlowEntity(context: store.viewContext)
    oldFlow.date = TestPortfolio.date("2027-01-01T00:00:00Z")
    oldFlow.amount = 1000; oldFlow.nature = "principal"; oldFlow.bond = bond
    try store.viewContext.save()
    XCTAssertNil(try BondTermsStore.read(bond))
    XCTAssertFalse(BondTermsStore.isReady(bond))
    XCTAssertGreaterThan(bond.cashFlowsArray.count, 0)
}
```

- [x] **Step 2: Run RED.** Target `BondTermsStorageTests` and `PersistenceMigrationTests`; absent mappings/current-model fields are expected failures, never point tests at the production store.
- [x] **Step 3: Add V3 metadata without editing older models.** Copy V2 to V3 and add exactly these optional fields plus the two false-default booleans. Add matching @NSManaged declarations and switch `.xccurrentversion` to V3:

| Entity | Name / Core Data type |
| --- | --- |
| BondEntity | `termsData` Binary optional; `termsDraftData` Binary optional |
| BondEntity | `termsReady` Boolean default NO; `termsIssue` String optional |
| BondEntity | `termsAcquisitionDay` String optional; `termsLegacyDateZone` String optional |
| BondEntity | `termsEffectiveFrom` String optional; `eventsActivateAfter` Date optional |
| BondEntity | `redemptionPaymentDate` Date optional; `legacyEventAliasesData` Binary optional |
| CashFlowEntity | `contractualDay` String optional; `eventIdentity` String optional |
| CashFlowEntity | `generatedFromTerms` Boolean default NO |

Encode the terms/drafts with JSONEncoder ISO-8601 dates in version-1 internal envelopes, decode through validating types, and surface corrupt bytes as a Needs review reason/error, never as an annual fallback. This is optional data on existing entities, not a new shared instrument system. `clear` removes all native state and caches while leaving historical rows alone. Add `TestPortfolio.legacyBond(in:cost:par:)` as an explicit alias of today's unapproved fixture and `TestPortfolio.readyBond(in: NSManagedObjectContext, terms: BondTerms, now: Date, nominal: Double = 1000, cost: Double = 900) throws -> BondEntity` using the real preview/staging APIs with final trade values set before approval. Set its acquisition day to 2026-02-01, and adopt the fixture terms' coupon/maturity before preview. Do not make the default fixture implicitly approved; owning tests must state which state they exercise.

Serialize all existing `PortfolioTransaction.run` writes per persistent-store coordinator while retaining a fresh context per operation. A terms approval and launch recording must not stage from simultaneous stale snapshots. Use a weak-key lock registry and hold the store lock around the synchronous `context.perform` closure's fetch/change/save; do not await while locked. All current active writes already go through this helper except startup empty-ETF cleanup; keep that launch-only cleanup unchanged.

```swift
private static let registryGuard = NSLock()
private static let storeLocks = NSMapTable<NSPersistentStoreCoordinator, NSLock>.weakToStrongObjects()
private static func lock(for coordinator: NSPersistentStoreCoordinator) -> NSLock {
    registryGuard.lock()
    defer { registryGuard.unlock() }
    if let lock = storeLocks.object(forKey: coordinator) { return lock }
    let lock = NSLock()
    storeLocks.setObject(lock, forKey: coordinator)
    return lock
}
// Obtain lock before context.perform; inside its synchronous closure:
storeLock.lock()
defer { storeLock.unlock() }
// Existing do/changes/save/catch/rollback remains inside this protected region.
```

`replaceProjections` is the only supported terms-application writer. Before deleting eligible old rows, snapshot legacy aliases, keep past-day rows, and preserve every HistoricalValuation row. Set approved profile bytes, acquisition day/zone, effective day and adjusted redemption cache. Establish activation at `now` only for first approval or a changed approval timestamp; regeneration with the same approved profile must preserve its activation instant. Native import explicitly establishes a new destination activation at its import instant even if the same approved profile previously existed. Update the instrument's legacy coupon/maturity fields from the reviewed profile and its derived `yieldToMaturity` from `preview.estimatedYTM`, without changing nominal/cost/acquisition instant/bank. Persist real-payment identities on new interest/principal rows; gain/loss/expectedProfit rows are analytical. Missing/unsupported terms cache readiness false with a reason and do not delete preserved old rows. This method stages only; its caller owns the save.

Yield is derived data, not an immutable trade input. Approval, regeneration and approved native import all call this writer and replace its stored estimate in the same transaction as the projections:

```swift
bond.yieldToMaturity = preview.estimatedYTM ?? 0
```

The zero fallback preserves the existing nonoptional numeric storage/legacy JSON contract only. Add `BondTermsStore.estimatedYTM(_ bond: BondEntity) throws -> Double?`: return nil for unresolved holdings; for Ready holdings recompute the pure preview using saved terms/trade and return its optional estimate. Detail and summary use this availability policy (nil renders unavailable and is omitted from weighted yield); valid estimates agree with the persisted number. No unsupported holding becomes a zero-yield investment in the weighted average. Propagate corrupt-profile errors through existing error presentation. Native transfer validates/recalculates this derived field rather than trusting the source number blindly.

Add this writer regression in `BondTermsStorageTests` before implementing the assignment:

```swift
func testApprovedRedemptionReplacesTheStoredYieldEstimate() throws {
    let container = try TestPortfolio.make()
    var terms = try BondTermsFixtures.fixed()
    terms.redemptionPercent = 105
    let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: terms,
        now: TestPortfolio.date("2026-02-03T12:00:00Z"), nominal: 100000, cost: 100000)
    let expected = try BondSchedule.preview(trade: BondTermsStore.trade(bond),
        terms: terms, from: MarketDay("2026-02-03"))
    let estimate = try XCTUnwrap(expected.estimatedYTM)
    XCTAssertEqual(bond.yieldToMaturity, estimate, accuracy: 1e-10)
    XCTAssertEqual(try XCTUnwrap(BondTermsStore.estimatedYTM(bond)), estimate, accuracy: 1e-10)
}
```

Also seed a stale stored yield before reapproval with a changed redemption, then assert replacement; run regeneration twice and assert the same number without changing approval or activation. Task 8 verifies detail/weighted-summary inputs; Task 9 verifies exported values and native round trips against this result.

- [x] **Step 4: Test aliases, corrupt metadata and serialization.** Before changing production behavior, add a test with one writer paused after reading a stored value and a second writer attempting an increment. Release the first, then assert final value increased twice; the second must not read the original value. Use test-owned expectations/semaphores only on background queues and a bounded timeout. Also assert failure releases the lock and preserves an unrelated main-context draft. For alias capture, map each legacy interest flow's calendar date using `termsLegacyDateZone` (or the review's explicit legacy display zone before first approval) to the new contractual identity, retaining the exact old `UUID|interest|Int(oldDate.timeIntervalSince1970)` key. Map legacy maturity similarly. Merge prior aliases, including already generated rows; never erase them on a second recalculation. No alias table is transferred to a different Mac. Run all migration/storage/transaction tests, then full suite.
- [x] **Step 5: Commit.** Commit `feat: persist optional bond terms with safe write isolation`. Activation/eligibility switches are not exposed in the live UI until Tasks 7-10, so this task does not silently disable legacy behavior mid-branch.

## Task 5: Decode richer ING terms without inventing missing data

**Files:** Modify `MyBondManager/Scrapper.swift`, `MyBondManager/BondCollection.swift`, `MyBondManager/AddBondView.swift`, `MyBondManagerTests/BondCollectionTests.swift`; create `MyBondManagerTests/INGBondTermsTests.swift`, `MyBondManagerTests/INGBondFixtures.swift`.

**Interfaces:** Extend `BondDetails` to represent partial provider responses. Keep the same initializer labels so existing complete fixtures remain source-compatible through optional promotion; use this explicit initializer, not a default-valued `let` that cannot be supplied through a memberwise initializer:

```swift
struct BondDetails: Sendable {
    let name: String
    let wkn: String
    let issuer: String
    let maturityDate: Date?
    let couponRate: Double?
    let terms: BondTerms?
    init(name: String, wkn: String, issuer: String, maturityDate: Date?,
         couponRate: Double?, terms: BondTerms? = nil) {
        self.name = name; self.wkn = wkn; self.issuer = issuer
        self.maturityDate = maturityDate; self.couponRate = couponRate; self.terms = terms
    }
}
```

Add `BondDataScraper.fetchDetails(isin: String, observedAt: Date = Date()) async throws -> BondDetails`. Preserve existing complete-data scraper method signatures for callers that explicitly require complete data. `BondCollection` retains its request guard and injectable async fetch but uses `fetchDetails` by default. Missing coupon/maturity is a successful partial collection; supplied invalid values still throw. Optional legacy display mirrors must agree with the corresponding supplied terms; no fallback to zero or today's date. Existing holdings display baseline values separately, without copying them into absent provider terms. Adapt `AddBondView` and `BondCollectionTests` in this task so optional handling compiles immediately: blank missing inputs, optional binding before arithmetic, and explicit validation before building nonoptional `BondCodable`. New entry requires user-confirmed valid coupon/maturity position fields to save a holding; it can retain its incomplete form meanwhile, and missing other support terms may still save the holding as Needs review.

- [x] **Step 1: Write literal response-fixture tests.** Reuse a URLProtocol fake with a path-indexed response map and no live network. A single `INGBondFixtures.responses` test constant holds these independent bodies:

```swift
let dates = #"{"issueDate":{"value":"2026-02-02T00:00:00+01:00"},"interestStartDate":{"value":"2026-01-15T00:00:00+01:00"},"maturityDate":{"value":"2027-01-15T00:00:00+01:00"},"interestPaymentDate":{"value":"2026-07-15T00:00:00+02:00"}}"#
let master = #"{"issuerCompanyName":{"value":"Issuer"},"currencyIsoCode":{"value":"EUR"},"isBondCallableBeforeMaturity":{"value":false}}"#
let rates = #"{"interest":"Fest","interestPaymentPeriod":"Halbjährlich","isZeroBond":false,"redemptionPayment":100,"data":[{"id":"InterestRate","fieldValue":{"value":3.375}}]}"#
let header = #"{"instrumentName":"EUR note","wkn":"TEST01"}"#
```

```swift
func testKeepsCouponFrequencyAccrualAndCalendarDate() async throws {
    let scraper = BondDataScraper(session: INGBondFixtures.session())
    let details = try await scraper.fetchDetails(isin: "DE0000000001",
        observedAt: TestPortfolio.date("2026-02-03T12:00:00Z"))
    let terms = try XCTUnwrap(details.terms)
    XCTAssertEqual(terms.frequency, 2)
    XCTAssertEqual(terms.couponRate, 3.375)
    XCTAssertEqual(terms.accrualStart?.rawValue, "2026-01-15")
    XCTAssertEqual(terms.nextCoupon?.rawValue, "2026-07-15")
    XCTAssertEqual(terms.issueDay?.rawValue, "2026-02-02")
    XCTAssertEqual(terms.callable, false)
}
```

- [x] **Step 2: Run RED.** Target `INGBondTermsTests` and `BondCollectionTests`, log `/tmp/mybond-ing-terms-red.log`. The old decoder cannot supply these new terms.
- [x] **Step 3: Implement endpoint DTOs and mappings.** Decode value wrappers as optional values where ING can omit a field. Map `Jährlich`/`Halbjährlich`/`Vierteljährlich` to 1/2/4; retain raw unknown values. Recognize `Fest` as fixed; a true `isZeroBond` selects zero only if rate is zero. Preserve provider-indicated floating/indexed/perpetual/amortizing restrictions; a manually changed structure label cannot erase them. Missing metadata yields incomplete terms, while malformed JSON/nonfinite financial fields or malformed supplied date strings produce explicit errors. Validate the exact leading YYYY-MM-DD part of ING dates and its optional ISO suffix; an empty supplied date cannot trap. Keep original issue and accrual dates distinct. The optional header name can help identify a restriction but never proves support. Never use `Yield`, `duration` or `yieldPopupContent` as exact bond-pricing inputs.

```swift
let frequency = ["Jährlich": 1, "Halbjährlich": 2, "Vierteljährlich": 4][rawPeriod]
var terms = BondTerms()
terms.isin = ETFPurchase.normalizedISIN(isin)
terms.frequency = frequency
terms.rawFrequency = rawPeriod
terms.callable = masterData.isBondCallableBeforeMaturity?.value
terms.checkpointObservedOn = MarketDay(date: observedAt)
terms.collectedAt = observedAt
```

Implement `INGBondFixtures.session(responses: [String: Data] = responses) -> URLSession` using an ephemeral configuration and a test-only URLProtocol fixture handler, with handler cleanup in teardown. Complete the map by matching URL path suffixes, not actual DNS. If accessing a static fixture handler across URLProtocol queues, protect it with a lock; do not make product classes carry test cleanup APIs.

For absent rate/maturity, construct `BondDetails` directly from optional DTOs rather than calling the old complete-data fetch methods. In `BondCollection.collect`, validate a rate only when present:

```swift
if let rate = result.couponRate, !rate.isFinite || rate < 0 {
    throw PortfolioError("The provider returned an invalid coupon rate.")
}
details = result
```

Add independent missing-rate and missing-maturity response variants to the literal fixture map by omitting the actual field, not substituting zero/empty dates. Assert collection succeeds, the corresponding `BondDetails` and `BondTerms` fields remain nil, and preview reports the named missing term.
- [x] **Step 4: Test unknowns and stale responses.** Missing `callable` stays nil; missing frequency stays nil; unknown periods stay unsupported. A zero bond with a nominal next-interest date still produces no coupons. Test empty dates, 31 February, differing issue/accrual years, numeric-string rates, non-EUR, rate/type contradictions, stale response after ISIN change, and two requests for the same ISIN completing in reverse order. Run full suite.
- [x] **Step 5: Commit.** Commit `feat: retain ING bond instrument terms and provenance` with the named production/test files only.

## Task 6: Resumable review and atomic forward approval

**Files:** Create `MyBondManager/BondTermsReview.swift`, `MyBondManagerTests/BondTermsReviewTests.swift`; extend `BondTermsStore.swift`, `BondCollection.swift`; modify `MyBondManager/AddBondView.swift`, `EditBondView.swift`, `CashFlowGenerator.swift` only at their persistence seams, before UI wiring in Task 10.

**Interfaces:** Produces the following service/model contract. `BondTermsReview` is @MainActor ObservableObject with `@Published private(set) var drafts: [UUID: BondTermsDraft]`, `errors: [String: String]`, `isWorking: Bool`; init takes `container: NSPersistentContainer`, `fetch: @escaping (String) async throws -> BondDetails` and `now: @escaping () -> Date = Date.init`. Methods: `load() async throws`, `collect(ids: [UUID]) async`, `edit(_ draft: BondTermsDraft) async throws`, `preview(_ draft: BondTermsDraft) throws -> BondSchedulePreview`, `apply(ids: [UUID]) async throws`, `saveNew(values: BondCodable, terms: BondTerms, legacyDateZone: String) async throws -> UUID`. Add `CashFlowGenerator.regenerateCashFlows(for: BondEntity, now: Date)`; the existing overload delegates using Date().

- [x] **Step 1: Write stateful service tests.** Create two purchases with the same ISIN and a third different ISIN whose fixture fetch throws. Count the real fake-boundary fetches, assert two network-boundary calls rather than three, and assert both successful purchase drafts survive the third error. Restart `BondTermsReview` against the same in-memory store and assert drafts/resolved state reload without fetching.

```swift
func testApprovalPreservesTradeAndHistoryAndRejectsStaleReview() async throws {
    let container = try TestPortfolio.make()
    let bond = TestPortfolio.legacyBond(in: container.viewContext)
    bond.acquisitionDate = TestPortfolio.date("2026-02-01T00:00:00Z")
    bond.maturityDate = TestPortfolio.date("2027-01-15T00:00:00Z")
    bond.couponRate = 3.375
    try HistoricalDataRecorder.recordBondAcquisition(bond: bond, context: container.viewContext)
    try container.viewContext.save()
    let review = BondTermsReview(container: container,
        fetch: { _ in try BondTermsFixtures.details() },
        now: { TestPortfolio.date("2026-02-03T12:00:00Z") })
    await review.collect(ids: [bond.id])
    bond.initialPrice = 1200
    try container.viewContext.save()
    do { try await review.apply(ids: [bond.id]); XCTFail("Expected changed trade rejection") }
    catch {}
    XCTAssertEqual(bond.initialPrice, 1200)
    XCTAssertEqual(try container.viewContext.count(for: HistoricalValuation.fetchRequest()), 1)
}
```

`BondTermsFixtures.details() throws -> BondDetails` returns the fixed fixture from Task 3 in the actual BondDetails type with the optional terms populated; name `EUR note`, WKN `TEST01`, issuer `Issuer`, maturity equal to the terms' maturity instant and coupon 3.375. The test's legacy dates above are intentionally compatible with the proposed terms.

Verify the partial-result contract end-to-end with this separate regression in the `@MainActor` review test class. The provider's missing value must survive persistence and relaunch without being filled from the holding's display baseline:

```swift
func testMissingProviderTermsPersistUntilExplicitCorrection() async throws {
    for missingField in ["couponRate", "maturity"] {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.legacyBond(in: container.viewContext)
        bond.acquisitionDate = TestPortfolio.date("2026-02-01T00:00:00Z")
        bond.maturityDate = TestPortfolio.date("2027-01-15T00:00:00Z")
        bond.couponRate = 3.375
        try container.viewContext.save()
        var partial = try BondTermsFixtures.fixed()
        if missingField == "couponRate" { partial.couponRate = nil }
        else { partial.maturity = nil }
        let response = BondDetails(name: "EUR note", wkn: "TEST01", issuer: "Issuer",
            maturityDate: partial.maturity?.instant, couponRate: partial.couponRate, terms: partial)
        let review = BondTermsReview(container: container, fetch: { _ in response },
            now: { TestPortfolio.date("2026-02-03T12:00:00Z") })
        await review.collect(ids: [bond.id])
        let resumed = BondTermsReview(container: container, fetch: { _ in
            throw PortfolioError("Load must not fetch.")
        }, now: { TestPortfolio.date("2026-02-03T12:00:00Z") })
        try await resumed.load()
        var draft = try XCTUnwrap(resumed.drafts[bond.id])
        XCTAssertFalse(try resumed.preview(draft).assessment.supported)
        if missingField == "couponRate" { XCTAssertNil(draft.proposed.couponRate) }
        else { XCTAssertNil(draft.proposed.maturity) }
        draft.proposed.couponRate = 3.375
        draft.proposed.maturity = try MarketDay("2027-01-15")
        draft.proposed.confirmedFields.insert(missingField)
        try await resumed.edit(draft)
        try await resumed.apply(ids: [bond.id])
        try await container.viewContext.perform {
            container.viewContext.refreshAllObjects()
            XCTAssertTrue(BondTermsStore.isReady(bond))
        }
    }
}
```

- [x] **Step 2: Run RED.** Target `BondTermsReviewTests`, log `/tmp/mybond-review-red.log`. The absent service or stale-write acceptance should fail.
- [x] **Step 3: Implement load/collect/edit/preview/apply.** Snapshot UUIDs and trade baselines on the view context queue, fetch sequentially once per normalized ISIN, and write resulting drafts in isolated transactions. Deduplicate request identities and reject stale/late results. Manual refresh merges confirmed overrides from the existing terms into the proposed draft; present provider differences, never silently replace a confirmed override. Persist successful drafts independently of other failed fetches.

At approval, freeze the selected drafts before awaiting. Re-resolve each UUID exactly once, reject duplicate/missing identities, compare every baseline financial/instrument field and existing terms bytes, and require `previewDay == MarketDay(date: now())`; if the day changed, rebuild the preview and request confirmation rather than silently change the frozen approval. Revalidate support and use the same schedule preview; unsupported drafts can be saved as Needs review but cannot be falsely approved. Stage all selected valid approvals in one `PortfolioTransaction.run`; a failed member rolls back the selected batch only. Preserve original historical records byte-for-byte, all trade inputs and the launch checkpoint. New terms may update the reviewed instrument rate/maturity, the derived yield from the same preview, projections and native metadata; ordinary EditBondView historical trade guards remain enforced.

```swift
let frozen = ids.compactMap { drafts[$0] }
guard frozen.count == ids.count else { throw PortfolioError("A review item is missing.") }
let appliedAt = now()
try await PortfolioTransaction.run(in: container) { context in
    for draft in frozen {
        let request = BondEntity.fetchRequest()
        request.predicate = NSPredicate(format: "id == %@", draft.trade.id as CVarArg)
        let matches = try context.fetch(request)
        guard matches.count == 1, let bond = matches.first,
              BondBaseline.capture(bond) == draft.baseline else {
            throw PortfolioError("This holding changed. Refresh its review before applying.")
        }
        guard draft.previewDay == MarketDay(date: appliedAt) else {
            throw PortfolioError("The review day changed. Review the updated payment preview.")
        }
        var terms = draft.proposed
        let result = try BondSchedule.preview(trade: draft.trade, terms: terms, from: draft.previewDay)
        guard result.assessment.supported else { throw PortfolioError(result.assessment.reasons.joined(separator: "\n")) }
        terms.approvedAt = appliedAt
        try BondTermsStore.replaceProjections(for: bond, terms: terms, preview: result, now: appliedAt,
            acquisitionDay: draft.trade.acquisitionDay, legacyDateZone: draft.legacyDateZone, context: context)
    }
}
```

`saveNew` stages a new bond, records acquisition once, stores reviewed terms or an incomplete draft, and creates Ready projections only when approved supported terms exist. Required nonoptional position coupon/maturity values must come from an explicit valid provider/user entry; reject saving when these are still absent, with field-specific form errors. Missing other support terms may still save a holding as Needs review. Existing-holding drafts with missing provider coupon/maturity are persisted independently of these position fields and can be corrected later. No new purchase may silently run the annual fallback. Recalculation uses stored terms and updates the derived yield with its new preview; it does not change `approvedAt`, activation time or reset aliases. Existing frozen imported/fixture profiles are validated through the same engine.
- [x] **Step 4: Pin failure/partial/time behavior.** Test deleted holding, duplicate UUIDs, changed bank/rate/maturity/cost/terms bytes, a failed save in the second selected bond, persisted partial review, unknown restrictions not erased by manual labels, confirmation overrides preserved, midnight while review open, and no network work on load/recalculate. Assert an approved future schedule differs while past flow values/history remain unchanged. Run full suite; adapt the old loaded-relationship regeneration test to create an explicit Ready fixture rather than bypass readiness globally.
- [x] **Step 5: Commit.** Commit `feat: review and approve bond terms without rewriting history`.

## Task 7: Stable prospective event recording and final adjusted payment

**Files:** Modify `MyBondManager/LaunchEventProcessor.swift`, `LaunchNotifier.swift`, `HistoricalDataRecorder.swift`, `CashFlowGenerator.swift`, `BondTermsStore.swift`; create `MyBondManagerTests/BondTermsEventTests.swift`; update `LaunchEventProcessorTests.swift`, `LaunchNotifierTests.swift`, `PortfolioWriteTests.swift`, `PortfolioTransactionTests.swift` where annual/unapproved fixture assumptions change.

**Interfaces:** Consumes stored approved profiles, generated payment identities and local aliases. Preserve `LaunchEventProcessor.stage(context:since:until:) throws -> [String]` and notifier's checkpoint contract. Add `BondTermsStore.legacyAliases(_ bond: BondEntity) throws -> [String: [String]]`; `BondTermsStore.projectedPayments(_ bond: BondEntity, from: MarketDay) throws -> [BondPayment]` recomputes from saved supported terms without network.

- [x] **Step 1: Write the weekend/legacy replay test.** Use an annual fixed bond maturing contractual `2027-01-01` with redemption 105%, nominal 1000 and cost 900. Apply on `2026-12-30T12:00:00Z`; seed a historical maturity row with the old exact timestamp key for original Jan 1 and save. Processing through Jan 4 must not create a second redemption. A separate unrecorded bond must record on Jan 4, not Jan 1, with invested delta -1000 and realized gain 150.

```swift
func testAdjustedMaturityUsesActualRedemptionAndNeverRunsEarly() async throws {
    let container = try TestPortfolio.make()
    var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2027-01-01", next: "2027-01-01")
    terms.accrualStart = try MarketDay("2026-01-01")
    terms.redemptionPercent = 105
    let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: terms,
        now: TestPortfolio.date("2026-12-30T12:00:00Z"), nominal: 1000, cost: 900)
    try container.viewContext.save()
    let before = try LaunchEventProcessor.stage(context: container.viewContext,
        since: TestPortfolio.date("2026-12-31T00:00:00Z"), until: TestPortfolio.date("2027-01-02T00:00:00Z"))
    XCTAssertTrue(before.isEmpty)
    let after = try LaunchEventProcessor.stage(context: container.viewContext,
        since: TestPortfolio.date("2027-01-02T00:00:00Z"), until: TestPortfolio.date("2027-01-05T00:00:00Z"))
    XCTAssertEqual(after.count, 2)
    let rows = try container.viewContext.fetch(HistoricalValuation.fetchRequest())
    XCTAssertEqual(rows.reduce(0) { $0 + $1.capitalGains.doubleValue }, 150)
}
```

The Task 4 `readyBond` factory calls the real preview/application operation with these final trade values; never mutate them after approval to manufacture the event expectation.
- [x] **Step 2: Run RED.** Target `BondTermsEventTests` and existing launch tests. The old processor records at contractual maturity with nominal rather than actual redemption and has no readiness gate; these should be behavioral failures.
- [x] **Step 3: Implement payment-driven processing.** Skip Needs review bonds; validate saved profiles. Recompute real payment candidates from stored terms, restrict to `(since, until]` and `paymentDay.instant > eventsActivateAfter`. Interest must respect contractual eligibility, not `paymentDate <= contractualMaturity`. Maturity uses adjusted redemption and actual redemption amount, with nominal invested-capital removal. Ignore analytical gain/loss/profit rows for event counting.

Before recording each candidate, check both its stable identity and every compatible legacy key captured before projection replacement. Legacy aliases only identify the same contractual event; never treat an unrelated payment in the same year or with the same amount as a match. Keep existing rows and keys unchanged.

```swift
let aliases = try BondTermsStore.legacyAliases(bond)[payment.identity] ?? []
let keys = [payment.identity] + aliases
let request = HistoricalValuation.fetchRequest()
request.predicate = NSPredicate(format: "eventKey IN %@", keys)
guard try context.count(for: request) == 0 else { continue }
let record = try HistoricalDataRecorder.recordChange(assetType: .bond, depotBank: bond.depotBank,
    investedDelta: payment.kind == .maturity ? -bond.parValue : 0,
    interestDelta: payment.kind == .interest ? payment.amount : 0,
    gainsDelta: payment.kind == .maturity ? payment.amount - bond.initialPrice : 0,
    date: payment.paymentDay.instant, context: context)
record.eventKey = payment.identity
```

For unkeyed legacy bond history, automatic attribution to one holding is unsafe. Before enabling prospective events on approval, detect ambiguous pre-activation records that could overlap the revised payment's contractual/adjusted window; mark that holding Needs review with a history-reconciliation reason instead of guessing, rewriting a row or posting a possible duplicate. This preserves the spec's no-silent-repair rule.
- [x] **Step 4: Add hard replay tests.** Repeat an interval; recalculate twice; reopen a loaded store; approve after an earlier-today payment; import approved terms on another Mac; and fail the save after staging two payments. Assert no earlier-today/source-history replay, checkpoint unchanged on failure, one final coupon plus one redemption after success, aliases retained through recalculation, and an unknown-history ambiguity does not create another entry. Run a test that queues approval against launch writing through the same transaction serialization; the operation order must remain consistent.
- [x] **Step 5: Run full suite and commit.** Update only tests whose old date/readiness assumptions genuinely changed, retaining old-key fixtures for compatibility. Commit `fix: record approved payments by stable contractual identity`.

## Task 8: Consistent readiness and adjusted maturity across consumers

**Files:** Create `MyBondManager/BondEligibility.swift`, `MyBondManagerTests/BondEligibilityTests.swift`; modify `MyBondManager/CashFlowSelection.swift`, `PortfolioSummaryView.swift`, `BondTableView.swift`, `MaturedBondsView.swift`, `CashFlowView.swift`, `MyBondManagerTests/CashFlowPresentationTests.swift`, `PortfolioCalculationsTests.swift`.

**Interfaces:** Consumes `BondTermsStore.isReady(_:)`, `MarketDay` and `BondSchedule`. Produces `BondEligibility.isActive(_ bond: BondEntity, on: MarketDay) -> Bool`, `BondEligibility.includes(_ flow: CashFlowEntity, from: MarketDay, through: MarketDay) -> Bool`, `BondEligibility.excludedCount(_ bonds: [BondEntity], on: MarketDay) -> Int`, and `BondEligibility.nextCoupon(_ bonds: [BondEntity], on: MarketDay) -> CashFlowEntity?`. Calls stay on the owning managed-object context. Readiness requires supported approved terms and current trade/profile consistency, not the cached flag alone.

- [x] **Step 1: Add consumer regressions.** An unresolved holding stays active and contributes capital; its stored old projections contribute nothing to forecast totals. A Ready bond whose contractual maturity is Jan 1 and payment is Jan 4 stays active through Jan 4 and becomes matured Jan 5.

```swift
func testUnreviewedHoldingKeepsCapitalButHasNoNextCoupon() throws {
    let container = try TestPortfolio.make()
    let bond = TestPortfolio.bond(in: container.viewContext)
    let row = CashFlowEntity(context: container.viewContext)
    row.date = TestPortfolio.date("2026-07-15T00:00:00Z")
    row.amount = 50; row.nature = CashFlowEntity.Nature.interest.rawValue
    row.bond = bond
    let today = try MarketDay("2026-02-01")
    XCTAssertTrue(BondEligibility.isActive(bond, on: today))
    XCTAssertEqual(BondEligibility.excludedCount([bond], on: today), 1)
    XCTAssertNil(BondEligibility.nextCoupon([bond], on: today))
    XCTAssertFalse(BondEligibility.includes(row, from: today, through: try MarketDay("2027-01-05")))
    XCTAssertEqual([bond].filter { BondEligibility.isActive($0, on: today) }
        .reduce(0) { $0 + $1.initialPrice }, bond.initialPrice)
}
```

- [x] **Step 2: Run RED.** Run `BondEligibilityTests` and `CashFlowPresentationTests` using the targeted runner below. Expect missing policy methods, then incorrect old maturity/readiness behavior.
- [x] **Step 3: Implement the shared policy and wire every consumer.** Keep unresolved legacy holdings active according to their displayed contractual maturity until corrected. Ready holdings use validated adjusted redemption. Include payment day itself in active holdings; strict following-day maturity matches existing whole-day presentation. Forecast selection requires Ready ownership, an eligible nature, the requested market-day range, and generated metadata consistent with the saved profile.

```swift
static func isActive(_ bond: BondEntity, on day: MarketDay) -> Bool {
    let lastDay = isReadyPaymentDay(bond) ?? MarketDay(date: bond.maturityDate)
    return lastDay >= day
}
```

Implement private `isReadyPaymentDay(_ bond: BondEntity) -> MarketDay?` inside `BondEligibility`: return the stored `redemptionPaymentDate` converted through `MarketDay` only when `BondTermsStore.isReady(bond)` succeeds; otherwise return nil. Use context-safe fetches broad enough to include delayed final payments, then apply the shared policy. Replace every `maturityDate >= today` shortcut in bond/cash-flow consumers; do not impose a contractual-maturity ceiling on the final adjusted coupon. Keep expected-profit analytical rows out of cash totals. Totals use invested cost/nominal for all active holdings, expected cash/profit and Estimated YTM from Ready holdings only. Do not show a zero yield as an available estimate when nothing is eligible. Groups with mixed readiness retain both purchases and show their unresolved count. Next coupon searches positive eligible interest payments; next redemption uses adjusted redemption. All date comparisons use market days rather than device-midnight predicates.
- [x] **Step 4: Pin summary, grouped and maturity boundaries.** Add a Ready/unresolved mixed-ISIN group; zero-coupon bond; Jan 1/Jan 4/Jan 5 states; a final delayed coupon; gain/loss decomposition; a device time zone west of UTC; and a no-eligible-yield case. In `PortfolioCalculationsTests`, assert capital includes both purchases while forecast totals include the Ready one only. For the 105% redemption fixture in Task 4, assert the detail yield input equals `BondTermsStore.estimatedYTM` and the weighted-summary numerator uses that new persisted estimate; unresolved/nil estimates contribute neither numerator nor denominator. In `CashFlowPresentationTests`, fetch through the real selection path and assert the Jan 4 final payment survives. Run the targeted tests and full suite.
- [x] **Step 5: Commit.** Commit `fix: apply bond readiness and payment dates across forecasts`.

## Task 9: Frozen legacy JSON and atomic native bond transfer

**Files:** Create `MyBondManager/BondTransfer.swift`, `MyBondManagerTests/BondTransferTests.swift`; modify `MyBondManager/ExportManager.swift`, `ImportManager.swift`, `PositionsTransferValidation.swift`, `MyBondManagerTests/PositionsTransferTests.swift`, `ImportManagerTests.swift`.

**Interfaces:** Keep `BondCodable` and `CashFlowCodable` unchanged. Add these value types to `BondTransfer.swift`; each is `Codable, Equatable, Sendable` except `PreparedBondTransfer`, which is `Equatable, Sendable`.

```swift
struct BondTermsEntry: Codable, Equatable, Sendable {
    let id: UUID
    let isin: String // normalized
    let terms: BondTerms? // nil is valid Needs review
    let draft: BondTerms? // proposed corrections survive native transfer
    let acquisitionDay: MarketDay
    let legacyDateZone: String
    let projectionFrom: MarketDay? // source termsEffectiveFrom, required for approved entries
    let needsReviewReasons: [String]
}
struct BondTermsEnvelope: Codable, Equatable, Sendable {
    let version: Int // exactly 1
    let bondsSHA256: String // lowercase SHA-256 of exact companion bytes
    let bonds: [BondTermsEntry]
}
struct PreparedBondTransfer: Equatable, Sendable {
    let bonds: [BondCodable]
    let bondsBytes: Data?
    let native: BondTermsEnvelope?
}
enum BondTransfer {
    static func prepare(bonds: Data, sidecar: Data?) throws -> PreparedBondTransfer
    static func snapshot(from context: NSManagedObjectContext) throws -> PreparedBondTransfer
    static func encode(_ snapshot: PreparedBondTransfer) throws -> (bonds: Data, sidecar: Data)
    static func validate(_ transfer: PreparedBondTransfer) throws
}
```

`BondTransfer.snapshot` returns a complete native envelope from a single coherent context read; `bondsSHA256` is empty only for that in-memory pre-encoding value. `encode` serializes the frozen bonds once, then returns a new envelope bound to those exact bytes; it does not mutate its input. Keep raw frozen companion bytes in `PreparedBondTransfer` as `bondsBytes: Data?` (nil only for a local pre-encoding snapshot), so apply-time validation can recheck the digest without relying on a re-encoding with potentially different JSON order. Require the decoded bytes to equal the frozen bond values semantically as well. External `prepare` never accepts an empty/invalid digest. `draft` transports proposed instrument fields, never a source `BondBaseline`: reconstruct destination drafts against destination holdings after import. Neither entry carries historical aliases, automatic-event activation, event records or the launch checkpoint. `legacyDateZone` preserves interpretation of the legacy acquisition date and must be a recognized time-zone identifier.

Add `ExportManager.exportBonds(to:from:) async throws -> URL`; `ImportManager.prepareBonds(from: URL) async throws -> PreparedBondTransfer`; `ImportManager.applyBonds(_ transfer: PreparedBondTransfer, into: NSPersistentContainer, now: Date = Date()) async throws`; and `PositionsTransferValidation.bondIssues(_ transfer: PreparedBondTransfer, context: NSManagedObjectContext) throws -> [String]`. Preserve existing all-positions public signatures.

- [x] **Step 1: Freeze the legacy shape with a literal fixture.** Put the following UTF-8 string in `BondTransferTests.swift`, decode using the existing ISO-8601 strategy, and assert round-trip JSON object key sets, value types, nature strings and whole-second date strings. Do not generate the expected fixture with the new encoder.

```swift
let legacyBondJSON = Data(#"[{"id":"00000000-0000-0000-0000-000000000001","name":"Example EUR","isin":"DE0000000001","issuer":"Example","depotBank":"Bank","acquisitionDate":"2026-02-01T00:00:00Z","maturityDate":"2027-01-15T00:00:00Z","couponRate":3.375,"parValue":100000,"initialPrice":99000,"yieldToMaturity":4.4,"wkn":"ABC123","cashFlows":[{"date":"2026-07-15T00:00:00Z","amount":1687.5,"nature":"interest"}]}]"#.utf8)

func testLegacyOnlyPreparationDoesNotRequireETFFile() throws {
    let transfer = try BondTransfer.prepare(bonds: legacyBondJSON, sidecar: nil)
    XCTAssertEqual(transfer.bonds.count, 1)
    XCTAssertNil(transfer.native)
    XCTAssertEqual(transfer.bonds[0].couponRate, 3.375)
}

func testSidecarDigestIsBoundToExactCompanionBytes() throws {
    let container = try TestPortfolio.make()
    _ = TestPortfolio.bond(in: container.viewContext)
    try container.viewContext.save()
    let snapshot = try BondTransfer.snapshot(from: container.viewContext)
    let files = try BondTransfer.encode(snapshot)
    let differentBytes = files.bonds + Data("\n".utf8)
    XCTAssertThrowsError(try BondTransfer.prepare(bonds: differentBytes, sidecar: files.sidecar))
    XCTAssertNoThrow(try BondTransfer.prepare(bonds: files.bonds, sidecar: files.sidecar))
}
```

The literal `interest` matches the current `Nature` contract. Assert the exact 13 bond keys and 3 flow keys listed in the spec; order is irrelevant. Ready export uses approved eligible projections; unresolved export has the same position fields and `cashFlows: []`.
- [x] **Step 2: Run RED.** Run `BondTransferTests`, `PositionsTransferTests` and `ImportManagerTests`. Missing codec/import methods must fail before implementation; retain original malformed/nested/rollback tests.

Include a real native yield round trip as a separate regression, so passing the schedule unit test cannot hide an unwired export/import:

```swift
func testNativeRoundTripKeepsTheApprovedDerivedYield() async throws {
    let source = try TestPortfolio.make()
    var terms = try BondTermsFixtures.fixed()
    terms.redemptionPercent = 105
    let bond = try TestPortfolio.readyBond(in: source.viewContext, terms: terms,
        now: TestPortfolio.date("2026-02-03T12:00:00Z"), nominal: 100000, cost: 100000)
    try source.viewContext.save()
    let expected = try XCTUnwrap(BondTermsStore.estimatedYTM(bond))
    let files = try BondTransfer.encode(BondTransfer.snapshot(from: source.viewContext))
    let frozen = try BondTransfer.prepare(bonds: files.bonds, sidecar: files.sidecar)
    XCTAssertEqual(try XCTUnwrap(frozen.bonds.first).yieldToMaturity, expected, accuracy: 1e-10)
    let destination = try TestPortfolio.make()
    try await ImportManager().applyBonds(frozen, into: destination,
        now: TestPortfolio.date("2026-02-04T12:00:00Z"))
    try await destination.viewContext.perform {
        let imported = try XCTUnwrap(destination.viewContext.fetch(BondEntity.fetchRequest()).first)
        XCTAssertEqual(imported.yieldToMaturity, expected, accuracy: 1e-10)
        XCTAssertEqual(try XCTUnwrap(BondTermsStore.estimatedYTM(imported)), expected, accuracy: 1e-10)
    }
}
```

Run this new test RED before wiring persisted/exported yield and GREEN after the full path is integrated. Annotate this test class `@MainActor` for view-context fixture setup.
- [x] **Step 3: Implement codec validation before mutations.** Use `CryptoKit.SHA256.hash(data:)`. Validate the exact digest before approval and require version 1; valid UUIDs/unique normalized identities; exactly one native entry for each bond; no missing/extra entries; financial finiteness and allowed values; strict date/provenance/enumeration decoding. Match UUID and normalized ISIN together. Preserve separate purchases sharing an ISIN. Validate a Ready claim by nonnil `approvedAt`, supported engine assessment, matching rate/maturity/acquisition, actual redemption and legacy decomposition. Require `projectionFrom` for an approved entry and compare its legacy rows on/after that day with the regenerated schedule multiset from that same day; older retained rows are individually validated legacy data, not evidence of an approved projection. Compare `projectionFrom` against approval time and reject inconsistent boundaries. Compare legacy instant strings at ISO-8601 second precision; compare instrument days canonically. An incomplete/unapproved/known-unsupported entry is valid Needs review, with no exported payments, even if its optional terms are absent. A corrupted approved claim is an error, not a downgraded success.

Refactor the existing export publication code into private `publish(files: [(name: String, data: Data)], to: URL, now: Date) throws -> URL` inside `ExportManager`, reusing security-scoped access, `.positions-UUID` staging, local-time `positions-yyyy-MM-dd_HH-mm-ss` naming, `-2` collision suffixes and injected writes. Both public exports capture values on their context queue before detached file work. Bond export publishes exactly `bonds.json` and `bond-terms.json`; all-positions export retains `bonds.json` and `etfs.json`. Both suppress unverified bond cash flows and report their exclusion count in the caller. Encode only after reading a saved consistent snapshot; reject a context with pending changes instead of exporting mixed saved/unsaved state.

Expose `ExportManager.snapshotBonds(from:)` internally and share its readiness-aware legacy projection with `BondTransfer.snapshot` and validation. Native snapshot obtains bonds and entries from the same fetch/context operation. Avoid fetching the same mutable context in two separate awaits.
- [x] **Step 4: Implement frozen category replacement.** `prepareBonds` reads companion bytes once under security-scoped access; only a genuinely missing sidecar means legacy mode. Permission/read/decode/digest errors must surface. Revalidate the value payload in `applyBonds`, then perform one isolated transaction: replace bonds by UUID, delete absent bonds/projections using existing category-replacement behavior, preserve history, clear all previous native metadata before applying incoming metadata, and preserve every ETF/price/holding. Empty `bonds: []` intentionally replaces the bond category with empty. The existing deletion path does not prohibit removing a position with recorded history: retain historical rows unchanged after removal and test that explicitly. Do not invent a new removal prohibition.

Approved native entries regenerate through the same engine and store writer; establish `eventsActivateAfter = now` locally. Imported source aliases/checkpoints cannot exist in this schema. Preserve destination aliases for the same UUID/ISIN where their local recorded event identity can be safely proven, and reject identity conflicts with local history. Existing all-positions legacy import must explicitly clear native metadata even when updating an existing UUID. Build one internal bond replacement operation shared by both import scopes; keep ETF replacement exclusive to all-positions mode. Validation compares expected exported projections, not hidden old unresolved storage rows; nested arrays remain multisets and Core Data object IDs remain irrelevant.

For approved entries, legacy `yieldToMaturity` must equal the pure preview estimate (or numeric zero when that optional estimate is unavailable), using tolerance `1e-10 * max(1, abs(expected))`. Reject an inconsistent claimed-approved yield; import then recalculates and persists the destination result through the writer rather than retaining a stale serialized number. Needs review legacy imports retain their legacy numeric field for schema compatibility while all native yield presentation/weighting excludes them. No new JSON keys are introduced.
- [x] **Step 5: Pin transfer failure and reuse boundaries.** Test ready fixed/zero/callable round trips without network; unresolved nil and unsupported terms; duplicate UUID, repeated ISIN purchases, extra/missing sidecar IDs, unsupported version, invalid calendar day, wrong zone, NaN/negative redemption, corrupted approved schedule, changed cost/rate and same IDs/different bytes. Test a frozen confirmation payload after disk files change; legacy replacement of a Ready same-UUID bond; empty replacement with preserved ETFs; removal retaining historical rows; failed second file write preserving previous exports; failed save rolling back bonds/terms while ETF and history stay unchanged; fresh destination activation without source-event replay. Run targeted and full suites.
- [x] **Step 6: Commit.** Commit `feat: transfer native bond terms beside unchanged legacy JSON`.

## Task 10: Review, entry and transfer UI with explicit exclusions

**Files:** Create `MyBondManager/BondTermsReviewView.swift`, `BondTermsFields.swift`; modify `MyBondManager/MainTabView.swift`, `AddBondView.swift`, `EditBondView.swift`, `ExportValidationView.swift`, `BondTableView.swift`, `PortfolioSummaryView.swift`, `MyBondManagerApp.swift`, `MyBondManagerTests/UIIsolationTests.swift`; create `MyBondManagerTests/BondTermsPresentationTests.swift`.

**Interfaces:** Consumes `BondTermsReview` and Task 9 frozen payload APIs. Produces `BondTermsReviewView(review: BondTermsReview)` and `BondTermsFields(terms: Binding<BondTerms>)`. Keep the service instance tied to the app-selected container and inject it into sheets; never construct a second production container in a view. Add `BondTermsPresentation` in `BondTermsFields.swift` with `status(assessment: TermsAssessment, approved: Bool) -> String`, `exclusions(_ count: Int) -> String?`, and `callWarning(_ terms: BondTerms) -> String?` as pure functions for tested copy.

- [x] **Step 1: Test the visible contract.** Pin empty/partial/Ready status, exclusions, and call warning before wiring views.

```swift
func testUnresolvedPaymentsAreExplicitlyExcluded() {
    let assessment = TermsAssessment(reasons: ["Coupon frequency is missing."], warnings: [])
    XCTAssertEqual(BondTermsPresentation.status(assessment: assessment, approved: false), "Needs review")
    XCTAssertEqual(BondTermsPresentation.exclusions(2), "Forecast excludes 2 holdings needing review.")
    XCTAssertNil(BondTermsPresentation.exclusions(0))
    var terms = BondTerms()
    terms.callable = true
    XCTAssertEqual(BondTermsPresentation.callWarning(terms), "Early redemption is not modeled.")
}
```

- [x] **Step 2: Run RED.** Run `BondTermsPresentationTests` and `UIIsolationTests`. Expect missing presentation contract; retain selected-container guarantees.
- [x] **Step 3: Implement fields and resumable review.** Bind corrections to `BondTerms` with supported frequency/structure/date/redemption/convention fields; retain unknown source labels and restrictions read-only. Display assumed/confirmed provenance and mark user corrections confirmed. Distinguish contractual maturity from redemption payment. Show old/proposed terms, dated payments, missing-field errors and call warning per purchase. Dates bind through explicit `MarketDay` conversion, never device-zone offset guessing. Show dates interpreted from legacy values and require confirmation when proposed days differ.

```swift
static func exclusions(_ count: Int) -> String? {
    guard count > 0 else { return nil }
    return count == 1 ? "Forecast excludes 1 holding needing review."
        : "Forecast excludes \(count) holdings needing review."
}
```

Use one initial review explanation, a persistent unresolved count/action and resumable drafts. Loading or normal launches never start a fetch. A user-initiated Collect action fetches unresolved selected ISINs, while Refresh explicitly proposes changes for approved holdings. Disable duplicate in-flight actions. Apply uses the frozen selection, surfaces stale/partial/save errors and refreshes views only after successful save. Separate Save as Needs review from Apply approved terms; do not call unsupported terms approved. No source edit may erase discovered restrictions to make a fixed label pass.
- [x] **Step 4: Wire entry and transfer without changing ETF flows.** New-bond save goes through `saveNew`, with incomplete purchases visible but excluded. Detail/ordinary edit retains existing historical financial-edit protection; terms changes open the controlled review. Label every yield surface Estimated YTM. Add Export Bonds and Import Bonds actions alongside existing all-positions transfer. Export result explains number of excluded schedules and both files' purpose. Import confirmation shows actual incoming/removed bond counts, native/legacy status, unresolved count and that bonds will be replaced; only the confirmation applies the already frozen payload. Legacy all-positions confirmation explains loss of approved terms. Sidecar failures show an actionable error before confirmation; no fallback button silently discards an invalid sidecar. Empty imports state explicitly that all bond positions will be removed. Preserve current controls/styles.
- [x] **Step 5: Verify UI state and run suites.** Extend `UIIsolationTests` with an in-memory container carrying both Ready and unresolved holdings and an ETF. Test copy/status derivation, import confirmation counts, no apply before confirmation, no fetch at startup/load, selected-container writes and errors that retain pending drafts. Open a dedicated in-memory SwiftUI preview for regular semiannual, callable, zero and incomplete holdings; inspect before/after review, delayed maturity, and both import modes. Record interactive checks actually performed. Run targeted and full suites.
- [x] **Step 6: Commit.** Commit `feat: expose bond terms review and bond-only transfer controls`.

## Task 11: Document, verify and independently review the complete change

**Files:** Modify `docs/portfolio-safeguards.md`, `docs/positions-transfer.md`; update this plan's execution checkboxes and append actual evidence. Touch implementation files only to resolve concrete failures/review findings, with a failing regression first.

**Interfaces:** Consumes the completed app and tests from Tasks 1–10; produces a reproducible validation record and a reviewed branch. No new runtime interfaces.

- [x] **Step 1: Document the shipped rules.** Describe one-time resumable collection, per-purchase approval, EUR/regular-only support, assumed defaults, callable warning, Needs review exclusions, adjusted maturity, prospective event activation, preserved history, and Estimated YTM. Show the two bond files and existing all-positions alternative; native approved reuse, legacy-only Needs review, digest failures, bond-category replacement/empty behavior, no history backup, and ETF preservation. Explicitly distinguish schema compatibility from an actual external-webapp check.
- [x] **Step 2: Run the full Debug suite and Release build.** Use the full test command in the workflow section, then:

```sh
xcodebuild -project MyBondManager.xcodeproj -scheme MyBondManager \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath /tmp/MyBondManager-bond-terms \
  CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= build \
  > /tmp/mybond-bond-terms-release.log 2>&1
```

Check process exit status and final XCTest/build result; record test totals/failures and log locations, without claiming a particular future count. Inspect V1/V2 migration tests, calendar/schedule golden cases, ETF regressions and local-only transfer temp directories. Inspect the in-memory UI preview. If the actual webapp is unavailable, record that runtime compatibility remains unverified; do not block truthful completion of repository work or claim it was checked. Broker-statement agreement is likewise separate from deterministic fixtures.
- [x] **Step 3: Obtain the independent review.** Use requesting-code-review against application baseline `33992ac5379b80ebb3b44d7a8c21620764880527` and the final feature head, supplying the spec, plan and evidence. Native execution gets one fresh final reviewer; Subagent-driven execution also requires the whole-branch review after per-task reviews. Review financial/event/transfer paths with connected code, not diff alone. Verify substantive findings before fixing under receiving-code-review; rerun affected tests and full suite after changes.
- [x] **Step 4: Commit documentation and evidence.** Commit `docs: explain approved bond schedules and native transfers` with only these docs and verified implementation corrections in their own scoped commits. Verify `git status --short`, `git log -1`, and the branch diff; keep local signing/workspace/generated files out. Do not push or merge without a new user request.
- [x] **Step 5: Hand off reviewable results.** Report implemented scope, test/build results, independent-review outcome, remaining external checks and local branch state. A Release build passing is not proof of an installed app or a live webapp check. Do not automatically launch against the user's real portfolio or perform the migration for them.

## Targeted execution commands and scoped commits

At execution time define this shell function in the test shell; each task's RED/GREEN command uses a real XCTest class and a distinct log. Keep RED evidence before implementation and verify failure cause rather than accepting an unrelated toolchain error.

```sh
bond_test() {
  local test_class="$1"
  local test_log="$2"
  xcodebuild -project MyBondManager.xcodeproj -scheme MyBondManager \
    -configuration Debug -destination 'platform=macOS' \
    -derivedDataPath /tmp/MyBondManager-bond-terms \
    "-only-testing:MyBondManagerTests/$test_class" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= test > "$test_log" 2>&1
}
bond_test MarketDayTests /tmp/mybond-market-day-red.log
bond_test BondTermsTests /tmp/mybond-terms-red.log
bond_test TargetCalendarTests /tmp/mybond-target-red.log
bond_test BondScheduleTests /tmp/mybond-schedule-red.log
bond_test BondTermsStorageTests /tmp/mybond-store-red.log
bond_test PersistenceMigrationTests /tmp/mybond-migration-red.log
bond_test INGBondTermsTests /tmp/mybond-scraper-red.log
bond_test BondTermsReviewTests /tmp/mybond-review-red.log
bond_test BondTermsEventTests /tmp/mybond-events-red.log
bond_test BondEligibilityTests /tmp/mybond-eligibility-red.log
bond_test BondTransferTests /tmp/mybond-transfer-red.log
bond_test BondTermsPresentationTests /tmp/mybond-presentation-red.log
```

Execute only the corresponding task's commands at that step; for GREEN use the same command with `-green.log`, followed by the full suite. Existing regression classes named in tasks run with the same function and their own class name. These are recipes, not a batch to run against unfinished later tasks.

For each task's commit, stage only its explicitly listed paths, inspect `git diff --cached`, then use its exact message. The following are the scoped new-file anchors; also stage that task's named modified files individually after reviewing them. Never use `git add .` or stage the entire Xcode project.

| Task | New-file staging anchor | Commit command |
| --- | --- | --- |
| 1 | `git add MyBondManager/MarketDay.swift MyBondManager/BondTerms.swift MyBondManagerTests/MarketDayTests.swift MyBondManagerTests/BondTermsTests.swift MyBondManagerTests/BondTermsFixtures.swift` | `git commit -m "feat: define EUR bond terms and market dates"` |
| 2 | `git add MyBondManager/TargetCalendar.swift MyBondManagerTests/TargetCalendarTests.swift` | `git commit -m "feat: add explicit TARGET payment adjustment"` |
| 3 | `git add MyBondManager/BondSchedule.swift MyBondManagerTests/BondScheduleTests.swift` | `git commit -m "feat: calculate supported regular EUR bond schedules"` |
| 4 | `git add MyBondManager/BondTermsStore.swift MyBondManagerTests/BondTermsStorageTests.swift` | `git commit -m "feat: persist optional bond terms with safe write isolation"` |
| 5 | `git add MyBondManagerTests/INGBondTermsTests.swift` | `git commit -m "feat: retain ING bond instrument terms and provenance"` |
| 6 | `git add MyBondManager/BondTermsReview.swift MyBondManagerTests/BondTermsReviewTests.swift` | `git commit -m "feat: review and approve bond terms without rewriting history"` |
| 7 | `git add MyBondManagerTests/BondTermsEventTests.swift` | `git commit -m "fix: record approved payments by stable contractual identity"` |
| 8 | `git add MyBondManager/BondEligibility.swift MyBondManagerTests/BondEligibilityTests.swift` | `git commit -m "fix: apply bond readiness and payment dates across forecasts"` |
| 9 | `git add MyBondManager/BondTransfer.swift MyBondManagerTests/BondTransferTests.swift` | `git commit -m "feat: transfer native bond terms beside unchanged legacy JSON"` |
| 10 | `git add MyBondManager/BondTermsReviewView.swift MyBondManager/BondTermsFields.swift MyBondManagerTests/BondTermsPresentationTests.swift` | `git commit -m "feat: expose bond terms review and bond-only transfer controls"` |
| 11 | `git add docs/portfolio-safeguards.md docs/positions-transfer.md docs/superpowers/plans/2026-10-15-bond-terms-and-schedules.md` | `git commit -m "docs: explain approved bond schedules and native transfers"` |

## Plan self-review and execution handoff

Review feedback resolved on 2026-10-15 after verifying current `BondCollection`, `AddBondView`, summary and export call sites:

- [x] Derived Estimated YTM now has one defined calculation/storage path through approval, regeneration and native import, explicit unavailable-value presentation, and regressions across persistence, summary/detail inputs and JSON/native round trips (Tasks 3/4/6/8/9). No change to legacy JSON field types.
- [x] Partial `BondDetails` can preserve missing provider coupon/maturity. Existing holdings retain their display baseline separately, incomplete drafts persist/reload, explicit correction enables approval, and new-position saving validates its required position inputs without invented provider values (Tasks 5/6/10).

These are corrections to the implementation instructions, not executed application fixes. Planned XCTest snippets remain to be run during implementation; this document update was checked for interface consistency and formatting only. The independent review's original verdict was With fixes; no second independent verdict is claimed.

Planning checks completed against the approved specification:

- [x] Coverage: terms/provenance and dates (Tasks 1/5); calendar/schedules (2/3); additive migration and serialized writes (4); resumable approval/history preservation (6/7); every forecast/maturity consumer (8); web/native transfer contracts (9); entry/review/import UI (10); docs, build and independent review (11).
- [x] Review Focus: each of the five failure classes maps to named owning-task tests; none is deferred to an unspecified future check.
- [x] Interface consistency: fixture trade values precede approval; storage and ING test class names match commands; native payload retains exact bytes and a source projection boundary; async file preparation matches the existing import pattern.
- [x] Placeholder scan: no unresolved implementation placeholders; each task supplies exact interfaces, a starting regression, implementation algorithm, verification and scoped commit checkpoint.
- [x] Scope: no application edits, test runs, branch integration or production data migration performed during planning. Pre-existing Xcode/generated changes are excluded.

This is one coupled feature: readiness, payment identity and transfer validation depend on the same terms/schedule contracts. Keep these tasks in order, and do not expose the review/import UI until the underlying safety gates are integrated. Each numbered task owns its regression cycle and commit; its steps may require multiple short edits to finish the listed independent cases.

Before implementation, the human reviews this written plan and selects Native or Subagent-driven execution. Recommended: Native, because these tasks share tightly coupled storage, date and identity interfaces; one implementer can keep those contracts aligned, followed by an independent whole-branch review. QuantLib, historical repair and exact yield remain excluded.


## Execution evidence

Native execution was authorized by the user's executing-plans invocation. Tasks 1-11 are implemented on `codex/bond-terms-schedules`, in the managed isolated worktree. The final review fixes are committed as `4c6afcd`; integration awaits the user's decision.

- Baseline: 62 tests passed.
- Final Debug suite: 125 tests passed, zero failures, xcodebuild exit 0. `/tmp/mybond-final-full-green.log` records the complete run. The task-11 completion gate repeats this full suite against the committed feature.
- Migration tests exercised both original and V2 SQLite stores upgrading to V3, retaining positions, cash flows and history.
- Synthetic in-memory portfolio/review renders inspected through XCTest attachments in `/tmp/mybond-bond-terms-ui-final`; no production store opened.
- External webapp rendering, broker-statement parity and real user-data migration/interactive modal clicks have not been performed.

- Final Release build: succeeded after review fixes, using ad hoc signing; `/tmp/mybond-bond-terms-release-final.log`. Local app: `/tmp/MyBondManager-bond-terms/Build/Products/Release/MyBondManager.app`. No installation or production launch performed.
- Fresh independent whole-branch review: verdict With fixes, two Important findings and no Critical findings. The annual leap-year roll ambiguity and stale rendered input after restoring saved terms each have observed failing regressions followed by a passing full suite. No second independent review is claimed.
- Exact additional integration cases now pass: an already recorded Saturday coupon is not replayed on adjusted Monday; approval overlapping a saving import rejects the stale trade and preserves ETF/history state.
- The rendered terms component is exercised with actual native text editing and an explicit reset. The complete Revert-button/modal interaction remains a manual check.
- Deferred minors: none reported by the reviewer.

### Execution decisions

The following chronological rulings preserve the execution ledger before its scratch workspace is removed.

- Ruling: Native worktree created from committed feature head and only approved documents copied — original signing/scheme/workspace changes remain in original checkout — cost if wrong: use command-line signing overrides for local tests.
- Task 4: Ruling: private Core Data JSON envelopes use Foundation exact numeric Date encoding instead of whole-second ISO — the subsecond regression proved ISO truncation makes approved holdings fail their trade baseline and changes approval instants — cost if wrong: private version-1 bytes differ from plan; public legacy/native wire date conventions remain unchanged. RED /tmp/mybond-store-instants-red.log.
- Task 6: Ruling: switch the legacy generator to readiness gating together with event consumers in Task 7 — their legacy annual fixtures must change in the same integration gate; the new review/save service already uses only approved schedules — cost if wrong: this intermediate commit retains the old generator until Task 7, never shipped separately.
- Task 7: Ruling: add defaulted now parameter to the legacy persistence generation helper and explicit fixture clocks — avoids tests depending on wall-clock maturity, preserving existing call sites — cost if wrong: one optional parameter on a dormant helper. Missing overload observed RED in /tmp/mybond-helper-clock-red.log.
- Task 7: Ruling: native-import activation regression belongs to Task 9 where that API is introduced — Task 7 cannot consume a future transfer API — cost if wrong: import activation is not verified until Task 9; no UI/native transfer is exposed before then.
- Task 8: Ruling: add explicit Berlin market date formatters and wire payment labels/month groups, preserving acquisition date formatting — canonical Berlin midnight otherwise renders as the previous day on a western device — cost if wrong: date labels now deliberately use the EUR market day rather than device-local day. Next Redemption shows actual redemption amount; average maturity uses adjusted date.
- Task 9: Ruling: legacy imports clear approval/profile data but retain safe local same-identity event aliases — they are destination deduplication state, never imported historical data — cost if wrong: stale aliases could suppress an event; retention is limited to same UUID/normalized ISIN and native mode also verifies trade identity against local keyed history.
- Task 10: Ruling: add optional expectedDestinationIDs to bond-only apply and recheck inside the transaction — a newly created holding after a replacement prompt was not part of the confirmed removal count — cost if wrong: a changed portfolio requires reconfirmation; existing programmatic calls keep default behavior.
- Final: Ruling: exact yield, accrued interest, irregular coupons, callable valuation and historical repair remain excluded — the approved scope exposes estimated yield and unsupported/callable warnings — cost if wrong: these instruments need a broader calculation model before reliable pricing.
- Final: Ruling: external webapp and broker parity are unverified — schema tests prove only the unchanged wire contract — cost if wrong: consumer behavior or statement differences need external validation.
- Final: Ruling: live ING compatibility is unverified — fixture-tested parsing stands pending a live provider check — cost if wrong: provider response drift can require parser updates.
- Final: Ruling: production migration and real modal interaction remain unperformed — synthetic migration/UI tests avoid touching the user's portfolio — cost if wrong: real-data or interaction-specific defects remain possible.
- Final: Ruling: reviewer did not repeat Release build — parent-run xcodebuild succeeded and will run again after fixes — cost if wrong: build evidence has no independent reproduction.
- Final: Ruling: rendered input-state regression replaces a virtual-button click test — native test-host accessibility does not expose the SwiftUI footer actions reliably; the same production reset token now owns the entire field component state — cost if wrong: complete Revert-button interaction still needs a manual UI check, while displayed values and invalid-input reset are tested directly.
