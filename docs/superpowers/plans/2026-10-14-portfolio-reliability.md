# Portfolio Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [x]`) syntax for tracking.

**Goal:** Protect portfolio writes, correct financial results, and make positions transfers and ETF refresh reliable with minimal changes.

**Architecture:** Keep the existing SwiftUI/Core Data structure. Add one small transaction helper shared by write operations; generators and history recorders stage changes while the caller owns the save. Extract only the small calculation, FIFO, and launch-processing seams needed to exercise actual behavior without driving SwiftUI.

**Tech Stack:** Swift 5.0, macOS 15.0, SwiftUI, Core Data, Foundation, XCTest, Xcode.

**Spec:** `docs/superpowers/specs/2026-10-14-portfolio-reliability-design.md`.

## Execution Record - 2026-10-14

All eight implementation tasks are complete on `codex/portfolio-reliability`, with 42 passing tests and a successful unsigned Release build. The independent whole-change review received one fix pass: restored explicit persistence in the dormant generation helper, added loaded-object merge checks, tested the edit form persistence action against an injected container, and rendered the fixture portfolio. The original-model lightweight migration is covered by a disposable SQLite test.

The recipe checkboxes below are closed. The user subsequently authorized a consolidated local commit. No push or merge is authorized. Interactive folder-panel selection and live endpoints/user portfolio data were not exercised; tests use real isolated Core Data stores, temporary files, and injected quotes.

Execution adjustments:

- Used the current checkout on a new branch, preserving the existing local Xcode changes and docs. No new worktree was created.
- `UIIsolationTests` replaces the proposed isolated-fixture-only test class; it verifies the hosted app's actual InMemory store and renders MainTabView with the injected container.
- Completed launch save ownership and event-key processing together rather than leave an intermediate constructor-based launch path. The final internal stage seam returns `[String]`, and injected validation failures return `[]` before save fails.
- Event processing uses the record returned by `recordChange`; convenience recorders remain Void because no caller needs their returned identity.
- Published transfer folders use `positions-<UUID>`; uniqueness and two-file publication are preserved without a timestamp naming feature.
- The unused `saveAndGenerateCashFlows` convenience method retains its pre-existing two-phase contract, but now awaits a fresh, rollback-protected generation transaction and propagates errors. Active forms use one atomic save. Do not route new forms through the legacy helper.
- Dormant CashFlowMigration keeps its existing singleton selection and explicit save; it was not activated. Unchanged bond-deletion actions are outside the enumerated write-action migration.

Verification logs are in `/tmp/mybond-complete.log` (42 tests), `/tmp/mybond-final-release.log` (Release), and earlier red-test logs in `/tmp/mybond-*.log`. The rendering fixture is `/tmp/mybond-portfolio-preview.png`. No claim of distribution signing, live quote compatibility, or user-store migration is made.

## Global Constraints

- Keep SwiftUI, Core Data, Swift 5.0, and macOS 15.0.
- Add no dependencies; preserve the existing visual design.
- Export/Import remains current positions only, clearly labeled. It is not a complete backup.
- Daily ETF price history stores the latest quote for that day.
- Preserve existing history during positions import. Do not replay acquisition or sale history for imported positions.
- Preserve nominal-based historical bond invested-capital entries. Realized gain is redemption minus acquisition cost.
- Preserve the current annual coupon schedule and approximate yield-to-maturity formula.
- Do not automatically repair old history, reset databases, or call live endpoints in tests.
- Preserve the existing signing-team, scheme-version, Xcode user-state changes, `.DS_Store`, and `graphify-out/`.
- No commits or pushes unless separately authorized. Commit steps below describe proposed boundaries only.

## Review Focus

- Failed imports/saves must leave persisted data and unrelated unsaved view-context edits intact, with every caller using the app-selected container: Tasks 2 and 3.
- A crash after history save but before checkpoint update must not duplicate an event on retry: Task 6.
- An obsolete header response after ISIN or mode changes must not become saveable: Task 5.
- Empty replacements, duplicate IDs, file changes during confirmation, and transfer failure between two writes must produce explicit outcomes: Task 7.
- Launch/manual refresh overlap and a delayed response after an import changes instrument identity must not overwrite the current instrument: Task 8.

---

## Scope and file map

One plan is appropriate because transaction ownership and test isolation are shared dependencies. Execute in three batches; each task is independently reviewable. Separate subsystem plans would repeat these interfaces.

| Batch | Task | Files and responsibility |
| --- | --- | --- |
| Protect data | 1 | Test plan/scheme/app startup and test fixtures: enable safe hosted tests |
| Protect data | 2 | `PortfolioTransaction.swift`, `PortfolioContainerEnvironment.swift`, persistence, import: isolated save/rollback, selected-container wiring, and frozen preflight payload |
| Protect data | 3 | Recorders/generator and all write callers including launch: one save per action and checkpoint after launch save |
| Correct results | 4 | `PortfolioCalculations.swift`, summary/history, `ETFSale.swift`: signed results and execution-price FIFO |
| Reliability | 5 | `ETFPurchase.swift`, Add ETF: validated values and instrument identity |
| Reliability | 6 | Notifier, `LaunchEventProcessor.swift`, versioned model: retryable, deduplicated events |
| Reliability | 7 | Transfer managers/Codable/validation/main controls: positions scope and complete validation |
| Reliability | 8 | Updater/app/main controls: daily latest quote, coordinated refresh, final verification |

New files stay in the existing `MyBondManager/` and `MyBondManagerTests/` synchronized groups. No repository/service hierarchy or generic validation framework.

## Execution setup and commands

At execution time, use `superpowers:using-git-worktrees` to obtain an isolated checkout. Inspect branch/status first. Carry approved local Xcode configuration deliberately; a new worktree will not copy it automatically. Do not include unrelated changes in any proposed commit.

All commands below run from that checkout. Derived data and cloned packages go under `/tmp`, not into the source tree.

```bash
xcodebuild -project MyBondManager.xcodeproj -scheme MyBondManager \
  -destination 'platform=macOS' -derivedDataPath /tmp/MyBondManager-plan-tests \
  -clonedSourcePackagesDirPath /tmp/MyBondManager-plan-packages \
  CODE_SIGNING_ALLOWED=NO test
```

