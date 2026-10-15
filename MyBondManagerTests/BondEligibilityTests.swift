import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class BondEligibilityTests: XCTestCase {
    func testUnreviewedHoldingKeepsCapitalButHasNoForecastOrNextCoupon() throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext)
        let flow = CashFlowEntity(context: container.viewContext)
        flow.bond = bond; flow.date = TestPortfolio.date("2026-07-15T00:00:00Z"); flow.amount = 50; flow.nature = "interest"
        let day = try MarketDay("2026-02-01")
        XCTAssertTrue(BondEligibility.isActive(bond, on: day))
        XCTAssertEqual(BondEligibility.excludedCount([bond], on: day), 1)
        XCTAssertNil(BondEligibility.nextCoupon([bond], on: day))
        XCTAssertFalse(try BondEligibility.includes(flow, from: day, through: MarketDay("2027-01-05")))
        XCTAssertEqual([bond].filter { BondEligibility.isActive($0, on: day) }.reduce(0) { $0 + $1.initialPrice }, 1100)
    }
    func testAdjustedRedemptionKeepsHoldingActiveThroughPaymentDay() throws {
        let container = try TestPortfolio.make()
        var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2027-01-01", next: "2027-01-01")
        terms.accrualStart = try MarketDay("2026-01-01")
        let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: terms,
            now: TestPortfolio.date("2026-12-30T12:00:00Z"))
        for day in ["2027-01-01", "2027-01-04"] { XCTAssertTrue(BondEligibility.isActive(bond, on: try MarketDay(day))) }
        XCTAssertFalse(BondEligibility.isActive(bond, on: try MarketDay("2027-01-05")))
        let coupon = try XCTUnwrap(BondEligibility.nextCoupon([bond], on: MarketDay("2027-01-02")))
        XCTAssertEqual(MarketDay(date: coupon.date).rawValue, "2027-01-04")
        XCTAssertTrue(try BondEligibility.includes(coupon, from: MarketDay("2027-01-02"), through: MarketDay("2027-01-04")))
    }
    func testMixedGroupKeepsBothPurchasesButOnlyReadyYieldAndPayments() throws {
        let container = try TestPortfolio.make()
        var terms = try BondTermsFixtures.fixed(); terms.redemptionPercent = 105
        let ready = try TestPortfolio.readyBond(in: container.viewContext, terms: terms,
            now: TestPortfolio.date("2026-02-03T12:00:00Z"))
        let legacy = TestPortfolio.bond(in: container.viewContext)
        let group = BondSummary(id: ready.isin, name: ready.name, issuer: ready.issuer,
            couponRate: ready.couponRate, maturityDate: ready.maturityDate, records: [ready, legacy])
        XCTAssertEqual(group.totalNominal, 2000)
        XCTAssertEqual(try BondEligibility.weightedYTM([ready, legacy]), try BondTermsStore.estimatedYTM(ready))
        XCTAssertEqual(BondEligibility.excludedCount(group.records, on: try MarketDay("2026-02-03")), 1)
        XCTAssertNil(try BondEligibility.weightedYTM([legacy]))
        let flow = try XCTUnwrap(ready.cashFlowsArray.first { $0.natureEnum == .interest })
        XCTAssertTrue(try BondEligibility.includes(flow, from: MarketDay("2026-02-03"), through: MarketDay("2027-02-01")))
        flow.amount += 1
        XCTAssertFalse(try BondEligibility.includes(flow, from: MarketDay("2026-02-03"), through: MarketDay("2027-02-01")))
    }
}
