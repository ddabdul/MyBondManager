import XCTest
@testable import MyBondManager

final class BondScheduleTests: XCTestCase {
    func testRegularFrequenciesKeepFullCouponForMidPeriodPurchase() throws {
        for (frequency, next, amount, count) in [(1,"2027-01-15",3375.0,1), (2,"2026-07-15",1687.5,2), (4,"2026-04-15",843.75,4)] {
            let result = try BondSchedule.preview(trade: BondTermsFixtures.trade(),
                terms: BondTermsFixtures.fixed(frequency: frequency, next: next), from: MarketDay("2026-02-01"))
            XCTAssertTrue(result.assessment.supported, result.assessment.reasons.joined())
            XCTAssertEqual(result.payments.filter { $0.kind == .interest }.map(\.amount), Array(repeating: amount, count: count))
        }
    }
    func testDelayedFinalCouponAndRedemptionAndStableIdentity() throws {
        var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2027-01-01", next: "2027-01-01")
        terms.accrualStart = try MarketDay("2026-01-01")
        let result = try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: terms, from: MarketDay("2027-01-02"))
        XCTAssertEqual(result.payments.map { $0.paymentDay.rawValue }, ["2027-01-04", "2027-01-04"])
        XCTAssertEqual(result.payments.map(\.amount), [3375, 100000])
        XCTAssertTrue(result.payments[0].identity.hasSuffix("|interest|2027-01-01"))
    }
    func testActualRedemptionCashDoesNotDoubleCountSignedLoss() throws {
        for (percent, cash, loss, gain) in [(95.0,95000.0,-5000.0,0.0), (105.0,105000.0,0.0,5000.0)] {
            var terms = try BondTermsFixtures.fixed(); terms.redemptionPercent = percent
            let result = try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: terms, from: MarketDay("2027-01-15"))
            XCTAssertEqual(result.flows.filter { [.principal,.capitalGains].contains($0.nature) }.reduce(0) { $0 + $1.amount }, cash)
            XCTAssertEqual(result.flows.filter { $0.nature == .capitalLoss }.reduce(0) { $0 + $1.amount }, loss)
            XCTAssertEqual(result.flows.filter { $0.nature == .capitalGains }.reduce(0) { $0 + $1.amount }, gain)
        }
    }
    func testZeroIgnoresCouponMetadataAndCallableWarns() throws {
        var terms = try BondTermsFixtures.fixed(); terms.structure = .zero; terms.couponRate = 0
        terms.frequency = nil; terms.callable = true
        let result = try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: terms, from: MarketDay("2026-02-01"))
        XCTAssertTrue(result.assessment.supported)
        XCTAssertEqual(result.payments.count, 1)
        XCTAssertEqual(result.payments[0].kind, .maturity)
        XCTAssertFalse(result.assessment.warnings.isEmpty)
    }
    func testIncompleteUnsupportedContradictoryAndIrregularTermsNeverForecast() throws {
        let original = try BondTermsFixtures.fixed()
        let mutations: [(inout BondTerms) throws -> Void] = [
            { $0.frequency = nil }, { $0.callable = nil }, { $0.currency = "USD" },
            { $0.structure = .unknown }, { $0.restrictions = ["floating"] },
            { $0.conventions.dayCount = "actual360" }, { $0.couponRate = nil },
            { $0.redemptionPercent = -1 }, { $0.couponRate = .infinity },
            { $0.accrualStart = try MarketDay("2026-01-16") },
            { $0.nextCoupon = try MarketDay("2026-08-15") },
            { $0.maturity = nil }
        ]
        for mutate in mutations {
            var terms = original; try mutate(&terms)
            let result = try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: terms, from: MarketDay("2026-02-01"))
            XCTAssertFalse(result.assessment.supported); XCTAssertTrue(result.payments.isEmpty)
        }
    }
    func testOrdinaryMidMonthScheduleDoesNotRequireAnInventedRollOverride() throws {
        var terms = try BondTermsFixtures.fixed(); terms.roll = nil
        XCTAssertTrue(try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: terms,
            from: MarketDay("2026-02-01")).assessment.supported)
    }
    func testAgedCheckpointStillValidAndMonthEndRequiresConfirmation() throws {
        let terms = try BondTermsFixtures.fixed()
        XCTAssertTrue(try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: terms,
            from: MarketDay("2026-10-01")).assessment.supported)
        var end = try BondTermsFixtures.fixed(maturity: "2027-02-28", next: "2026-08-31")
        end.accrualStart = try MarketDay("2026-02-28"); end.roll = nil
        XCTAssertFalse(try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: end,
            from: MarketDay("2026-02-01")).assessment.supported)
        end.roll = .endOfMonth
        let result = try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: end, from: MarketDay("2026-02-01"))
        XCTAssertTrue(result.assessment.supported)
        XCTAssertEqual(result.payments.filter { $0.kind == .interest }.map { $0.contractualDay.rawValue }, ["2026-08-31", "2027-02-28"])
    }
    func testAnnualFebruaryRollRequiresConfirmationAcrossEveryCouponYear() throws {
        var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2030-02-28", next: "2027-02-28")
        terms.accrualStart = try MarketDay("2026-02-28")
        terms.checkpointObservedOn = try MarketDay("2026-03-01")
        terms.roll = nil
        let from = try MarketDay("2026-03-01")
        let ambiguous = try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: terms, from: from)
        XCTAssertFalse(ambiguous.assessment.supported)
        XCTAssertTrue(ambiguous.payments.isEmpty)
        for (roll, leapCoupon) in [(CouponRoll.dayOfMonth, "2028-02-28"), (.endOfMonth, "2028-02-29")] {
            terms.roll = roll
            let result = try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: terms, from: from)
            XCTAssertTrue(result.assessment.supported, result.assessment.reasons.joined())
            XCTAssertTrue(result.payments.contains { $0.kind == .interest && $0.contractualDay.rawValue == leapCoupon })
        }
    }

}