For focused runs append the exact selectors below to the command. Every task's fail/pass steps use its row. Package resolution needs network access or an existing package cache. Report environmental failures separately from compiler/test failures. If unsigned hosted tests cannot launch on the execution machine, use its authorized signing configuration and report the actual command; do not disable tests to obtain a green result.

| Task | Focused selectors |
| --- | --- |
| 1 | `-only-testing:MyBondManagerTests/UIIsolationTests -only-testing:MyBondManagerTests/LaunchNotifierTests` |
| 2 | `-only-testing:MyBondManagerTests/PortfolioTransactionTests -only-testing:MyBondManagerTests/ImportManagerTests` |
| 3 | `-only-testing:MyBondManagerTests/PortfolioWriteTests -only-testing:MyBondManagerTests/LaunchNotifierTests` |
| 4 | `-only-testing:MyBondManagerTests/PortfolioCalculationsTests -only-testing:MyBondManagerTests/ETFSaleTests` |
| 5 | `-only-testing:MyBondManagerTests/ETFPurchaseTests` |
| 6 | `-only-testing:MyBondManagerTests/LaunchEventProcessorTests -only-testing:MyBondManagerTests/LaunchNotifierTests` |
| 7 | `-only-testing:MyBondManagerTests/PositionsTransferTests` |
| 8 | `-only-testing:MyBondManagerTests/ETFPriceUpdaterTests` |

### Task 1: Enable tests without touching the real portfolio

**Files:** Modify `MyBondManager.xctestplan`, `MyBondManager.xcodeproj/xcshareddata/xcschemes/MyBondManager.xcscheme`, `MyBondManager/MyBondManagerApp.swift`, `MyBondManager/LaunchNotifier.swift`, `MyBondManagerTests/LaunchNotifierTests.swift`; create `MyBondManagerTests/TestPortfolio.swift` and `MyBondManagerTests/UIIsolationTests.swift`.

**Interfaces:** Keep `PersistenceController.init(inMemory: Bool = false)`. Add `LaunchNotifier.init()` with no processing for the hosted test app, and `LaunchNotifier.init(context: NSManagedObjectContext, now: Date = Date(), defaults: UserDefaults = .standard)` before the lifecycle rewrite in Task 6. Test fixture exposes `TestPortfolio.make() throws -> NSPersistentContainer`, `TestPortfolio.bond(in:cost:par:) -> BondEntity`, and `TestPortfolio.holding(in:shares:price:) -> ETFHoldings`.

- [x] **Step 1: Record the test discovery failure.** Run the test command with `-only-testing:MyBondManagerTests/LaunchNotifierTests`. Capture the missing/disabled target failure; a zero-test run does not pass this task.
- [x] **Step 2: Repair discovery and isolate the host.** Set the test-plan target identifier to `098EB4F72DBE982A008CB539`, set `enabled` to `true`, and remove obsolete scheme test references. Add `MYBONDMANAGER_TESTING=1` to test-plan environment variables. Preserve `LastUpgradeVersion` and all signing values.

```swift
// App initialization: assign the stored persistence controller here.
let isTesting = ProcessInfo.processInfo.environment["MYBONDMANAGER_TESTING"] == "1"
    || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
let persistence = isTesting ? PersistenceController(inMemory: true) : .shared
let context = persistence.container.viewContext
let notifier = isTesting ? LaunchNotifier() : LaunchNotifier(context: context)
// Assign the app's stored properties and StateObject from these locals.
// Skip empty-ETF cleanup and startup refresh when isTesting is true.
```

Add a stored `isTesting: Bool` to the app so its `.task` uses `guard !isTesting else { return }`. Inject a unique defaults suite into the existing notifier test; delete only that suite in teardown.

- [x] **Step 3: Add deterministic shared fixtures and an isolation assertion.** Fixture code:

```swift
import CoreData
import XCTest
@testable import MyBondManager

enum TestPortfolio {
    static func make() throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "MyBondManager")
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }
    static func bond(in context: NSManagedObjectContext,
                     cost: Double = 1100, par: Double = 1000) -> BondEntity {
        let bond = BondEntity(context: context)
        bond.id = UUID(); bond.name = "Fixture"; bond.issuer = "Issuer"
        bond.isin = "DE0000000001"; bond.wkn = "TEST01"; bond.depotBank = "Bank"
        bond.initialPrice = cost; bond.parValue = par; bond.couponRate = 0
        bond.yieldToMaturity = 0
        bond.acquisitionDate = ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z")!
        bond.maturityDate = ISO8601DateFormatter().date(from: "2027-01-01T00:00:00Z")!
        return bond
    }
    static func holding(in context: NSManagedObjectContext,
                        shares: Int32 = 10, price: Double = 90) -> ETFHoldings {
        let etf = ETFEntity(context: context)
        etf.id = UUID(); etf.etfName = "ETF fixture"; etf.isin = "DE0000000002"
        etf.wkn = "TEST02"; etf.issuer = "Issuer"; etf.lastPrice = 100
        let holding = ETFHoldings(context: context)
        holding.holdingtoetf = etf; holding.numberOfShares = shares
        holding.acquisitionPrice = price
        holding.acquisitionDate = ISO8601DateFormatter().date(from: "2025-01-01T00:00:00Z")!
        return holding
    }
}
@MainActor
final class UIIsolationTests: XCTestCase {
    func testFixtureUsesOnlyMemory() throws {
        let container = try TestPortfolio.make()
        XCTAssertEqual(container.persistentStoreCoordinator.persistentStores.first?.type,
                       NSInMemoryStoreType)
    }
}
```

- [x] **Step 4: Run discovery and the existing notifier test.** Require nonzero executed tests and zero failures. Confirm the hosted app does not open its normal store or contact ING. Record any baseline failure before changing behavior.
- [x] **Step 5: Review this boundary.** Proposed commit message: `test: enable isolated portfolio tests`. Commit only if authorized.

### Task 2: Make writes isolated and imports all-or-nothing

