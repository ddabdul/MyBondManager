import XCTest
@testable import MyBondManager

@MainActor
final class PaymentCalendarTests: XCTestCase {
    func testCanonicalReceiptsGroupPurchasesAndUseFullRedemption() throws {
        let store = try TestPortfolio.make()
        for cost in [99010.0, 98570.0] {
            _ = try TestPortfolio.readyBond(in: store.viewContext, terms: BondTermsFixtures.fixed(),
                now: TestPortfolio.date("2026-10-18T12:00:00Z"), nominal: 100000, cost: cost)
        }
        let unresolved = TestPortfolio.bond(in: store.viewContext)
        unresolved.maturityDate = TestPortfolio.date("2028-01-01T00:00:00Z")
        let data = CashFlowCalendarData.build(bonds: try store.viewContext.fetch(BondEntity.fetchRequest()),
            from: try MarketDay("2026-10-18"), through: try MarketDay("2199-12-31"))
        let result = try PaymentCalendarProjection.make(data: data, options: .init(), timeZone: TimeZone(identifier: "Europe/Berlin")!)
        XCTAssertEqual(result.count, 1)
        let event = try XCTUnwrap(result.first)
        XCTAssertTrue(event.title.contains("203,375"), event.title)
        XCTAssertTrue(event.notes.contains("200,000"), event.notes)
        XCTAssertTrue(event.notes.contains("3,375"), event.notes)
        XCTAssertTrue(event.notes.contains("2 purchases"), event.notes)
        XCTAssertTrue(event.notes.contains("Expected payment"))
        XCTAssertEqual(data.exclusions.count, 1)
    }

    func testAdjustedDayStableIdentityPrivacyAndAlarmAcrossDST() throws {
        let day = try MarketDay("2027-03-29")
        let receipt = CalendarReceipt(id: "example", purchaseID: UUID(), isin: " xs123 ", name: "Example bond",
            bank: "Bank", acquisitionDay: try MarketDay("2026-01-01"), nominal: 100000, cost: 99000,
            paymentDay: day, contractualDay: try MarketDay("2027-03-28"), kind: .interest, amount: 1250,
            rateSource: .projected, conditional: true, warnings: ["Frozen market data."])
        let data = CashFlowCalendarData(receipts: [receipt], exclusions: [])
        var options = PaymentCalendarOptions(); options.dayBefore = true; options.showAmounts = false
        let events = try PaymentCalendarProjection.make(data: data, options: options, timeZone: TimeZone(identifier: "Europe/Berlin")!)
        let event = try XCTUnwrap(events.first)
        XCTAssertFalse(event.title.contains("1,250"))
        XCTAssertTrue(event.notes.contains("Projected"))
        XCTAssertTrue(event.notes.contains("Conditional"))
        XCTAssertTrue(event.notes.contains("2027-03-28"))
        XCTAssertTrue(event.notes.contains("Frozen market data."))
        XCTAssertEqual(event.alarms, [TestPortfolio.date("2027-03-28T07:00:00Z"), TestPortfolio.date("2027-03-29T07:00:00Z")])
        options.showAmounts = true; options.hour = 15
        let changed = try XCTUnwrap(PaymentCalendarProjection.make(data: data, options: options,
            timeZone: TimeZone(identifier: "Asia/Nicosia")!).first)
        XCTAssertEqual(event.key, changed.key, "Options must update the same event rather than duplicate it")
    }

    func testReconciliationUpdatesDuplicatesDeletesStaleFutureAndPreservesPast() throws {
        let first = try event(day: "2027-01-15", amount: 1000)
        let changed = try event(day: "2027-01-15", amount: 2000)
        let stale = try event(day: "2028-01-15", amount: 1000)
        let past = try event(day: "2025-01-15", amount: 1000)
        let plan = PaymentCalendarChanges(desired: [changed], existing: [
            .init(identifier: "keeper", event: first), .init(identifier: "duplicate", event: first),
            .init(identifier: "stale", event: stale), .init(identifier: "past", event: past)
        ], from: try MarketDay("2026-10-18"))
        XCTAssertEqual(plan.upserts.count, 1)
        XCTAssertEqual(plan.upserts.first?.identifier, "keeper")
        XCTAssertEqual(Set(plan.removals), ["duplicate", "stale"])
        let repeated = PaymentCalendarChanges(desired: [changed], existing: [.init(identifier: "keeper", event: changed)],
            from: try MarketDay("2026-10-18"))
        XCTAssertTrue(repeated.upserts.isEmpty)
        XCTAssertTrue(repeated.removals.isEmpty)
        let empty = PaymentCalendarChanges(desired: [], existing: [.init(identifier: "keeper", event: changed)],
            from: try MarketDay("2026-10-18"))
        XCTAssertEqual(empty.removals, ["keeper"], "Deleting a holding must remove its future reminders")
    }

    func testNativeOwnershipRejectsUnrelatedOrMalformedCalendarEvents() throws {
        XCTAssertNil(EventKitPaymentCalendarStore.ownedKey(nil))
        XCTAssertNil(EventKitPaymentCalendarStore.ownedKey(URL(string: "https://example.com/payment/EXAMPLE/2027-01-15")))
        XCTAssertNil(EventKitPaymentCalendarStore.ownedKey(URL(string: "mybondmanager://payment/EXAMPLE/invalid")))
        XCTAssertNil(EventKitPaymentCalendarStore.ownedKey(URL(string: "mybondmanager://payment/EXAMPLE/2027-01-15/extra")))
        XCTAssertEqual(EventKitPaymentCalendarStore.ownedKey(URL(string: "mybondmanager://payment/EXAMPLE/2027-01-15"))?.key,
            "EXAMPLE/2027-01-15")
    }

    private func event(day: String, amount: Double) throws -> PaymentCalendarEvent {
        let day = try MarketDay(day)
        let receipt = CalendarReceipt(id: UUID().uuidString, purchaseID: UUID(), isin: "EXAMPLE", name: "Example bond",
            bank: "Bank", acquisitionDay: day, nominal: 100000, cost: 99000, paymentDay: day,
            contractualDay: day, kind: .interest, amount: amount, rateSource: nil, conditional: false, warnings: [])
        return try XCTUnwrap(PaymentCalendarProjection.make(data: .init(receipts: [receipt], exclusions: []),
            options: .init(), timeZone: TimeZone(identifier: "Europe/Berlin")!).first)
    }
}
