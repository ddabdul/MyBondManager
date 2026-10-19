import XCTest
@testable import MyBondManager

@MainActor
final class PastPaymentReportTests: XCTestCase {
    func testDropsPreviouslyMaturedBondsFromPaymentsWarningsAndJSONButKeepsTodayMaturity() throws {
        let store = try TestPortfolio.make()
        let ready = try TestPortfolio.readyBond(in: store.viewContext, terms: BondTermsFixtures.fixed(),
            now: TestPortfolio.date("2026-10-18T12:00:00Z"))
        let missing = TestPortfolio.bond(in: store.viewContext)
        missing.maturityDate = ready.maturityDate
        let today = TestPortfolio.bond(in: store.viewContext)
        today.maturityDate = TestPortfolio.date("2028-01-01T00:00:00Z")
        let report = try PastPaymentReport.build(bonds: [ready, missing, today], from: MarketDay("2026-07-15"),
            through: MarketDay("2027-01-15"), now: TestPortfolio.date("2028-01-01T12:00:00Z"))
        XCTAssertTrue(report.payments.isEmpty)
        XCTAssertEqual(report.total, 0)
        XCTAssertEqual(report.excludedHoldings.map(\.id), [today.id])
        let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
        let json = try decoder.decode(PastPaymentReport.self, from: report.json())
        XCTAssertTrue(json.payments.isEmpty)
        XCTAssertEqual(json.excludedHoldings.map(\.id), [today.id])
    }

    func testTodayMaturityUsesCanonicalDayAfterApprovalWithWesternLegacyTimezone() throws {
        let store = try TestPortfolio.make()
        let approvedAt = TestPortfolio.date("2026-10-18T12:00:00Z")
        let bond = try TestPortfolio.readyBond(in: store.viewContext, terms: BondTermsFixtures.fixed(), now: approvedAt)
        bond.termsLegacyDateZone = "America/New_York"
        let now = TestPortfolio.date("2027-01-15T12:00:00Z")
        let report = try PastPaymentReport.build(bonds: [bond], from: MarketDay("2026-07-15"),
            through: MarketDay("2026-07-15"), now: now)
        XCTAssertEqual(report.payments.count, 1)
        XCTAssertEqual(BondEligibility.contractualMaturityDay(bond), try MarketDay("2027-01-15"))
    }

