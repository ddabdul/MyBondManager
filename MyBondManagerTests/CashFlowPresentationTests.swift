import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class CashFlowPresentationTests: XCTestCase {
    private var calendar: Calendar {
        var result = Calendar(identifier: .gregorian)
        result.timeZone = TimeZone(secondsFromGMT: 0)!
        return result
    }
    private func flow(_ date: String, bond: BondEntity, amount: Double = 50) -> CashFlowEntity {
        let row = CashFlowEntity(context: bond.managedObjectContext!)
        row.bond = bond; row.date = TestPortfolio.date(date); row.amount = amount; row.natureEnum = .interest
        row.generatedFromTerms = true; row.contractualDay = MarketDay(date: row.date).rawValue
        row.eventIdentity = "\(bond.id)|interest|\(row.contractualDay!)"
        return row
    }

    func testSelectedDaysIncludeMidnightAndEndOfLastDay() throws {
        let container = try TestPortfolio.make()
        let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(),
            now: TestPortfolio.date("2026-10-01T12:00:00Z"))
        for row in bond.cashFlowsArray { container.viewContext.delete(row) }
        _ = flow("2026-10-15T00:00:00Z", bond: bond)
        _ = flow("2026-10-16T23:59:59Z", bond: bond)
        _ = flow("2026-10-17T00:00:00Z", bond: bond)
        let request = CashFlowEntity.fetchRequest()
        request.predicate = CashFlowSelection.predicate(searchText: "", nature: nil, bank: "All",
            start: TestPortfolio.date("2026-10-15T12:00:00Z"),
            end: TestPortfolio.date("2026-10-16T12:00:00Z"),
            now: TestPortfolio.date("2026-10-15T12:00:00Z"), calendar: calendar)
        XCTAssertEqual(try container.viewContext.fetch(request).count, 2)
    }

    func testMaturityTodayIsIncludedAndZeroCouponIsNotNextPayment() throws {
        let container = try TestPortfolio.make(), now = TestPortfolio.date("2026-10-15T12:00:00Z")
        let context = container.viewContext
        var todayTerms = try BondTermsFixtures.fixed(maturity: "2026-10-15")
        todayTerms.structure = .zero; todayTerms.couponRate = 0
        let today = try TestPortfolio.readyBond(in: context, terms: todayTerms,
            now: TestPortfolio.date("2026-10-14T12:00:00Z"))
        var zeroTerms = try BondTermsFixtures.fixed(); zeroTerms.structure = .zero; zeroTerms.couponRate = 0
        _ = try TestPortfolio.readyBond(in: context, terms: zeroTerms, now: TestPortfolio.date("2026-10-14T12:00:00Z"))
        var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2027-11-01", next: "2026-11-01")
        terms.accrualStart = try MarketDay("2025-11-01")
        let paying = try TestPortfolio.readyBond(in: context, terms: terms, now: TestPortfolio.date("2026-10-14T12:00:00Z"))
        _ = flow("2028-01-01T00:00:00Z", bond: today, amount: 50)
        let request = CashFlowEntity.fetchRequest()
        request.predicate = CashFlowSelection.predicate(searchText: "", nature: .principal, bank: "All",
            start: now, end: now, now: now)
        XCTAssertEqual(try context.fetch(request).count, 1)
        let next = try XCTUnwrap(CashFlowSelection.nextCoupon(in: [today, paying], now: now))
        XCTAssertEqual(MarketDay(date: next.date).rawValue, "2026-11-02")
        XCTAssertEqual(next.amount, 33.75)
    }
    func testRealSelectionRetainsFinalPaymentAfterContractualMaturity() throws {
        let container = try TestPortfolio.make()
        var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2027-01-01", next: "2027-01-01")
        terms.accrualStart = try MarketDay("2026-01-01")
        _ = try TestPortfolio.readyBond(in: container.viewContext, terms: terms,
            now: TestPortfolio.date("2026-12-30T12:00:00Z"))
        let start = try MarketDay("2027-01-02"), end = try MarketDay("2027-01-04")
        let request = CashFlowEntity.fetchRequest()
        request.predicate = CashFlowSelection.predicate(searchText: "", nature: nil, bank: "All",
            start: start.instant, end: end.instant, now: start.instant)
        let flows = try container.viewContext.fetch(request).filter { BondEligibility.includes($0, from: start, through: end) }
        XCTAssertEqual(flows.count, 3) // final coupon, principal and positive gain, no analytical extra cash
        XCTAssertTrue(flows.allSatisfy { MarketDay(date: $0.date).rawValue == "2027-01-04" })
    }

    func testSameNamedPositionsAtDifferentBanksRemainSeparateCards() throws {
        let container = try TestPortfolio.make()
        let first = TestPortfolio.bond(in: container.viewContext)
        let second = TestPortfolio.bond(in: container.viewContext)
        first.depotBank = "Bank A"; second.depotBank = "Bank B"
        let a = flow("2026-10-16T00:00:00Z", bond: first)
        let b = flow("2026-10-16T00:00:00Z", bond: second, amount: 75)
        try container.viewContext.save()
        let groups = YearGroup.build(from: [a, b], calendar: calendar)
        let cards = try XCTUnwrap(groups.first?.months.first).bondGroups
        XCTAssertEqual(cards.count, 2)
        XCTAssertEqual(Set(cards.map { $0.events.first?.depotBank }), Set(["Bank A", "Bank B"]))
        XCTAssertEqual(groups.first?.total, 125)
    }
}
