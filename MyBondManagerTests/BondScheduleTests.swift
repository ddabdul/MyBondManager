import XCTest
@testable import MyBondManager

final class BondScheduleTests: XCTestCase {
    func testNativePreviewRejectsUnrepresentableDateExplicitly() throws {
        var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "1900-12-31", next: "1900-12-31")
        terms.accrualStart = try MarketDay("1900-01-01")
        terms.checkpointObservedOn = try MarketDay("1900-06-01")
        let trade = BondTrade(id: UUID(), isin: terms.isin, nominal: 100000, cost: 99000,
            acquisitionDay: try MarketDay("1900-01-01"), bank: "Fixture")
        let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay("1900-06-01"))
        XCTAssertFalse(preview.assessment.supported)
        XCTAssertTrue(preview.assessment.reasons.contains { $0.contains("1901") })
    }
    func testCheckpointMismatchNamesSuppliedExpectedAndObservedDays() throws {
        var terms = try BondTermsFixtures.fixed()
        terms.nextCoupon = try MarketDay("2026-08-15")
        let preview = try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: terms, from: MarketDay("2026-02-01"))
        XCTAssertFalse(preview.assessment.supported)
        let reason = preview.assessment.reasons.joined()
        for value in ["2026-08-15", "2026-07-15", "2026-02-01"] { XCTAssertTrue(reason.contains(value), reason) }
    }
    func testConfirmedFixedOverrideUsesConstantRateAndWarnsWithoutRemovingOtherRestrictions() throws {
        for marker in ["floating", "variabel", "fixed-to-floating", "Unsupported interest structure: Variabel"] {
            var terms = try BondTermsFixtures.fixed(); terms.rawStructure = "Variabel"
            terms.restrictions = [marker]
            XCTAssertFalse(try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: terms, from: MarketDay("2026-02-01")).assessment.supported)
            terms.confirmedFields.insert("structure")
            let preview = try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: terms, from: MarketDay("2026-02-01"))
            XCTAssertTrue(preview.assessment.supported, preview.assessment.reasons.joined())
            XCTAssertTrue(preview.assessment.warnings.contains { $0.contains("constant") && $0.contains("provider") })
            XCTAssertEqual(preview.payments.filter { $0.kind == .interest }.map(\.amount), [1687.5, 1687.5])
            terms.restrictions.append("ex-coupon")
            XCTAssertFalse(try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: terms, from: MarketDay("2026-02-01")).assessment.supported)
        }
    }
    func testOpeningReferencePeriodRequiresRollConfirmationEvenWhenBoundaryPrecedesAccrualStart() throws {
        var terms = try BondTermsFixtures.fixed(frequency: 2, maturity: "2025-02-28", next: "2025-02-28")
        terms.couponRate = 6; terms.accrualStart = try MarketDay("2024-12-15")
        terms.firstCoupon = try MarketDay("2025-02-28"); terms.checkpointObservedOn = try MarketDay("2025-01-01")
        terms.roll = nil
        let trade = BondTrade(id: UUID(), isin: terms.isin, nominal: 100000, cost: 100000,
            acquisitionDay: try MarketDay("2024-12-15"), bank: "Fixture")
        let unknown = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay("2025-01-01"))
        XCTAssertFalse(unknown.assessment.supported)
        XCTAssertTrue(unknown.assessment.reasons.contains { $0.contains("month-end roll") })
        terms.roll = .endOfMonth
        let eom = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay("2025-01-01"))
        XCTAssertEqual(try XCTUnwrap(eom.payments.first).amount, 3000 * 75 / 181, accuracy: 0.0000001)
        terms.roll = .dayOfMonth
        let dom = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay("2025-01-01"))
        XCTAssertEqual(try XCTUnwrap(dom.payments.first).amount, 3000 * 75 / 184, accuracy: 0.0000001)
    }
    func testConfirmedLongFirstCouponUsesICMAReferencePeriodsAndKeepsRegularAmounts() throws {
        var terms = try BondTermsFixtures.fixed(frequency: 2, maturity: "2031-05-31", next: "2026-11-30")
        terms.isin = "XS3350943018"; terms.couponRate = 6.875
        terms.accrualStart = try MarketDay("2026-05-13"); terms.firstCoupon = try MarketDay("2026-11-30")
        terms.checkpointObservedOn = try MarketDay("2026-10-16"); terms.roll = .endOfMonth
        let trade = BondTrade(id: UUID(), isin: terms.isin, nominal: 100000, cost: 99000,
            acquisitionDay: try MarketDay("2026-06-01"), bank: "Fixture")
        let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay("2026-10-16"))
        XCTAssertTrue(preview.assessment.supported, preview.assessment.reasons.joined())
        let coupons = preview.payments.filter { $0.kind == .interest }
        XCTAssertEqual(coupons.count, 10)
        // 18 days in Nov30-May31 (182 days), plus the full May31-Nov30 reference period.
        XCTAssertEqual(try XCTUnwrap(coupons.first).amount, 3777.4725274725274, accuracy: 0.0000001)
        XCTAssertEqual(coupons.first?.contractualDay.rawValue, "2026-11-30")
        XCTAssertEqual(coupons.dropFirst().first?.contractualDay.rawValue, "2027-05-31")
        for coupon in coupons.dropFirst() { XCTAssertEqual(coupon.amount, 3437.5, accuracy: 1e-8) }
        XCTAssertEqual(preview.flows.first { $0.nature == .interest }?.amount, coupons.first?.amount)
        let profit = try XCTUnwrap(preview.flows.first { $0.nature == .expectedProfit })
        XCTAssertEqual(profit.amount, 35714.97252747253, accuracy: 0.0000001)
    }
    func testConfirmedOpeningCouponsUseCalendarDaysAcrossLeapYearAndDST() throws {
        for (frequency, start, first, maturity, rate, amount) in [
            (2, "2024-02-15", "2024-08-31", "2026-08-31", 6.0, 3230.7692307692305),
            (4, "2023-11-15", "2024-03-31", "2025-03-31", 6.0, 2250.0),
            (1, "2025-05-23", "2026-02-23", "2036-02-23", 4.625, 3497.2602739726026)
        ] {
            var terms = try BondTermsFixtures.fixed(frequency: frequency, maturity: maturity, next: first)
            terms.couponRate = rate; terms.accrualStart = try MarketDay(start); terms.firstCoupon = try MarketDay(first)
            terms.checkpointObservedOn = try MarketDay(start); terms.roll = .endOfMonth
            if frequency == 1 { terms.roll = .dayOfMonth }
            let trade = BondTrade(id: UUID(), isin: terms.isin, nominal: 100000, cost: 100000,
                acquisitionDay: try MarketDay(start), bank: "Fixture")
            let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay(start))
            XCTAssertTrue(preview.assessment.supported, preview.assessment.reasons.joined())
            XCTAssertEqual(try XCTUnwrap(preview.payments.first).amount, amount, accuracy: 0.0000001)
            XCTAssertTrue(preview.payments.filter { $0.kind == .interest }.dropFirst().allSatisfy { $0.amount == 100000 * rate / 100 / Double(frequency) })
        }
    }
    func testHistoricalOpeningPeriodsDoNotBlockINGExamplesRegularFutureCoupons() throws {
        // ING dates captured 2026-10-16; coupon and trade amounts are controlled fixtures.
        for (isin, start, maturity, next, paid, count) in [
            ("BE6350792089", "2024-04-03", "2031-10-03", "2027-10-03", "2027-10-04", 5),
            ("DE0001135325", "2007-01-26", "2039-07-04", "2027-07-04", "2027-07-05", 13),
            ("EU000A1G30R0", "2012-04-24", "2038-04-04", "2027-04-04", "2027-04-05", 12)
        ] {
            var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: maturity, next: next)
            terms.isin = isin; terms.accrualStart = try MarketDay(start)
            terms.checkpointObservedOn = try MarketDay("2026-10-16")
            let trade = try BondTrade(id: UUID(), isin: isin, nominal: 100000, cost: 100000,
                acquisitionDay: MarketDay("2026-02-01"), bank: "Fixture")
            let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay("2026-10-16"))
            XCTAssertTrue(preview.assessment.supported, isin + ": " + preview.assessment.reasons.joined())
            let coupons = preview.payments.filter { $0.kind == .interest }
            XCTAssertEqual(coupons.count, count)
            XCTAssertEqual(coupons.first?.contractualDay.rawValue, next)
            XCTAssertEqual(coupons.first?.paymentDay.rawValue, paid)
            XCTAssertTrue(coupons.allSatisfy { $0.amount == 3375 })
            XCTAssertFalse(preview.assessment.warnings.isEmpty)
            XCTAssertEqual(terms.accrualStart?.rawValue, start)
        }
    }
    func testHistoricalOpeningPeriodSupportsEveryImplementedFrequency() throws {
        for (frequency, start, count) in [(1, "2024-02-10", 2), (2, "2025-02-10", 3), (4, "2026-02-10", 5)] {
            var terms = try BondTermsFixtures.fixed(frequency: frequency, maturity: "2028-01-15", next: "2027-01-15")
            terms.accrualStart = try MarketDay(start); terms.checkpointObservedOn = try MarketDay("2026-10-16")
            let preview = try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: terms, from: MarketDay("2026-10-16"))
            XCTAssertTrue(preview.assessment.supported, preview.assessment.reasons.joined())
            XCTAssertEqual(preview.payments.filter { $0.kind == .interest }.count, count)
            XCTAssertEqual(preview.payments.first?.amount, 3375 / Double(frequency))
        }
    }
    func testPotentialShortOrLongOpeningCouponsStillRequireTheirOwnTerms() throws {
        for (observed, next) in [("2025-06-01", "2025-07-15"), ("2025-10-01", "2026-01-15")] {
            var terms = try BondTermsFixtures.fixed(maturity: "2028-01-15", next: next)
            terms.accrualStart = try MarketDay("2025-02-10"); terms.checkpointObservedOn = try MarketDay(observed)
            let trade = try BondTrade(id: UUID(), isin: terms.isin, nominal: 100000, cost: 100000,
                acquisitionDay: MarketDay("2025-03-01"), bank: "Fixture")
            let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay(observed))
            XCTAssertFalse(preview.assessment.supported)
            XCTAssertTrue(preview.payments.isEmpty)
            XCTAssertTrue(preview.assessment.reasons.contains { $0.contains("opening coupon") })
        }
    }
    func testHistoricalOpeningPeriodDoesNotExcuseAContradictoryCheckpoint() throws {
        var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2031-10-03", next: "2027-04-03")
        terms.accrualStart = try MarketDay("2024-04-03"); terms.checkpointObservedOn = try MarketDay("2026-10-16")
        let preview = try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: terms, from: MarketDay("2026-10-16"))
        XCTAssertFalse(preview.assessment.supported)
        XCTAssertTrue(preview.assessment.reasons.contains { $0.contains("Next coupon contradicts") })
    }
    func testAdjustedOpeningCouponCannotBeTreatedAsAlreadyPaid() throws {
        var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2029-01-01", next: "2028-01-01")
        terms.accrualStart = try MarketDay("2025-02-03"); terms.checkpointObservedOn = try MarketDay("2027-01-05")
        let trade = try BondTrade(id: UUID(), isin: terms.isin, nominal: 100000, cost: 100000,
            acquisitionDay: MarketDay("2025-03-01"), bank: "Fixture")
        let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay("2027-01-02"))
        XCTAssertFalse(preview.assessment.supported)
        XCTAssertTrue(preview.payments.isEmpty)
        XCTAssertTrue(preview.assessment.reasons.contains { $0.contains("opening coupon") })
    }
    func testUnsupportedHistoricalDateIsReportedSeparatelyFromOpeningPeriodReview() throws {
        var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2199-01-15", next: "2027-01-15")
        terms.accrualStart = try MarketDay("0900-01-15"); terms.checkpointObservedOn = try MarketDay("2026-10-16")
        let preview = try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: terms, from: MarketDay("2026-10-16"))
        XCTAssertFalse(preview.assessment.supported)
        XCTAssertEqual(preview.assessment.reasons, ["QuantLib dates must be in 1901...2199."])
    }
    func testVerifiedMatmutFirstCouponAllowsRegularPaymentsAfterTheShortPeriod() throws {
        var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2036-02-23", next: "2027-02-23")
        terms.isin = "FR001400ZQ88"; terms.couponRate = 4.625
        terms.accrualStart = try MarketDay("2025-05-23"); terms.issueDay = terms.accrualStart
        terms.checkpointObservedOn = try MarketDay("2026-10-16")
        let encoder = JSONEncoder()
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(terms)) as? [String: Any])
        json["firstCoupon"] = "2026-02-23"; json["interestDeferral"] = true
        let verified = try JSONDecoder().decode(BondTerms.self, from: JSONSerialization.data(withJSONObject: json))
        let trade = try BondTrade(id: UUID(), isin: terms.isin, nominal: 100000, cost: 100000,
            acquisitionDay: MarketDay("2025-06-01"), bank: "Fixture")
        let preview = try BondSchedule.preview(trade: trade, terms: verified, from: MarketDay("2026-10-16"))
        XCTAssertTrue(preview.assessment.supported, preview.assessment.reasons.joined())
        XCTAssertEqual(preview.payments.first?.contractualDay.rawValue, "2027-02-23")
        XCTAssertEqual(preview.payments.first?.amount, 4625)
        XCTAssertTrue(preview.assessment.warnings.contains { $0.localizedCaseInsensitiveContains("defer") })
        let roundTrip = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(verified)) as? [String: Any])
        XCTAssertEqual(roundTrip["firstCoupon"] as? String, "2026-02-23")
        XCTAssertEqual(roundTrip["interestDeferral"] as? Bool, true)
    }
    func testVerifiedFirstCouponMustFitTheGrid() throws {
        for first in ["2025-05-23", "2026-03-23", "2037-02-23"] {
            var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2036-02-23", next: "2026-02-23")
            terms.accrualStart = try MarketDay("2025-05-23"); terms.checkpointObservedOn = try MarketDay("2025-10-16")
            var json = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(terms)) as? [String: Any])
            json["firstCoupon"] = first
            let verified = try JSONDecoder().decode(BondTerms.self, from: JSONSerialization.data(withJSONObject: json))
            let trade = try BondTrade(id: UUID(), isin: terms.isin, nominal: 100000, cost: 100000,
                acquisitionDay: MarketDay("2025-06-01"), bank: "Fixture")
            let preview = try BondSchedule.preview(trade: trade, terms: verified, from: MarketDay("2025-10-16"))
            XCTAssertFalse(preview.assessment.supported)
            XCTAssertTrue(preview.payments.isEmpty)
        }
    }
    func testRetainedVariableInterestRestrictionCannotBecomeAFixedForecastWithoutRawLabel() throws {
        var terms = try BondTermsFixtures.fixed()
        terms.rawStructure = nil; terms.restrictions = ["Unsupported interest structure: Variabel"]
        let preview = try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: terms, from: MarketDay("2026-02-01"))
        XCTAssertFalse(preview.assessment.supported)
        XCTAssertTrue(preview.payments.isEmpty)
    }
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


