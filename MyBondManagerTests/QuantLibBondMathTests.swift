import XCTest
@testable import MyBondManager

final class QuantLibBondMathTests: XCTestCase {
    func testModifiedFollowingKeepsMonthEndPaymentInItsMonth() throws {
        XCTAssertEqual(try QuantLibBondMath.modifiedFollowing(MarketDay("2027-01-31")).rawValue, "2027-01-29")
    }
    func testLinkedVersionAndTARGETHolidayAdjustment() throws {
        XCTAssertEqual(QuantLibBondMath.version, "1.44")
        XCTAssertEqual(try QuantLibBondMath.following(MarketDay("2026-04-03")).rawValue, "2026-04-07")
    }
    func testUnsupportedNativeDateRangeIsRejected() throws {
        XCTAssertThrowsError(try QuantLibBondMath.following(MarketDay("1900-01-01")))
        XCTAssertThrowsError(try QuantLibBondMath.following(MarketDay("2200-01-01")))
    }
    func testMalformedNativeDateDoesNotOverwriteErrorBufferSentinel() {
        var result: Int32 = 0
        var bytes: [CChar] = [42, 99]
        let status = bytes.withUnsafeMutableBufferPointer { buffer in
            MBMQLFollowing(20260231, &result, buffer.baseAddress, 1)
        }
        XCTAssertNotEqual(status, 0)
        XCTAssertEqual(bytes[0], 0)
        XCTAssertEqual(bytes[1], 99)
    }
    func testNullNativeOutputIsRejected() {
        var bytes = [CChar](repeating: 0, count: 512)
        let status = bytes.withUnsafeMutableBufferPointer {
            MBMQLFollowing(20260403, nil, $0.baseAddress, $0.count)
        }
        XCTAssertNotEqual(status, 0)
    }
    func testLongFirstCouponAndLaterRegularCoupon() throws {
        var terms = try BondTermsFixtures.fixed(frequency: 2, maturity: "2031-05-31", next: "2026-11-30")
        terms.accrualStart = try MarketDay("2026-05-13")
        terms.firstCoupon = try MarketDay("2026-11-30")
        terms.couponRate = 6.875; terms.roll = .endOfMonth
        let coupons = try QuantLibBondMath.payments(terms: terms, nominal: 100000).filter { $0.kind == .interest }
        XCTAssertEqual(coupons.count, 10)
        XCTAssertEqual(try XCTUnwrap(coupons.first).amount, 3777.4725274725274, accuracy: 1e-8)
        XCTAssertEqual(coupons[1].amount, 3437.5, accuracy: 1e-8)
        XCTAssertEqual(coupons[1].contractualDay.rawValue, "2027-05-31")
    }
    func testIndependentOpeningCouponAmounts() throws {
        let rows: [(Int, String, String, String, Double, CouponRoll, Double)] = [
            (1, "2025-05-23", "2026-02-23", "2036-02-23", 4.625, .dayOfMonth, 3497.2602739726026),
            (2, "2024-02-15", "2024-08-31", "2026-08-31", 6, .endOfMonth, 3230.7692307692305),
            (4, "2023-11-15", "2024-03-31", "2025-03-31", 6, .endOfMonth, 2250),
            (2, "2024-12-15", "2025-02-28", "2025-02-28", 6, .endOfMonth, 1243.0939226519337),
            (2, "2024-12-15", "2025-02-28", "2025-02-28", 6, .dayOfMonth, 1222.8260869565217)
        ]
        for (frequency, start, first, end, rate, roll, expected) in rows {
            var terms = try BondTermsFixtures.fixed(frequency: frequency, maturity: end)
            terms.accrualStart = try MarketDay(start); terms.firstCoupon = try MarketDay(first)
            terms.couponRate = rate; terms.roll = roll
            let coupon = try XCTUnwrap(QuantLibBondMath.payments(terms: terms, nominal: 100000).first)
            XCTAssertEqual(coupon.amount, expected, accuracy: 1e-8, start + " / " + first)
        }
    }
    func testSingleLongCouponAtMaturityHasNoPhantomPayment() throws {
        var terms = try BondTermsFixtures.fixed(frequency: 2, maturity: "2026-11-30")
        terms.accrualStart = try MarketDay("2026-05-13"); terms.firstCoupon = terms.maturity
        terms.couponRate = 6.875; terms.roll = .endOfMonth
        let payments = try QuantLibBondMath.payments(terms: terms, nominal: 100000)
        XCTAssertEqual(payments.count, 2)
        XCTAssertEqual(payments[0].amount, 3777.4725274725274, accuracy: 1e-8)
        XCTAssertEqual(payments[1].amount, 100000)
    }
    func testUnknownRollRequiresConfirmationForPreStartReferenceBoundary() throws {
        var terms = try BondTermsFixtures.fixed(frequency: 2, maturity: "2025-02-28")
        terms.accrualStart = try MarketDay("2024-12-15"); terms.firstCoupon = terms.maturity; terms.roll = nil
        XCTAssertThrowsError(try QuantLibBondMath.payments(terms: terms, nominal: 100000))
    }
    func testZeroCouponIgnoresUnusedCouponMetadata() throws {
        var terms = try BondTermsFixtures.fixed(maturity: "2027-01-15")
        terms.structure = .zero; terms.frequency = 999; terms.couponRate = nil
        terms.accrualStart = nil; terms.redemptionPercent = 105
        let payments = try QuantLibBondMath.payments(terms: terms, nominal: 100000)
        XCTAssertEqual(payments.count, 1)
        XCTAssertEqual(payments[0].kind, .maturity)
        XCTAssertEqual(payments[0].amount, 105000)
    }
    func testNativeCapacityFailureDoesNotPublishPartialPayments() {
        var request = MBMQLRequest(structure: 1, startDay: 0, maturityDay: 20270115, firstCouponDay: 0,
            frequency: 0, roll: 2, nominal: 100000, annualRate: 0, redemptionPercent: 100)
        var output = MBMQLPayment(kind: 99, contractualDay: 42, paymentDay: 42, irregularOpening: 0, amount: 42)
        var count = 99
        var bytes = [CChar](repeating: 0, count: 512)
        let status = bytes.withUnsafeMutableBufferPointer {
            MBMQLPayments(&request, &output, 0, &count, $0.baseAddress, $0.count)
        }
        XCTAssertEqual(status, 2); XCTAssertEqual(count, 0)
        XCTAssertEqual(output.amount, 42); XCTAssertEqual(output.kind, 99)
    }
}