    func testIncludesPastCouponsOfUnmaturedHoldingsWithInclusiveDatesAndJSON() throws {
        let store = try TestPortfolio.make()
        for cost in [99010.0, 98570.0] {
            _ = try TestPortfolio.readyBond(in: store.viewContext, terms: BondTermsFixtures.fixed(),
                now: TestPortfolio.date("2026-10-18T12:00:00Z"), nominal: 100000, cost: cost)
        }
        let bonds = try store.viewContext.fetch(BondEntity.fetchRequest())
        let report = try PastPaymentReport.build(bonds: bonds, from: MarketDay("2026-07-15"),
            through: MarketDay("2026-07-15"), now: TestPortfolio.date("2026-10-18T12:00:00Z"))
        XCTAssertEqual(report.payments.count, 2)
        XCTAssertEqual(report.coupons, 3375)
        XCTAssertEqual(report.redemptions, 0)
        XCTAssertEqual(report.total, 3375)
        XCTAssertTrue(report.isComplete)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: report.json()) as? [String: Any])
        XCTAssertEqual(object["basis"] as? String, "expected")
        XCTAssertEqual(object["from"] as? String, "2026-07-15")
        XCTAssertEqual(object["through"] as? String, "2026-07-15")
        XCTAssertEqual(object["total"] as? Double, 3375)
        let rows = try XCTUnwrap(object["payments"] as? [[String: Any]])
        XCTAssertEqual(rows.count, report.payments.count)
        XCTAssertEqual(rows.filter { $0["type"] as? String == "redemption" }.count, 0)
    }

    func testReconstructsPaymentsBeforeApprovalAndRespectsBankSearchAndType() throws {
        let store = try TestPortfolio.make()
        let bond = try TestPortfolio.readyBond(in: store.viewContext, terms: BondTermsFixtures.fixed(),
            now: TestPortfolio.date("2026-10-18T12:00:00Z"), nominal: 100000, cost: 99000)
        bond.name = "Historical EUR bond"
        let report = try PastPaymentReport.build(bonds: [bond], from: MarketDay("2026-07-15"), through: MarketDay("2026-07-15"),
            bank: "Bank", search: "historical", kind: .interest, now: TestPortfolio.date("2026-10-18T12:00:00Z"))
        XCTAssertEqual(report.payments.count, 1)
        XCTAssertEqual(report.coupons, 1687.5)
        XCTAssertTrue(report.payments.first?.paymentDay.rawValue == "2026-07-15")
        XCTAssertTrue(try PastPaymentReport.build(bonds: [bond], from: MarketDay("2026-07-15"), through: MarketDay("2026-07-15"),
            bank: "Other", now: TestPortfolio.date("2026-10-18T12:00:00Z")).payments.isEmpty)
        XCTAssertTrue(try PastPaymentReport.build(bonds: [bond], from: MarketDay("2026-07-15"), through: MarketDay("2026-07-15"),
            search: "no match", now: TestPortfolio.date("2026-10-18T12:00:00Z")).payments.isEmpty)
        XCTAssertTrue(try PastPaymentReport.build(bonds: [bond], from: MarketDay("2026-07-15"), through: MarketDay("2026-07-15"),
            kind: .maturity, now: TestPortfolio.date("2026-10-18T12:00:00Z")).payments.isEmpty)
    }

    func testUsesAdjustedCouponDateAndExposesOnlyUnmaturedMissingReviews() throws {
        let store = try TestPortfolio.make()
        var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2028-01-01", next: "2027-01-01")
        terms.accrualStart = try MarketDay("2026-01-01")
        let ready = try TestPortfolio.readyBond(in: store.viewContext, terms: terms,
            now: TestPortfolio.date("2026-10-18T12:00:00Z"))
        let missing = TestPortfolio.bond(in: store.viewContext)
        missing.maturityDate = TestPortfolio.date("2028-01-01T00:00:00Z")
        let unrelated = TestPortfolio.bond(in: store.viewContext)
        unrelated.acquisitionDate = TestPortfolio.date("2020-01-01T00:00:00Z")
        unrelated.maturityDate = TestPortfolio.date("2024-01-01T00:00:00Z")
        let now = TestPortfolio.date("2027-01-05T12:00:00Z")
        let earlier = try PastPaymentReport.build(bonds: [ready], from: MarketDay("2027-01-01"), through: MarketDay("2027-01-03"), now: now)
        XCTAssertTrue(earlier.payments.isEmpty)
        let report = try PastPaymentReport.build(bonds: [ready, missing, unrelated], from: MarketDay("2027-01-04"), through: MarketDay("2027-01-04"), now: now)
        XCTAssertEqual(report.payments.count, 1)
        XCTAssertTrue(report.payments.allSatisfy { $0.contractualDay.rawValue == "2027-01-01" })
        XCTAssertEqual(report.excludedHoldings.count, 1)
        XCTAssertFalse(report.isComplete)
        let beforePurchase = try PastPaymentReport.build(bonds: [ready], from: MarketDay("2025-01-01"), through: MarketDay("2025-12-31"), now: now)
        XCTAssertTrue(beforePurchase.payments.isEmpty)
        XCTAssertTrue(beforePurchase.excludedHoldings.isEmpty)
    }

    func testRejectsReversedAndNonPastRangesAndDoesNotModifyHistory() throws {
        let store = try TestPortfolio.make()
        let bond = try TestPortfolio.readyBond(in: store.viewContext, terms: BondTermsFixtures.fixed(),
            now: TestPortfolio.date("2026-10-18T12:00:00Z"))
        try store.viewContext.save()
        let now = TestPortfolio.date("2026-10-18T12:00:00Z")
        XCTAssertThrowsError(try PastPaymentReport.build(bonds: [bond], from: MarketDay("2026-07-16"), through: MarketDay("2026-07-15"), now: now))
        XCTAssertThrowsError(try PastPaymentReport.build(bonds: [bond], from: MarketDay("2026-07-15"), through: MarketDay("2026-10-18"), now: now))
        _ = try PastPaymentReport.build(bonds: [bond], from: MarketDay("2026-07-15"), through: MarketDay("2026-07-15"), now: now)
        XCTAssertFalse(store.viewContext.hasChanges)
        XCTAssertEqual(try store.viewContext.count(for: HistoricalValuation.fetchRequest()), 0)
    }
}
