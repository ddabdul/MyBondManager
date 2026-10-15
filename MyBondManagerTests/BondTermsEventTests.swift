import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class BondTermsEventTests: XCTestCase {
    private func januaryTerms() throws -> BondTerms {
        var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2027-01-01", next: "2027-01-01")
        terms.accrualStart = try MarketDay("2026-01-01"); terms.redemptionPercent = 105
        return terms
    }
    func testAdjustedMaturityNeverPostsEarlyAndUsesActualRedemption() throws {
        let container = try TestPortfolio.make()
        _ = try TestPortfolio.readyBond(in: container.viewContext, terms: januaryTerms(),
            now: TestPortfolio.date("2026-12-30T12:00:00Z"))
        XCTAssertTrue(try LaunchEventProcessor.stage(context: container.viewContext,
            since: TestPortfolio.date("2026-12-31T00:00:00Z"), until: TestPortfolio.date("2027-01-02T00:00:00Z")).isEmpty)
        let messages = try LaunchEventProcessor.stage(context: container.viewContext,
            since: TestPortfolio.date("2027-01-02T00:00:00Z"), until: TestPortfolio.date("2027-01-05T00:00:00Z"))
        XCTAssertEqual(messages.count, 2)
        let rows = try container.viewContext.fetch(HistoricalValuation.fetchRequest())
        XCTAssertEqual(rows.reduce(0) { $0 + $1.capitalGains.doubleValue }, 150)
        XCTAssertEqual(rows.reduce(0) { $0 + $1.investedCapital.doubleValue }, -1000)
    }
    func testLegacyKeyAndRepeatedRegenerationNeverDuplicateEconomicPayment() throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext, cost: 900)
        let oldDate = bond.maturityDate
        let record = try HistoricalDataRecorder.recordChange(assetType: .bond, investedDelta: -1000,
            interestDelta: 0, gainsDelta: 100, date: oldDate, context: container.viewContext)
        record.eventKey = "\(bond.id)|maturity|\(Int(oldDate.timeIntervalSince1970))"
        var terms = try januaryTerms(); let now = TestPortfolio.date("2026-12-30T12:00:00Z"); terms.approvedAt = now
        let preview = try BondSchedule.preview(trade: BondTermsStore.trade(bond), terms: terms, from: MarketDay(date: now))
        try BondTermsStore.replaceProjections(for: bond, terms: terms, preview: preview, now: now,
            acquisitionDay: MarketDay("2025-01-01"), legacyDateZone: "Europe/Berlin", context: container.viewContext)
        for _ in 0..<2 { try CashFlowGenerator(context: container.viewContext).regenerateCashFlows(for: bond, now: now) }
        let since = TestPortfolio.date("2027-01-02T00:00:00Z"), until = TestPortfolio.date("2027-01-05T00:00:00Z")
        XCTAssertEqual(try LaunchEventProcessor.stage(context: container.viewContext, since: since, until: until).count, 1)
        XCTAssertTrue(try LaunchEventProcessor.stage(context: container.viewContext, since: since, until: until).isEmpty)
        XCTAssertEqual(try container.viewContext.count(for: HistoricalValuation.fetchRequest()), 2)
        XCTAssertEqual(record.capitalGains.doubleValue, 100)
    }
    func testUnapprovedAndEarlierTodayPaymentsNeverPost() throws {
        let container = try TestPortfolio.make()
        let legacy = TestPortfolio.bond(in: container.viewContext)
        legacy.maturityDate = TestPortfolio.date("2027-01-04T00:00:00Z")
        _ = try TestPortfolio.readyBond(in: container.viewContext, terms: januaryTerms(),
            now: TestPortfolio.date("2027-01-04T12:00:00Z"))
        let messages = try LaunchEventProcessor.stage(context: container.viewContext,
            since: TestPortfolio.date("2026-12-31T00:00:00Z"), until: TestPortfolio.date("2027-01-05T00:00:00Z"))
        XCTAssertTrue(messages.isEmpty)
        XCTAssertEqual(try container.viewContext.count(for: HistoricalValuation.fetchRequest()), 0)
    }
    func testAmbiguousUnkeyedHistoryCannotBeAutomaticallyAttributed() throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext)
        _ = try HistoricalDataRecorder.recordChange(assetType: .bond, depotBank: bond.depotBank,
            investedDelta: -1000, interestDelta: 0, gainsDelta: 100,
            date: TestPortfolio.date("2027-01-01T00:00:00Z"), context: container.viewContext)
        var terms = try januaryTerms(); let now = TestPortfolio.date("2027-01-02T12:00:00Z"); terms.approvedAt = now
        let preview = try BondSchedule.preview(trade: BondTermsStore.trade(bond), terms: terms, from: MarketDay(date: now))
        try BondTermsStore.replaceProjections(for: bond, terms: terms, preview: preview, now: now,
            acquisitionDay: MarketDay("2025-01-01"), legacyDateZone: "Europe/Berlin", context: container.viewContext)
        XCTAssertFalse(BondTermsStore.isReady(bond)); XCTAssertNotNil(bond.termsIssue)
        XCTAssertTrue(try LaunchEventProcessor.stage(context: container.viewContext,
            since: TestPortfolio.date("2027-01-02T00:00:00Z"), until: TestPortfolio.date("2027-01-05T00:00:00Z")).isEmpty)
        XCTAssertEqual(try container.viewContext.count(for: HistoricalValuation.fetchRequest()), 1)
    }
}