extension BondScheduleTests {
    func testPurchaseYieldDiscountsEachEntitledCouponAndDoesNotChangeWithForecastDay() throws {
        let terms = try BondTermsFixtures.fixed()
        // Dirty PV at 8% is 96,123.33994013291; subtract 17/181 of the 1,687.5 coupon for clean cost.
        let trade = try BondTermsFixtures.trade(cost: 96123.33994013291 - 1687.5 * 17 / 181)
        for day in ["2026-02-01", "2026-10-17", "2028-01-01"] {
            let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay(day))
            XCTAssertTrue(preview.assessment.supported, preview.assessment.reasons.joined())
            XCTAssertEqual(try XCTUnwrap(preview.estimatedYTM), 8, accuracy: 1e-8, day)
        }
    }
    func testPurchaseYieldUsesICMAOpeningCouponAndActualPaymentDate() throws {
        var terms = try BondTermsFixtures.fixed(frequency: 2, maturity: "2026-11-30", next: "2026-11-30")
        terms.accrualStart = try MarketDay("2026-05-13"); terms.firstCoupon = terms.maturity
        terms.couponRate = 6.875; terms.roll = .endOfMonth
        terms.checkpointObservedOn = try MarketDay("2026-06-01")
        // ICMA coupon 3,777.4725274725274 plus par, paid 182 days after purchase.
        let trade = BondTrade(id: UUID(), isin: terms.isin, nominal: 100000, cost: 99743.04231213038,
            acquisitionDay: try MarketDay("2026-06-01"), bank: "Fixture")
        let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay("2026-06-01"))
        XCTAssertEqual(try XCTUnwrap(preview.estimatedYTM), 7.5, accuracy: 1e-8)
    }
    func testZeroCouponPurchaseYieldUsesAdjustedRedemptionAndCalendarDays() throws {
        var terms = try BondTermsFixtures.fixed(maturity: "2027-01-01")
        terms.structure = .zero; terms.couponRate = 0; terms.redemptionPercent = 105
        // Jan 1 redemption is paid Jan 4, exactly 365 calendar days after purchase.
        for (cost, expected) in [(100000.0, 5.0), (210000.0, -50.0)] {
            let trade = BondTrade(id: UUID(), isin: terms.isin, nominal: 100000, cost: cost,
                acquisitionDay: try MarketDay("2026-01-04"), bank: "Fixture")
            let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay("2026-01-04"))
            XCTAssertEqual(try XCTUnwrap(preview.estimatedYTM), expected, accuracy: 1e-8)
        }
    }
    func testSameDayEntitledCouponIsOffsetByAccruedInterestPaid() throws {
        var terms = try BondTermsFixtures.fixed(maturity: "2027-01-15")
        terms.couponRate = 10
        let trade = BondTrade(id: UUID(), isin: terms.isin, nominal: 100000, cost: 105000,
            acquisitionDay: try MarketDay("2026-07-15"), bank: "Fixture")
        // Accrued 5,000 offsets the same-day receipt; clean outlay and final receipt are both 105,000.
        let expected = 0.0
        let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay("2026-07-15"))
        XCTAssertEqual(try XCTUnwrap(preview.estimatedYTM), expected, accuracy: 1e-8)
    }
    func testZeroDurationPurchaseHasNoYieldButKeepsRedemptionForecast() throws {
        var terms = try BondTermsFixtures.fixed(maturity: "2027-01-15")
        terms.structure = .zero; terms.couponRate = 0
        let trade = BondTrade(id: UUID(), isin: terms.isin, nominal: 100000, cost: 99000,
            acquisitionDay: try MarketDay("2027-01-15"), bank: "Fixture")
        let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay("2027-01-15"))
        XCTAssertTrue(preview.assessment.supported)
        XCTAssertNil(preview.estimatedYTM)
        XCTAssertEqual(preview.payments.count, 1)
    }
    func testUnknownOpeningCouponCannotProducePurchaseYieldFromOnlyLaterCoupons() throws {
        var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2031-10-03", next: "2026-10-03")
        terms.accrualStart = try MarketDay("2024-04-03")
        terms.checkpointObservedOn = try MarketDay("2026-02-01")
        let trade = BondTrade(id: UUID(), isin: terms.isin, nominal: 100000, cost: 100000,
            acquisitionDay: try MarketDay("2024-05-01"), bank: "Fixture")
        let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay("2026-02-01"))
        XCTAssertTrue(preview.assessment.supported, preview.assessment.reasons.joined())
        XCTAssertFalse(preview.payments.isEmpty)
        XCTAssertNil(preview.estimatedYTM)
        XCTAssertTrue(preview.assessment.warnings.contains { $0.contains("Purchase yield") })
    }
}


