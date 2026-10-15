import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class LaunchEventProcessorTests: XCTestCase {
    func testReplayingIntervalDoesNotDuplicateHistory() async throws {
        let container = try TestPortfolio.make()
        var terms = try BondTermsFixtures.fixed(); terms.couponRate = 5
        _ = try TestPortfolio.readyBond(in: container.viewContext, terms: terms,
            now: TestPortfolio.date("2026-02-03T12:00:00Z"))
        try container.viewContext.save()
        let suite = "LaunchReplay." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        for _ in 0..<2 {
            defaults.set(TestPortfolio.date("2026-07-14T00:00:00Z"), forKey: "lastLaunchDate")
            let notifier = LaunchNotifier(defaults: defaults)
            await notifier.processLaunch(in: container, now: TestPortfolio.date("2026-07-16T00:00:00Z"))
        }
        let reader = container.newBackgroundContext()
        let count = try await reader.perform { try reader.count(for: HistoricalValuation.fetchRequest()) }
        XCTAssertEqual(count, 1)
    }
    func testFailedSaveDoesNotAdvanceCheckpoint() async throws {
        let container = try TestPortfolio.make()
        let suite = "LaunchFailure." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let since = TestPortfolio.date("2026-01-01T00:00:00Z")
        defaults.set(since, forKey: "lastLaunchDate")
        let notifier = LaunchNotifier(defaults: defaults)
        await notifier.processLaunch(in: container,
            now: TestPortfolio.date("2026-01-02T00:00:00Z"), stage: { context, _, _ in
                let row = HistoricalValuation(context: context)
                row.id = UUID(); row.assetType = "Bond"
                row.investedCapital = 0; row.capitalGains = 0
                return []
            })
        XCTAssertEqual(defaults.object(forKey: "lastLaunchDate") as? Date, since)
        XCTAssertNotNil(notifier.alertMessage)
        let reader = container.newBackgroundContext()
        let count = try await reader.perform { try reader.count(for: HistoricalValuation.fetchRequest()) }
        XCTAssertEqual(count, 0)
    }
    func testCouponBeforeAcquisitionIsExcludedAndBoundariesAreExclusiveInclusive() throws {
        let container = try TestPortfolio.make()
        let context = container.viewContext
        let bond = TestPortfolio.bond(in: context)
        bond.acquisitionDate = TestPortfolio.date("2026-05-01T00:00:00Z")
        var terms = try BondTermsFixtures.fixed(frequency: 4, next: "2026-04-15")
        let approval = TestPortfolio.date("2026-05-02T12:00:00Z"); terms.approvedAt = approval
        let preview = try BondSchedule.preview(trade: BondTermsStore.trade(bond), terms: terms, from: MarketDay(date: approval))
        try BondTermsStore.replaceProjections(for: bond, terms: terms, preview: preview, now: approval,
            acquisitionDay: MarketDay("2026-05-01"), legacyDateZone: "Europe/Berlin", context: context)
        XCTAssertTrue(try LaunchEventProcessor.stage(context: context,
            since: MarketDay("2026-04-14").instant, until: MarketDay("2026-04-16").instant).isEmpty)
        let payment = try MarketDay("2026-07-15").instant
        XCTAssertEqual(try LaunchEventProcessor.stage(context: context,
            since: MarketDay("2026-07-14").instant, until: payment).count, 1)
        XCTAssertTrue(try LaunchEventProcessor.stage(context: context, since: payment,
            until: MarketDay("2026-07-16").instant).isEmpty)
        XCTAssertEqual(try context.fetch(HistoricalValuation.fetchRequest()).first?.date, payment)
    }

    func testFinalCouponAndMaturityAreRecordedOnce() async throws {
        let container = try TestPortfolio.make()
        var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2027-01-01", next: "2027-01-01")
        terms.accrualStart = try MarketDay("2026-01-01"); terms.couponRate = 5
        _ = try TestPortfolio.readyBond(in: container.viewContext, terms: terms,
            now: TestPortfolio.date("2026-02-03T12:00:00Z"))
        try container.viewContext.save()
        let since = TestPortfolio.date("2026-12-31T00:00:00Z")
        let until = TestPortfolio.date("2027-01-05T00:00:00Z")
        let first = try await PortfolioTransaction.run(in: container) { context in
            try LaunchEventProcessor.stage(context: context, since: since, until: until)
        }
        let replay = try await PortfolioTransaction.run(in: container) { context in
            try LaunchEventProcessor.stage(context: context, since: since, until: until)
        }
        XCTAssertEqual(first.count, 2); XCTAssertTrue(replay.isEmpty)
        let reader = container.newBackgroundContext()
        let values = try await reader.perform {
            let rows = try reader.fetch(HistoricalValuation.fetchRequest())
            return (rows.count, rows.reduce(0.0) { $0 + ($1.interestReceived?.doubleValue ?? 0) },
                    rows.reduce(0.0) { $0 + $1.capitalGains.doubleValue })
        }
        XCTAssertEqual(values.0, 2); XCTAssertEqual(values.1, 50); XCTAssertEqual(values.2, 100)
    }

    func testZeroCouponDoesNotProducePaymentHistory() throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext)
        try CashFlowGenerator(context: container.viewContext).regenerateCashFlows(for: bond)
        let messages = try LaunchEventProcessor.stage(context: container.viewContext,
            since: TestPortfolio.date("2025-12-31T00:00:00Z"),
            until: TestPortfolio.date("2026-01-02T00:00:00Z"))
        XCTAssertTrue(messages.isEmpty)
        XCTAssertEqual(try container.viewContext.count(for: HistoricalValuation.fetchRequest()), 0)
    }
    func testFutureCheckpointIsKeptAndReported() async throws {
        let container = try TestPortfolio.make()
        let suite = "FutureCheckpoint." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let future = TestPortfolio.date("2026-01-03T00:00:00Z")
        defaults.set(future, forKey: "lastLaunchDate")
        let notifier = LaunchNotifier(defaults: defaults)
        await notifier.processLaunch(in: container, now: TestPortfolio.date("2026-01-02T00:00:00Z"))
        XCTAssertEqual(defaults.object(forKey: "lastLaunchDate") as? Date, future)
        XCTAssertNotNil(notifier.alertMessage)
    }

}
