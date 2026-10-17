import XCTest
@testable import MyBondManager

enum FloatingMathFixtures {
    static func singlePeriodTerms(start: String, end: String) throws -> BondTerms {
        var terms = try BondTermsFixtures.fixed(maturity: end, next: end)
        terms.structure = .floating; terms.couponRate = nil
        terms.accrualStart = try MarketDay(start); terms.firstCoupon = nil
        terms.checkpointObservedOn = terms.accrualStart
        var floating = FloatingFixtures.plain3M(); floating.firstFloatingCoupon = try MarketDay(end)
        terms.floatingTerms = floating
        return terms
    }
    static func context(valuation: String, fixings: [PublishedFixing]) throws -> ProjectionContext {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let day = try MarketDay(valuation)
        let payload = MarketDataPayload(formatVersion: 1, method: "euribor-singlecurve-v1", sourceName: "Public fixture",
            quotes: try CurveFixtures.quotes(), historicalFixings: fixings)
        let snapshot = try MarketDataStore(directory: directory).save(payload, retrievedAt: day.instant)
        return ProjectionContext(valuationDay: day, marketData: snapshot)
    }
    static func window(_ start: String, _ from: String) throws -> FloatingCalculationWindow {
        FloatingCalculationWindow(acquisitionDay: try MarketDay(start), paymentFrom: try MarketDay(from))
    }
}
final class FloatingBondMathTests: XCTestCase {
    func testKnownCouponUsesExactPublishedFixingAndACT360() throws {
        let terms = try FloatingMathFixtures.singlePeriodTerms(start: "2026-10-15", end: "2027-01-15")
        let context = try FloatingMathFixtures.context(valuation: "2026-10-16", fixings: [PublishedFixing(day: MarketDay("2026-10-13"), rate: 0.025)])
        let payments = try QuantLibBondMath.floatingPayments(terms: terms, nominal: 1000000, context: context,
            window: FloatingMathFixtures.window("2026-10-15", "2026-10-15"))
        let coupon = try XCTUnwrap(payments.first { $0.payment.kind == .interest })
        XCTAssertEqual(coupon.rateSource, .publishedFixing)
        XCTAssertEqual(coupon.fixingDay?.rawValue, "2026-10-13")
        XCTAssertEqual(coupon.payment.amount, 6772.222222222222, accuracy: 1e-8)
    }
    func testMissingPastAndTodayFixingsNeverUseForwards() throws {
        let terms = try FloatingMathFixtures.singlePeriodTerms(start: "2026-10-15", end: "2027-01-15")
        for valuation in ["2026-10-13", "2026-10-16"] {
            let context = try FloatingMathFixtures.context(valuation: valuation, fixings: [])
            XCTAssertThrowsError(try QuantLibBondMath.floatingPayments(terms: terms, nominal: 1000000, context: context,
                window: FloatingMathFixtures.window("2026-10-15", "2026-10-15")))
        }
    }
    func testFutureResetRemainsProjectedInFrozenContext() throws {
        let terms = try FloatingMathFixtures.singlePeriodTerms(start: "2027-01-15", end: "2027-04-15")
        let context = try FloatingMathFixtures.context(valuation: "2026-10-16", fixings: [])
        let payments = try QuantLibBondMath.floatingPayments(terms: terms, nominal: 1000000, context: context,
            window: FloatingMathFixtures.window("2027-01-15", "2027-03-01"))
        let coupon = try XCTUnwrap(payments.first { $0.payment.kind == .interest })
        XCTAssertEqual(coupon.rateSource, .projected)
        XCTAssertEqual(coupon.fixingDay?.rawValue, "2027-01-13")
    }
    func testNegativeKnownCouponHasNoImplicitFloor() throws {
        let terms = try FloatingMathFixtures.singlePeriodTerms(start: "2026-10-15", end: "2027-01-15")
        let context = try FloatingMathFixtures.context(valuation: "2026-10-16", fixings: [PublishedFixing(day: MarketDay("2026-10-13"), rate: -0.005)])
        let payments = try QuantLibBondMath.floatingPayments(terms: terms, nominal: 1000000, context: context,
            window: FloatingMathFixtures.window("2026-10-15", "2026-10-15"))
        XCTAssertEqual(try XCTUnwrap(payments.first).payment.amount, -894.4444444444445, accuracy: 1e-8)
    }
    func testIrrelevantPrePurchaseFixingsAreNotRequired() throws {
        var terms = try FloatingMathFixtures.singlePeriodTerms(start: "2020-01-15", end: "2027-01-15")
        terms.floatingTerms?.firstFloatingCoupon = try MarketDay("2020-04-15")
        let context = try FloatingMathFixtures.context(valuation: "2026-10-16", fixings: [PublishedFixing(day: MarketDay("2026-10-13"), rate: 0.025)])
        let payments = try QuantLibBondMath.floatingPayments(terms: terms, nominal: 1000000, context: context,
            window: FloatingMathFixtures.window("2026-10-16", "2026-10-16"))
        XCTAssertEqual(payments.filter { $0.payment.kind == .interest }.count, 1)
        XCTAssertEqual(try QuantLibBondMath.floatingCouponDays(terms: terms).count, 28)
    }
    func testResetAnchorsUseDifferentDaysButSameAdjustedAccrual() throws {
        for (anchor, expected) in [(FloatingResetAnchor.contractualAccrualStart,"2027-01-28"), (.adjustedAccrualStart,"2027-01-27")] {
            var terms = try FloatingMathFixtures.singlePeriodTerms(start: "2027-01-31", end: "2027-04-30")
            terms.floatingTerms?.roll = .endOfMonth; terms.floatingTerms?.accrualAdjustment = .modifiedFollowing
            terms.floatingTerms?.resetAnchor = anchor
            let context = try FloatingMathFixtures.context(valuation: "2027-01-29", fixings: [PublishedFixing(day: MarketDay(expected), rate: 0.025)])
            let payments = try QuantLibBondMath.floatingPayments(terms: terms, nominal: 1000000, context: context,
                window: FloatingMathFixtures.window("2027-01-01", "2027-01-01"))
            let coupon = try XCTUnwrap(payments.first)
            XCTAssertEqual(coupon.fixingDay?.rawValue, expected)
            XCTAssertEqual(coupon.payment.amount, 6698.611111111111, accuracy: 1e-8)
        }
    }
    func testMixedPhasesHaveOneTransitionCouponAndOneRedemption() throws {
        var terms = try FloatingMathFixtures.singlePeriodTerms(start: "2026-01-15", end: "2028-01-15")
        terms.structure = .fixedToFloating; terms.frequency = 1; terms.couponRate = 3
        terms.firstCoupon = try MarketDay("2027-01-15"); terms.floatingStart = terms.firstCoupon
        terms.floatingTerms?.firstFloatingCoupon = try MarketDay("2027-04-15")
        let context = try FloatingMathFixtures.context(valuation: "2026-10-16", fixings: [])
        let payments = try QuantLibBondMath.floatingPayments(terms: terms, nominal: 1000000, context: context,
            window: FloatingMathFixtures.window("2026-01-15", "2026-10-16"))
        XCTAssertEqual(payments.filter { $0.payment.kind == .maturity }.count, 1)
        XCTAssertEqual(payments.filter { $0.payment.contractualDay.rawValue == "2027-01-15" }.count, 1)
        XCTAssertEqual(try XCTUnwrap(payments.first).payment.amount, 30000, accuracy: 1e-8)
        XCTAssertEqual(payments[1].payment.contractualDay.rawValue, "2027-04-15")
    }
    func testOffGridFixedTransitionIsRejectedWithoutReanchoring() throws {
        var terms = try FloatingMathFixtures.singlePeriodTerms(start: "2025-05-31", end: "2030-05-31")
        terms.structure = .fixedToFloating; terms.frequency = 1; terms.couponRate = 3
        terms.firstCoupon = try MarketDay("2026-05-31"); terms.floatingStart = try MarketDay("2026-08-31")
        terms.floatingTerms?.firstFloatingCoupon = try MarketDay("2026-11-30")
        XCTAssertThrowsError(try QuantLibBondMath.floatingCouponDays(terms: terms)) { error in
            XCTAssertTrue(error.localizedDescription.contains("Off-grid"))
        }
    }
}