**Files:** Create `MyBondManager/PortfolioTransaction.swift`, `MyBondManager/PortfolioContainerEnvironment.swift`; modify `MyBondManager/PersistenceController.swift`, `MyBondManager/MyBondManagerApp.swift`, `MyBondManager/CoreDataCodable.swift`, `MyBondManager/ImportManager.swift`, `MyBondManager/MainTabView.swift`; create `MyBondManagerTests/PortfolioTransactionTests.swift` and `MyBondManagerTests/ImportManagerTests.swift`.

**Interfaces:** `PortfolioTransaction.run<T>(in: NSPersistentContainer, changes: @escaping (NSManagedObjectContext) throws -> T) async throws -> T`. Results contain values or permanent object IDs, never managed objects. Add `EnvironmentValues.portfolioContainer: NSPersistentContainer?` with a nil default; app root injects its selected container, and sheet descendants receive it. Add immutable `PositionsPayload` containing `let bonds: [BondCodable]` and `let etfs: [ETFEntityCodable]` in `CoreDataCodable.swift`. `ImportManager.prepare(from: URL) async throws -> PositionsPayload` decodes/validates on a utility queue under security-scoped access. `ImportManager.apply(_ payload: PositionsPayload, into: NSPersistentContainer) async throws` only applies the frozen values through Task 2's transaction. Keep convenience `importAll(from: URL, into: NSPersistentContainer) async throws` for tests/noninteractive callers, delegating to prepare then apply; the interactive caller uses prepare/confirmation/apply.

- [x] **Step 1: Write failure-isolation tests.** Add this test and a success test that checks results through a fresh reader context:

```swift
@MainActor
final class PortfolioTransactionTests: XCTestCase {
    enum Failure: Error { case injected }
    func testFailedOperationPreservesUnrelatedDraftAndStore() async throws {
        let container = try TestPortfolio.make()
        let saved = TestPortfolio.bond(in: container.viewContext)
        try container.viewContext.save()
        saved.name = "Unrelated draft"
        do {
            try await PortfolioTransaction.run(in: container) { context in
                let bonds = try context.fetch(BondEntity.fetchRequest())
                bonds.forEach(context.delete)
                throw Failure.injected
            }
            XCTFail("Expected failure")
        } catch Failure.injected {}
        XCTAssertEqual(saved.name, "Unrelated draft")
        let reader = container.newBackgroundContext()
        let count = try await reader.perform {
            try reader.count(for: BondEntity.fetchRequest())
        }
        XCTAssertEqual(count, 1)
    }
}
```

In `ImportManagerTests`, create a temporary directory with `bonds.json` containing `[]` and `etfs.json` containing `{broken`; seed one saved bond, import, assert throw and fresh-reader bond count equals one. Also test missing file and duplicate UUIDs. Use `FileManager.default.temporaryDirectory` and remove only the test's directory in teardown.

- [x] **Step 2: Run focused classes and observe failure.** Use `PortfolioTransactionTests` and `ImportManagerTests`. Missing helper/API is the initial expected failure; after helper creation the malformed-import regression must fail on the old mutation ordering.
- [x] **Step 3: Implement the shared native transaction primitive.**

```swift
import CoreData

enum PortfolioTransaction {
    static func run<T>(in container: NSPersistentContainer,
                       changes: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        let context = container.newBackgroundContext()
        return try await context.perform {
            do {
                let result = try changes(context)
                if context.hasChanges { try context.save() }
                return result
            } catch {
                context.rollback()
                throw error
            }
        }
    }
}
```

Set `container.viewContext.automaticallyMergesChangesFromParent = true` in production persistence setup. Never capture `bond`, `etf`, or `holding` in this closure: capture `objectID` first and resolve with `try context.existingObject(with:)` on its queue.

Provide the selected container without a default singleton:

```swift
import SwiftUI
import CoreData

private struct PortfolioContainerKey: EnvironmentKey {
    static let defaultValue: NSPersistentContainer? = nil
}
extension EnvironmentValues {
    var portfolioContainer: NSPersistentContainer? {
        get { self[PortfolioContainerKey.self] }
        set { self[PortfolioContainerKey.self] = newValue }
    }
}
// App root and each explicitly constructed sheet:
// .environment(\.portfolioContainer, persistenceController.container)
```

Views read `@Environment(\.portfolioContainer) private var portfolioContainer`. If missing, show `Portfolio store is unavailable.` and perform no writes; never substitute `.shared`. The app remains the sole production selector of `PersistenceController.shared`. Test views receive their fixture container explicitly.

Define and validate the frozen payload before either application loop:

```swift
public struct PositionsPayload {
    public let bonds: [BondCodable]
    public let etfs: [ETFEntityCodable]
}
// importAll convenience body:
let payload = try await prepare(from: folderURL)
try await apply(payload, into: container)
```

Refactor the private import loops to consume decoded arrays, keeping existing field assignment and replacement behavior. Decode/validate in prepare's utility work, then apply on the fresh operation context queue, outside the view context. Require positive finite bond nominal/cost, finite nonnegative coupon, acquisition not after maturity, positive finite ETF holding prices, positive shares, finite positive price-history quotes, recognized cash-flow natures, finite cash-flow amounts, and child `etfId` equal to its parent UUID. Empty arrays remain valid replacements. Transfer history is untouched. MainTabView retains `@State private var pendingImport: PositionsPayload?` and only calls apply after replacement confirmation; clear it on cancel or successful application. Preparation errors cannot open a confirmation or mutate positions. Task 7 adds the complete scope/count copy.

- [x] **Step 4: Add a actual save-failure test.** Stage a `HistoricalValuation` with required `date` missing so Core Data validation rejects save. Assert no staged bond deletions or history rows persist. Verify a subsequent successful operation still works. Add a merge test: observe view-context `NSManagedObjectContextObjectsDidChange`, insert a cash flow through the writer, and assert the already loaded bond relationship updates before fulfilling the expectation.
- [x] **Step 5: Run both classes and review.** Proposed commit: `fix: isolate portfolio writes and preflight imports`.

