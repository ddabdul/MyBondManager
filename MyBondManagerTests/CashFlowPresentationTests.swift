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
        return row
    }

    func testSelectedDaysIncludeMidnightAndEndOfLastDay() throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext)
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
        let container = try TestPortfolio.make()
        let context = container.viewContext
        let today = TestPortfolio.bond(in: context)
        today.maturityDate = TestPortfolio.date("2026-10-15T00:00:00Z")
        let principal = flow("2026-10-15T00:00:00Z", bond: today, amount: 1000)
        principal.natureEnum = .principal
        let zero = TestPortfolio.bond(in: context)
        _ = flow("2026-10-16T00:00:00Z", bond: zero, amount: 0)
        let paying = TestPortfolio.bond(in: context)
        _ = flow("2026-11-01T00:00:00Z", bond: paying, amount: 33.75)
        _ = flow("2028-01-01T00:00:00Z", bond: today, amount: 50)
        let now = TestPortfolio.date("2026-10-15T12:00:00Z")
        let request = CashFlowEntity.fetchRequest()
        request.predicate = CashFlowSelection.predicate(searchText: "", nature: .principal, bank: "All",
            start: now, end: now, now: now, calendar: calendar)
        XCTAssertEqual(try context.fetch(request).count, 1)
        let next = try XCTUnwrap(CashFlowSelection.nextCoupon(in: [today, zero, paying], now: now, calendar: calendar))
        XCTAssertEqual(next.date, TestPortfolio.date("2026-11-01T00:00:00Z"))
        XCTAssertEqual(next.amount, 33.75)
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