extension BondScheduleTests {
    func testQuarterlyPurchaseYieldUsesActualDaysAcrossLeapYearAndDST() throws {
        var terms = try BondTermsFixtures.fixed(frequency: 4, maturity: "2025-02-28", next: "2024-05-28")
        terms.accrualStart = try MarketDay("2024-02-28"); terms.couponRate = 8
        terms.checkpointObservedOn = terms.accrualStart
        let trade = BondTrade(id: UUID(), isin: terms.isin, nominal: 100000, cost: 100000,
            acquisitionDay: try MarketDay("2024-02-28"), bank: "Fixture")
        let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay("2024-02-28"))
        let yield = try XCTUnwrap(preview.estimatedYTM) / 100
        // May28, Aug28, Nov28, Feb28 are 90, 182, 274, 366 calendar days after purchase.
        let price = [(90.0, 2000.0), (182.0, 2000.0), (274.0, 2000.0), (366.0, 102000.0)]
            .reduce(0.0) { $0 + $1.1 / pow(1 + yield, $1.0 / 365) }
        XCTAssertEqual(price, 100000, accuracy: 1e-6)
        XCTAssertEqual(preview.payments.filter { $0.kind == .interest }.count, 4)
    }
}


extension BondScheduleTests {
    func testCleanCarrefourPurchaseAddsAccruedInterestInsteadOfTreatingFullNextCouponAsProfit() throws {
        var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2027-05-04", next: "2026-05-04")
        terms.accrualStart = try MarketDay("2025-05-04"); terms.couponRate = 4.08
        terms.checkpointObservedOn = try MarketDay("2026-04-15")
        let trade = BondTrade(id: UUID(), isin: terms.isin, nominal: 100000, cost: 100750,
            acquisitionDay: try MarketDay("2026-04-15"), bank: "Fixture")
        for day in ["2026-04-15", "2026-10-17", "2028-01-01"] {
            let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay(day))
            XCTAssertTrue(preview.assessment.supported, preview.assessment.reasons.joined())
            // 100,750 clean + 4,080 * 346/365 accrued = 104,617.61643835617 paid.
            XCTAssertEqual(try XCTUnwrap(preview.estimatedYTM), 3.3394097440254678, accuracy: 1e-8)
        }
    }
}