### Task 3: Save positions, cash flows, and history together

**Files:** Modify `MyBondManager/HistoricalDataRecorder.swift`, `MyBondManager/CashFlowGenerator.swift`, `MyBondManager/AddBondView.swift`, `MyBondManager/EditBondView.swift`, `MyBondManager/AddETFView.swift`, `MyBondManager/ETFSellView.swift`, `MyBondManager/MainTabView.swift`, `MyBondManager/PersistenceController.swift`, `MyBondManager/CashFlowMigration.swift`, `MyBondManager/LaunchNotifier.swift`, `MyBondManager/MyBondManagerApp.swift`, `MyBondManagerTests/LaunchNotifierTests.swift`; create `MyBondManagerTests/PortfolioWriteTests.swift`.

**Interfaces:** Preserve existing recorder/generator argument signatures, but they only stage objects. Transaction ownership comes from Task 2 and all UI actions consume its injected container. Move launch I/O out of the constructor now: `@MainActor LaunchNotifier.init(defaults: UserDefaults = .standard)` and `processLaunch(in: NSPersistentContainer, now: Date = Date(), stage: ((NSManagedObjectContext, Date, Date) throws -> String?)? = nil) async`. Private `LaunchNotifier.stageLaunch(context: NSManagedObjectContext, since: Date, until: Date) throws -> String?` stages current launch events and returns alert text. The optional stage closure is an internal test seam executed inside the real transaction; production nil uses stageLaunch. Task 6 replaces this staging function with the persisted-flow processor and adds stable event keys. Update every caller, including dormant migration/save helpers, in this same task; do not activate dormant features.

- [x] **Step 1: Pin the no-hidden-save contract.**

```swift
@MainActor
final class PortfolioWriteTests: XCTestCase {
    func testRecorderAndGeneratorDoNotSaveTheirCallerContext() throws {
        let container = try TestPortfolio.make()
        let context = container.viewContext
        let bond = TestPortfolio.bond(in: context)
        try CashFlowGenerator(context: context).regenerateCashFlows(for: bond)
        try HistoricalDataRecorder.recordBondAcquisition(bond: bond, context: context)
        XCTAssertTrue(context.hasChanges)
        let reader = container.newBackgroundContext()
        let persisted = try reader.performAndWait {
            try reader.count(for: BondEntity.fetchRequest())
        }
        XCTAssertEqual(persisted, 0)
    }
}
```

- [x] **Step 2: Run `PortfolioWriteTests` and observe failure.** Existing helpers save, so `hasChanges` or persisted count must expose that behavior.
- [x] **Step 3: Remove nested saves and move callers into transactions.** Delete `try context.save()` from `HistoricalDataRecorder.recordChange` and the final save block from `CashFlowGenerator.regenerateCashFlows`. Keep their thrown fetch/validation errors propagated. Adapt the add/edit/FIFO/recalculate paths to call Task 2's helper. Copy validated form primitives before the background closure. Only set success or dismiss after `try await` returns.

```swift
let bondID = bond.objectID
guard let container = portfolioContainer else {
    errorMessage = "Portfolio store is unavailable."
    return
}
do {
    try await PortfolioTransaction.run(in: container) { context in
        guard let stored = try context.existingObject(with: bondID) as? BondEntity else {
            throw CocoaError(.validationMissingMandatoryProperty)
        }
        // Assign the captured, validated form values before generating flows.
        try CashFlowGenerator(context: context).regenerateCashFlows(for: stored)
    }
    dismiss()
} catch {
    errorMessage = "Could not save bond: \(error.localizedDescription)"
}
```

Add `@State private var errorMessage: String?` to edit/purchase forms and render it using the existing red error-text convention. Reject parse failures rather than falling back to old bond values. Disable Save while its operation is running. Preserve literal zero coupons. Keep cancellation free of managed-object mutations.

Launch ownership must ship in this task, not wait for Task 6. Move the existing event-building logic to `stageLaunch`, replacing `try?` fetches and swallowed history errors with propagated throws. In `processLaunch`, snapshot the interval, call `PortfolioTransaction.run(in: container)` with `stage ?? Self.stageLaunch`, and only then set `lastLaunchDate` and the alert. If the transaction throws, report it and leave the checkpoint untouched. App startup awaits this method using its selected container; tests await it with isolated defaults. Preserve the existing schedule until Task 6's explicit eligibility/deduplication work. The intermediate implementation still lacks crash-replay deduplication; Task 6 closes that existing gap before final release.

- [x] **Step 4: Verify real operation rollback and caller ownership.** Test a staged bond+cashflow+acquisition record followed by an injected throw; fresh readers must find zero new rows of all three entities. Test two FIFO lots with the final history record made invalid; all original shares and zero sale history must remain. Count context-save notifications to require exactly one save on successful acquisition, sale, and batch recalculation. At this task boundary, launch processing must persist coupon/maturity history before checkpoint advancement; inject an invalid staged history record and verify the checkpoint stays unchanged. Exercise an actual view action with an injected in-memory container and observe save notifications to assert the saving context's coordinator is that fixture's coordinator. Source-scan migrated view/updater callers to require no singleton reference; no test may initialize the production singleton.
- [x] **Step 5: Run `PortfolioWriteTests`, transaction tests, and import tests.** Search all `recordBond`, `recordETF`, `recordChange`, and `regenerateCashFlows` callers; each must reach one owning save. Proposed commit: `fix: commit portfolio actions as single transactions`.

### Task 4: Correct signed returns and execution-price FIFO sales

**Files:** Create `MyBondManager/PortfolioCalculations.swift`, `MyBondManager/ETFSale.swift`; modify `MyBondManager/PortfolioSummaryView.swift`, `MyBondManager/HistoricalDataRecorder.swift`, `MyBondManager/ETFSellView.swift`; create `MyBondManagerTests/PortfolioCalculationsTests.swift`, `MyBondManagerTests/ETFSaleTests.swift`.

