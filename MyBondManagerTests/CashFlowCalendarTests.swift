import XCTest
@testable import MyBondManager

@MainActor
final class CashFlowCalendarTests: XCTestCase {
    func testReceiptsUseFullRedemptionWithoutDoubleCountingGain() throws {
        let store = try TestPortfolio.make()
        let terms = try BondTermsFixtures.fixed()
        for cost in [99010.0, 98570.0] {
            _ = try TestPortfolio.readyBond(in: store.viewContext, terms: terms,
                now: TestPortfolio.date("2026-10-18T12:00:00Z"), nominal: 100000, cost: cost)
        }
        let bonds = try store.viewContext.fetch(BondEntity.fetchRequest())
        let data = CashFlowCalendarData.build(bonds: bonds, from: try MarketDay("2027-01-15"), through: try MarketDay("2027-01-15"))
        XCTAssertEqual(data.receipts.count, 4)
        XCTAssertEqual(data.totals.repayments, 200000)
        XCTAssertEqual(data.totals.coupons, 3375)
        XCTAssertEqual(data.totals.total, 203375)
        XCTAssertEqual(Set(data.receipts.map(\.isin)).count, 1)
        XCTAssertEqual(Set(data.receipts.map(\.purchaseID)).count, 2)
        let onlyRedemption = CashFlowCalendarData.build(bonds: bonds, from: try MarketDay("2027-01-15"),
            through: try MarketDay("2027-01-15"), kind: .maturity)
        XCTAssertEqual(onlyRedemption.totals.total, 200000)
    }

    func testAdjustedPaymentDayAndExcludedHoldings() throws {
        let store = try TestPortfolio.make()
        var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2027-01-01", next: "2027-01-01")
        terms.accrualStart = try MarketDay("2026-01-01")
        let ready = try TestPortfolio.readyBond(in: store.viewContext, terms: terms,
            now: TestPortfolio.date("2026-10-18T12:00:00Z"))
        let unresolved = TestPortfolio.bond(in: store.viewContext)
        let archived = TestPortfolio.bond(in: store.viewContext)
        archived.maturityDate = TestPortfolio.date("2025-01-01T00:00:00Z")
        let data = CashFlowCalendarData.build(bonds: [ready, unresolved, archived],
            from: try MarketDay("2027-01-02"), through: try MarketDay("2027-01-04"))
        XCTAssertEqual(data.receipts.count, 2)
        XCTAssertTrue(data.receipts.allSatisfy { $0.paymentDay.rawValue == "2027-01-04" })
        XCTAssertTrue(data.receipts.allSatisfy { $0.contractualDay.rawValue == "2027-01-01" })
        XCTAssertEqual(data.exclusions.count, 1)
    }

    func testCallableAndStaleMarketCaveatsSurviveCalendarProjection() throws {
        let store = try TestPortfolio.make()
        var fixed = try BondTermsFixtures.fixed(); fixed.callable = true
        let callable = try TestPortfolio.readyBond(in: store.viewContext, terms: fixed,
            now: TestPortfolio.date("2026-10-18T12:00:00Z"))
        let fixedData = CashFlowCalendarData.build(bonds: [callable], from: try MarketDay("2026-10-18"), through: try MarketDay("2027-12-31"))
        XCTAssertTrue(fixedData.receipts.contains { $0.warnings.contains("Early redemption is not modeled.") })

        let floating = TestPortfolio.bond(in: store.viewContext)
        floating.acquisitionDate = TestPortfolio.date("2026-10-23T00:00:00Z")
        var terms = try FloatingMathFixtures.singlePeriodTerms(start: "2027-01-15", end: "2027-04-15")
        terms.approvedAt = TestPortfolio.date("2026-10-23T12:00:00Z")
        let market = try FloatingMathFixtures.context(valuation: "2026-10-23", fixings: [])
        let trade = try BondTermsStore.trade(floating)
        let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay("2026-10-23"), context: market)
        XCTAssertTrue(preview.assessment.supported, preview.assessment.reasons.joined())
        try BondTermsStore.replaceProjections(for: floating, terms: terms, preview: preview, now: terms.approvedAt!,
            acquisitionDay: trade.acquisitionDay, legacyDateZone: "Europe/Berlin", context: store.viewContext, projectionContext: market)
        let data = CashFlowCalendarData.build(bonds: [floating], from: try MarketDay("2026-10-23"), through: try MarketDay("2027-12-31"))
        XCTAssertTrue(data.receipts.contains { $0.warnings.contains { $0.contains("more than two TARGET") } })
    }

    func testArchivedMalformedProfileDoesNotInflateActiveExclusions() throws {
        let store = try TestPortfolio.make()
        let archived = TestPortfolio.bond(in: store.viewContext)
        archived.maturityDate = TestPortfolio.date("2025-01-01T00:00:00Z")
        archived.termsReady = true; archived.termsData = Data([0xff])
        let data = CashFlowCalendarData.build(bonds: [archived], from: try MarketDay("2026-10-18"), through: try MarketDay("2027-12-31"))
        XCTAssertTrue(data.exclusions.isEmpty)
    }

    func testMonthGridIsMondayFirstAndHandlesLeapDay() throws {
        let february = CalendarMonth(year: 2028, month: 2)
        XCTAssertEqual(february.days.count, 42)
        XCTAssertNil(february.days[0]) // February 1, 2028 is Tuesday.
        XCTAssertEqual(february.days[1]?.rawValue, "2028-02-01")
        XCTAssertEqual(february.days.compactMap { $0 }.count, 29)
        XCTAssertEqual(february.days.compactMap { $0 }.last?.day, 29)
        let november = CalendarMonth(year: 2026, month: 11)
        XCTAssertEqual(november.days[6]?.day, 1) // Sunday.
    }
}