**Interfaces:** `PortfolioCalculations.expectedReturn(interest: Double, gains: Double, signedLosses: Double) -> Double`. `ETFSale.stage(etf: ETFEntity, shares: Int32, executionPrice: Double, date: Date, context: NSManagedObjectContext) throws -> Void` consumes Task 3's staging recorder and does not save. Keep existing gain recorder signature.

- [x] **Step 1: Write the financial regression.**

```swift
final class PortfolioCalculationsTests: XCTestCase {
    func testSignedPremiumLossReducesReturn() {
        XCTAssertEqual(PortfolioCalculations.expectedReturn(
            interest: 0, gains: 0, signedLosses: -100), -100)
    }
    @MainActor func testMaturityGainUsesPurchaseCost() throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext, cost: 900)
        try HistoricalDataRecorder.recordBondMaturity(
            bond: bond, redemptionAmount: 1000, context: container.viewContext)
        let record = try XCTUnwrap(container.viewContext.fetch(
            HistoricalValuation.fetchRequest()).first)
        XCTAssertEqual(record.capitalGains.doubleValue, 100)
    }
}
```

For `ETFSaleTests`, seed two lots in one ETF: 5 shares at 80 acquired January 1, 10 at 90 acquired February 1. Sell 8 at execution price 110 while `lastPrice` is 100. Assert the first lot is deleted, second retains 7 shares, invested delta is -670, gain is 210, and recorded date equals the supplied date. Test zero, negative, NaN, infinity, and oversell inputs leave the context unchanged.

- [x] **Step 2: Run both classes and observe the old failures.** A discount maturity currently produces zero; the FIFO operation does not accept an execution price.
- [x] **Step 3: Apply minimal calculations.**

```swift
enum PortfolioCalculations {
    static func expectedReturn(interest: Double, gains: Double,
                               signedLosses: Double) -> Double {
        interest + gains + signedLosses
    }
}
// HistoricalDataRecorder.recordBondMaturity:
let gainDelta = redemptionAmount - bond.initialPrice
```

Wire the summary to the tested helper. Move the existing FIFO loop to `ETFSale.stage`; validate `shares > 0`, `executionPrice.isFinite && executionPrice > 0`, and availability before mutation. Reject any nonpositive legacy lot instead of letting it distort FIFO arithmetic. Resolve equal-date ties deterministically by permanent object-ID URI. Pass the execution price to each staged history record; propagate every error.

Add a `salePrice` text field and restore the existing sale-date picker. Require `date <= Date()` and enough shares acquired by that date; exclude later acquisitions from FIFO eligibility. Keep same-day acquisitions eligible using calendar-day comparison. No fee or tax features. Invoke `stage` inside Task 2's transaction.

- [x] **Step 4: Add premium and date-edge tests.** Maturity cost 1100/redemption 1000 yields -100; zero-coupon and mixed gains/losses are correct. A sale before acquisition throws without mutation. Assert current `lastPrice` never influences realized gain.
- [x] **Step 5: Run both classes and transaction tests.** Proposed commit: `fix: correct portfolio returns and ETF sale accounting`.

### Task 5: Validate ETF purchases and bind fetched identity

**Files:** Create `MyBondManager/ETFPurchase.swift`; modify `MyBondManager/AddETFView.swift`; create `MyBondManagerTests/ETFPurchaseTests.swift`.

**Interfaces:** `ETFPurchase.normalizedISIN(_ value: String) -> String`; `ETFPurchase.validate(price: Double, shares: Int32) throws`; `ETFPurchase.acceptsHeader(requestedISIN: String, currentISIN: String, isNewMode: Bool, requestedID: UUID, activeID: UUID?) -> Bool`; `ETFPurchase.stage(isin: String, header: InstrumentHeaderScraper.ETFInstrumentHeader?, existingID: NSManagedObjectID?, date: Date, price: Double, shares: Int32, context: NSManagedObjectContext) throws` stages a holding and acquisition history, without saving.

- [x] **Step 1: Write identity and value tests.**

```swift
final class ETFPurchaseTests: XCTestCase {
    func testRejectsInvalidValues() {
        for price in [0.0, -1.0, .infinity, .nan] {
            XCTAssertThrowsError(try ETFPurchase.validate(price: price, shares: 1))
        }
        XCTAssertThrowsError(try ETFPurchase.validate(price: 90, shares: 0))
        XCTAssertThrowsError(try ETFPurchase.validate(price: 90, shares: -1))
        XCTAssertNoThrow(try ETFPurchase.validate(price: 90, shares: 1))
    }
    func testRejectsObsoleteHeaderResponse() {
        let requestID = UUID()
        XCTAssertFalse(ETFPurchase.acceptsHeader(
            requestedISIN: "A", currentISIN: "B", isNewMode: true,
            requestedID: requestID, activeID: requestID))
        XCTAssertFalse(ETFPurchase.acceptsHeader(
            requestedISIN: "A", currentISIN: "A", isNewMode: false,
            requestedID: requestID, activeID: requestID))
        XCTAssertFalse(ETFPurchase.acceptsHeader(
            requestedISIN: "A", currentISIN: "A", isNewMode: true,
            requestedID: requestID, activeID: UUID()))
        XCTAssertEqual(ETFPurchase.normalizedISIN(" de0000000002 "), "DE0000000002")
    }
}
```

- [x] **Step 2: Run `ETFPurchaseTests` and observe failure.** Add a persistence regression: selected ETF B has quote 80; supply a header A with quote 500 and B's existing ID; stage/save must retain B's quote 80.
- [x] **Step 3: Implement the predicates and use them in the real UI.**

```swift
static func normalizedISIN(_ value: String) -> String {
    value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
}
static func acceptsHeader(requestedISIN: String, currentISIN: String,
                          isNewMode: Bool, requestedID: UUID,
                          activeID: UUID?) -> Bool {
    isNewMode && requestedID == activeID
        && normalizedISIN(requestedISIN) == normalizedISIN(currentISIN)
}
```

Capture the normalized ISIN and a request UUID before awaiting. Store `fetchedISIN` with the response only when the UUID, mode, and current normalized input still match. On ISIN/mode changes clear the header and invalidate the request UUID. Save must recheck identity rather than trust button disabling. Existing mode ignores fetched-header prices entirely.

`stage` validates values before insertion, resolves an existing ID on its context, or matches the normalized input against normalized stored ISINs before creating a new ETF. At personal-portfolio scale, fetch ETFs once and filter with the same normalizer; an exact uppercased predicate alone misses legacy padded/lowercase values. Reuse a single match without rewriting its stored identifier. If multiple normalized matches exist, throw an explicit duplicate-instrument error; do not select an arbitrary row or migrate them. Use `Int32(numberOfShares)` directly, avoiding the current forced `Int` conversion. Record the holding and acquisition in the same transaction.

- [x] **Step 4: Test out-of-order response and reuse.** Feed two completed headers in reverse request order through the UUID acceptance check; only the active request can update state. Repeated normalized ISIN purchases create one ETF with two holdings. Seed a legacy `" de0000000002 "` identifier, purchase `"DE0000000002"`, and assert one ETF, two holdings, and the original identifier unchanged. Seed both padded/lowercase and canonical rows, then assert staging throws without creating holdings/history. Failure after staging leaves no new ETF/holding/history. The form keeps inputs and displays the error.
- [x] **Step 5: Run purchase and write tests.** Proposed commit: `fix: validate ETF purchases and preserve instrument identity`.

### Task 6: Make launch history retryable and deduplicated

**Files:** Create `MyBondManager/LaunchEventProcessor.swift`; modify `MyBondManager/LaunchNotifier.swift`, `MyBondManager/MyBondManagerApp.swift`, `HistoricalValuation+CoreDataClassProperties.swift`; create `MyBondManager/MyBondManager.xcdatamodeld/MyBondManagerV2.xcdatamodel/contents`, `MyBondManager/MyBondManager.xcdatamodeld/.xccurrentversion`; create `MyBondManagerTests/LaunchEventProcessorTests.swift`, modify `MyBondManagerTests/LaunchNotifierTests.swift`.

**Interfaces:** Add optional `HistoricalValuation.eventKey: String?`. `LaunchEventProcessor.stage(context: NSManagedObjectContext, since: Date, until: Date) throws -> [String]` returns alert descriptions and stages unique records. Retain Task 3's `@MainActor LaunchNotifier.init(defaults:)` and the production `processLaunch(in:now:)` call shape; its private stageLaunch adapter calls this processor and joins descriptions into a String. Keep Task 3's stage test seam, replacing the duplicate transaction-operation seam originally proposed for this task. It consumes Task 2's transaction and Task 3's staging recorder. App startup already awaits processing before price refresh. Tests retain isolated defaults and awaited processing.

- [x] **Step 1: Test retry across checkpoint failure.**

```swift
@MainActor
final class LaunchEventProcessorTests: XCTestCase {
    func testCommittedEventIsNotDuplicatedWhenIntervalReplays() async throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext)
        bond.couponRate = 5
        try CashFlowGenerator(context: container.viewContext).regenerateCashFlows(for: bond)
        try container.viewContext.save()
        let since = ISO8601DateFormatter().date(from: "2025-12-31T00:00:00Z")!
        let until = ISO8601DateFormatter().date(from: "2026-01-02T00:00:00Z")!
        for _ in 0..<2 {
            _ = try await PortfolioTransaction.run(in: container) { context in
                try LaunchEventProcessor.stage(context: context, since: since, until: until)
            }
        }
        let reader = container.newBackgroundContext()
        let count = try await reader.perform {
            try reader.count(for: HistoricalValuation.fetchRequest())
        }
        XCTAssertEqual(count, 1)
    }
}
```

- [x] **Step 2: Run launch tests and observe failure.** Retain Task 3's save-failure/checkpoint regression and stage seam. For a real validation failure, inject a stage closure that creates a HistoricalValuation with missing mandatory date and returns nil; saving the real transaction must fail and leave `lastLaunchDate` unchanged. Add replay tests for this task's new event-key behavior. Do not introduce another transaction closure or protocol.
- [x] **Step 3: Add a lightweight model version and event identity.** Copy the original model into V2, adding only optional String `eventKey` to history; retain the original model unchanged. Select V2 as current and explicitly allow inferred lightweight migration on store descriptions. Key format:

```swift
let key = "\(bond.id.uuidString)|\(nature)|\(Int(eventDate.timeIntervalSince1970))"
let request = HistoricalValuation.fetchRequest()
request.predicate = NSPredicate(format: "eventKey == %@", key)
request.fetchLimit = 1
if try context.count(for: request) == 0 {
    // Stage the matching coupon/maturity through HistoricalDataRecorder.
    // Set eventKey on the newly inserted HistoricalValuation before saving.
}
```

Have `recordChange` return its inserted `HistoricalValuation` (mark `@discardableResult`) so the processor can set `eventKey`; keep convenience methods' argument lists, return the record from them too. Update any declared return annotations accordingly. No scans based on display name or bank, which are mutable.

Fetch persisted interest flows and check `(since, until]`, acquisition day, and maturity day. Use identical interval bounds for maturity records. Reject a future checkpoint with a visible error rather than building an invalid year range. Advance defaults only after the transaction succeeds. On failure show an error, leave checkpoint unchanged, and retry on the next launch. Serialize launch processing with an in-flight guard. Existing seven-day first-run behavior remains.

- [x] **Step 4: Verify boundary and migration cases.** Test coupon before acquisition is excluded; an event exactly at `since` is excluded and at `until` included; final coupon and maturity both process once; zero coupon creates no misleading payment alert. Create a disposable SQLite store using the original model, seed one historical row, open through V2, and assert its original fields survive with nil eventKey. Store path must be inside the test's temporary directory. Existing history is not retroactively re-keyed.
- [x] **Step 5: Run launch, transaction, and write tests.** Proposed commit: `fix: make launch history processing retryable`.

### Task 7: Make positions transfer honest and reliable

**Files:** Modify `MyBondManager/CoreDataCodable.swift`, `MyBondManager/ExportManager.swift`, `MyBondManager/ImportManager.swift`, `MyBondManager/ExportValidationView.swift`, `MyBondManager/MainTabView.swift`; create `MyBondManager/PositionsTransferValidation.swift`, `MyBondManagerTests/PositionsTransferTests.swift`; document scope in `docs/positions-transfer.md`.

**Interfaces:** `ExportManager.exportAll(to: URL, from: NSManagedObjectContext) async throws -> URL` returns the published transfer subdirectory. `PositionsTransferValidation.issues(bonds: [BondCodable], etfs: [ETFEntityCodable], context: NSManagedObjectContext) throws -> [String]` runs on the supplied context's queue. Task 2's `prepare(from:)` accepts the returned folder and `apply(_:into:)` consumes the frozen payload. Codable mirrors become `Equatable`; decimal historical rows stay outside this format.

- [x] **Step 1: Write round-trip and scope tests.**

```swift
@MainActor
final class PositionsTransferTests: XCTestCase {
    func testTransferExcludesAndPreservesDestinationHistory() async throws {
        let source = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: source.viewContext, cost: 900)
        try CashFlowGenerator(context: source.viewContext).regenerateCashFlows(for: bond)
        try source.viewContext.save()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try await ExportManager().exportAll(to: root, from: source.viewContext)
        let target = try TestPortfolio.make()
        let old = TestPortfolio.bond(in: target.viewContext)
        try HistoricalDataRecorder.recordBondAcquisition(bond: old, context: target.viewContext)
        try target.viewContext.save()
        try await ImportManager().importAll(from: folder, into: target)
        let reader = target.newBackgroundContext()
        let count = try await reader.perform {
            try reader.count(for: HistoricalValuation.fetchRequest())
        }
        XCTAssertEqual(count, 1)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)),
                       Set(["bonds.json", "etfs.json"]))
    }
}
```

- [x] **Step 2: Run transfer tests and observe failure.** Add changed-price/same-name and missing-cashflow validation cases: both must produce issues, unlike the old name-only comparison. Add duplicate UUID cases; they must report errors without a dictionary trap.
- [x] **Step 3: Collect, stage, then publish the complete pair.** Fetch/map both datasets using `try await context.perform`. Pass only Codable values out of that closure; write them on a utility queue. Within the selected directory create hidden `.positions-UUID`, write both JSON files, then rename to `positions-YYYYMMDD-HHmmss-UUID` on the same filesystem. If encoding/write/rename fails, remove only that operation's staging directory and throw; previously published directories remain intact. Acquire security-scoped access for the entire operation and release in `defer`.

Do not change the JSON schemas or rely on exported Core Data URI identifiers for restored object identity. Compare ETF price/holding content by sorted value tuples, with IDs/parent linkage validated separately. Compare all bond fields and all nested cash flows. Normalize dates to whole Unix seconds before comparison because `.iso8601` encoding drops fractional seconds. Compare nested collections as multisets so missing duplicate rows are detected. Financial numeric values use exact JSON round-trip equality; do not round away discrepancies.

Update copy to `Export Positions`, `Import Positions`, and `Positions match export`. Before replacement show: `This replaces all current bond and ETF positions. Existing history is kept; this transfer does not restore history.` Include bond/ETF counts from `pendingImport`, including zero counts, in confirmation. Do not mutate while confirmation is pending. On confirm pass that exact value to `apply`; do not call URL-based `importAll` or reread either file. Returned export folder feeds validation. Add a loading state instead of initially showing contradictory discrepancy/no-issues messages.

- [x] **Step 4: Verify failure publication, frozen confirmation, and legacy compatibility.** Add a test-only internal write closure parameter (production default `Data.write`) to fail the second write, then assert no new published directory and an older directory unchanged. Prepare one-bond/two-ETF files, replace both files with empty arrays while confirmation is open, confirm, and assert the original prepared one-bond/two-ETF payload is applied. Repeat with cancellation and assert no positions change. Import the old two-file format directly from a fixture temporary folder. Empty arrays delete positions only after confirmation; missing one file causes no mutation. Preserve unsaved view-context edits through failed import/export.
- [x] **Step 5: Run transfer/import/transaction tests.** Document file names, replacement scope, history exclusion, and returned subfolder in `docs/positions-transfer.md`. Proposed commit: `fix: make current-position transfers consistent`.

### Task 8: Coordinate refresh and keep each day's latest quote

**Files:** Modify `MyBondManager/ETFPriceUpdater.swift`, `MyBondManager/MyBondManagerApp.swift`, `MyBondManager/MainTabView.swift`; create `MyBondManagerTests/ETFPriceUpdaterTests.swift`.

**Interfaces:** Keep `refreshAllPrices() async throws`. Make the existing `@MainActor ETFPriceUpdater` an `ObservableObject` with `@Published private(set) var isRefreshing = false`. Replace its context-only initializer with `init(container: NSPersistentContainer, scraper: InstrumentHeaderScraper = InstrumentHeaderScraper(), fetchPrice: ((String) async throws -> Double)? = nil, now: @escaping () -> Date = Date.init)`. The updater uses that container's view context for queued reads and Task 2's helper for writes; it never obtains `.shared`. Production uses the existing scraper. One app-owned `@StateObject` updater receives the app-selected container and is injected into `MainTabView` through `.environmentObject`; both launch and button use it. No new networking protocol/service.

- [x] **Step 1: Write deterministic quote-history regression.**

```swift
@MainActor
final class ETFPriceUpdaterTests: XCTestCase {
    func testDailyRecordKeepsLatestQuote() async throws {
        let container = try TestPortfolio.make()
        let holding = TestPortfolio.holding(in: container.viewContext)
        try container.viewContext.save()
        let etf = holding.holdingtoetf
        let etfID = etf.objectID
        var quotes = [100.0, 110.0, 120.0]
        let updater = ETFPriceUpdater(container: container,
            fetchPrice: { _ in quotes.removeFirst() })
        for _ in 0..<3 { try await updater.refreshAllPrices() }
        let reader = container.newBackgroundContext()
        let prices = try await reader.perform {
            try reader.fetch(ETFPrice.fetchRequest()).map { $0.price }
        }
        XCTAssertEqual(prices.count, 1)
        XCTAssertEqual(prices[0], 120)
        let persistedLastPrice = try await reader.perform {
            let stored = try XCTUnwrap(reader.existingObject(with: etfID) as? ETFEntity)
            return stored.lastPrice
        }
        XCTAssertEqual(persistedLastPrice, 120)
    }
}
```

- [x] **Step 2: Run `ETFPriceUpdaterTests` and observe failure.** The old averaging code produces 112.5 for the final record.
- [x] **Step 3: Replace averaging and share the running guard.**

```swift
guard !isRefreshing else { return }
isRefreshing = true
defer { isRefreshing = false }
// After a positive, finite quote arrives, on the context's own queue:
let keeper = existing.first ?? ETFPrice(context: context)
keeper.etfPriceHistory = etf
keeper.price = newPrice
keeper.datePrice = now()
existing.dropFirst().forEach(context.delete)
etf.lastPrice = newPrice
```

Set the quote timestamp once for each actual observation and derive day bounds from it, including midnight rollover. Preserve sequential fetching at personal-portfolio scale. Disable Refresh using `updater.isRefreshing`. Surface failed ISINs in manual and startup alerts; do not swallow startup errors. A quote failure must leave its old quote/history unchanged while successful instruments may update. Treat save failures separately and avoid saving unrelated view-context draft edits: stage updates in a fresh operation context via Task 2, resolving captured permanent ETF IDs there, then merge results into views.

Capture `(objectID, normalizedRequestedISIN)` before each request. In the final write context, verify the object still exists and normalize its current ISIN with Task 5's function. If deleted, or if its normalized ISIN changed during import, skip that response and include `Instrument changed during refresh; refresh again.` with the requested ISIN in the per-instrument errors. Do not create price rows or change the current quote for skipped responses. Fetch the object in the fresh context at write time, not before the network suspension. Valid responses for other instruments can still be saved.

- [x] **Step 4: Verify overlap, intervening import, and failure behavior.** Use an async continuation to suspend the injected fetch. Start a second call while the first is suspended; assert only one fetch starts and the UI remains busy until it finishes. While a quote for A is suspended, import the same ETF UUID with ISIN B and quote 80, then complete A's quote at 500; assert B remains at 80 with no A price row and a visible per-instrument error. Repeat with import deleting A; assert no resurrection or orphan price row. Test a failed quote preserves the old price, NaN/zero quotes are rejected, pre-existing daily duplicates collapse to one latest row, a midnight observation belongs to the correct day, and a save failure rolls back that refresh without committing an unrelated draft. Use the initializer's `now` closure for date-boundary tests. Verify stored values through a fresh reader; separately await the view-context change notification before asserting an already loaded ETF's `lastPrice` has merged.
- [x] **Step 5: Run the entire suite and Release build.**

```bash
xcodebuild -project MyBondManager.xcodeproj -scheme MyBondManager \
  -destination 'platform=macOS' -derivedDataPath /tmp/MyBondManager-plan-tests \
  -clonedSourcePackagesDirPath /tmp/MyBondManager-plan-packages \
  CODE_SIGNING_ALLOWED=NO test
xcodebuild -project MyBondManager.xcodeproj -scheme MyBondManager \
  -configuration Release -destination 'platform=macOS' \
  -derivedDataPath /tmp/MyBondManager-plan-release \
  -clonedSourcePackagesDirPath /tmp/MyBondManager-plan-packages \
  CODE_SIGNING_ALLOWED=NO build
git diff --check
git status --short
```

Require nonzero test execution and inspect failures rather than repeating commands without a change. Use a disposable store and stubbed quotes for manual checks: error text, no premature dismissal, replacement confirmation, latest history entry, and immediate background-merge updates. Do not point the app at the user's real store. Proposed commit: `fix: coordinate ETF refresh and store daily latest quotes`.

## Review and handoff

- [x] Review the complete change with `superpowers:requesting-code-review`, checking this spec, transaction callers, migration, tests, and UI scope copy.
- [x] Resolve concrete findings, rerun only affected checks, then confirm the whole suite if behavior changed.
- [x] Report source inspection, tests, Release build, migration test, manual checks, and live-data verification separately. Live portfolio/database and endpoint verification are outside this plan.
- [x] Leave all unrelated initial changes untouched; provide exact changed files and remaining limits. Do not commit or push without authorization.

## Plan self-review record

- Spec coverage: saved-data protection (Tasks 2-3); financial results (Task 4); identity/value checks (Task 5); retryable launch history (Task 6); positions-only scope and validation (Task 7); coordinated latest-price refresh (Task 8); isolated test wiring (Task 1).
- Five review-focus conditions each have an explicit failure test in their owning task.
- Interfaces are defined before use. Task 3 replaces Task 1's temporary launch initializer seam and owns saves/checkpoint advancement before recorder saves are removed. Task 6 adds event identity and persisted-flow eligibility without a temporary persistence regression.
- Complete backup and arithmetic averaging are excluded by the user's choices. Dormant cleanup and old-history repair remain excluded rather than silently added to implementation.
- This file is an implementation proposal, not evidence that its tests compile or pass. No application code was changed while writing it.

## Received-review disposition (2026-10-14)

All five findings were verified against the current source before changing this plan.

1. Launch save ownership: accepted; moved into Task 3 with checkpoint failure tests, leaving replay deduplication in Task 6.
2. Selected-container isolation: accepted; Task 2 provides a nil-default environment dependency, Task 3 uses it, Task 8 requires an explicit container, and caller-level isolation is tested.
3. Refresh/import identity race: accepted; Task 8 rechecks normalized ISIN inside the fresh write context and tests changed/deleted instruments.
4. Legacy ISIN matching: accepted; Task 5 normalizes both sides and tests one matching legacy row and ambiguous normalized duplicates without rewriting either.
5. Confirmation/data mismatch: accepted; Task 2 prepares a frozen immutable payload, Task 7 confirms/applies that payload, and tests file changes/cancellation.

The additional merge-test recommendation is accepted: persistence assertions use a fresh reader and UI assertions wait for a merge notification. No production changes or execution approval are implied by these documentation corrections.
