import Foundation

enum FloatingResetTiming: String, Codable, Sendable { case inAdvance, inArrears }
enum FloatingAccrualAdjustment: String, Codable, Sendable { case unadjusted, modifiedFollowing }
enum FloatingPaymentAdjustment: String, Codable, Sendable { case following, modifiedFollowing }
enum FloatingDayCount: String, Codable, Sendable { case actual360, actual365Fixed, actualActualICMA }
enum FloatingResetAnchor: String, Codable, Sendable { case contractualAccrualStart, adjustedAccrualStart }
enum FloatingPayoff: String, Codable, Sendable { case plain, cappedOrFloored, other }

struct FloatingBondTerms: Codable, Equatable, Sendable {
    var indexTenorMonths: Int?
    var spreadBps: Double?
    var gearing: Double?
    var resetLagTARGETDays: Int?
    var resetTiming: FloatingResetTiming?
    var resetAnchor: FloatingResetAnchor?
    var dayCount: FloatingDayCount?
    var frequency: Int?
    var firstFloatingCoupon: MarketDay?
    var accrualAdjustment: FloatingAccrualAdjustment?
    var paymentAdjustment: FloatingPaymentAdjustment?
    var roll: CouponRoll?
    var payoff: FloatingPayoff?
    var confirmedFields: Set<String> = []

    func assessment(structure: BondStructure, transition: MarketDay?, accrualStart: MarketDay?, maturity: MarketDay?) -> TermsAssessment {
        var reasons: [String] = []
        func require(_ present: Bool, _ field: String, _ label: String) {
            if !present { reasons.append("Floating \(label) is required.") }
            else if !confirmedFields.contains(field) { reasons.append("Confirm floating \(label).") }
        }
        require(indexTenorMonths != nil, "indexTenorMonths", "index tenor")
        require(spreadBps != nil, "spreadBps", "spread in basis points")
        require(gearing != nil, "gearing", "gearing")
        require(resetLagTARGETDays != nil, "resetLagTARGETDays", "reset lag in TARGET days")
        require(resetTiming != nil, "resetTiming", "reset timing")
        require(resetAnchor != nil, "resetAnchor", "reset anchor")
        require(dayCount != nil, "dayCount", "day count")
        require(frequency != nil, "frequency", "coupon frequency")
        require(accrualAdjustment != nil, "accrualAdjustment", "accrual adjustment")
        require(paymentAdjustment != nil, "paymentAdjustment", "payment adjustment")
        require(roll != nil, "roll", "coupon roll")
        require(payoff != nil, "payoff", "payoff")
        if let tenor = indexTenorMonths, ![1, 3, 6, 12].contains(tenor) {
            reasons.append("Floating index tenor must be 1, 3, 6 or 12 months.")
        }
        if let spread = spreadBps, !spread.isFinite { reasons.append("Floating spread must be finite.") }
        if let gearing, !gearing.isFinite || gearing <= 0 { reasons.append("Floating gearing must be finite and greater than zero.") }
        if let lag = resetLagTARGETDays, !(0...10).contains(lag) { reasons.append("Floating reset lag must be between 0 and 10 TARGET days.") }
        if let frequency, ![1, 2, 4, 12].contains(frequency) { reasons.append("Floating coupon frequency must be 1, 2, 4 or 12 per year.") }
        if let timing = resetTiming, timing != .inAdvance { reasons.append("Floating resets in arrears are not supported.") }
        if let dayCount, dayCount != .actual360 { reasons.append("Only Actual/360 floating day count is supported.") }
        if let payoff, payoff != .plain { reasons.append("Only plain floating coupons without caps or floors are supported.") }
        if confirmedFields.contains("firstFloatingCoupon"), firstFloatingCoupon == nil {
            reasons.append("Enter a valid explicit first floating coupon date, or clear the field to use the regular schedule.")
        }
        if structure == .fixedToFloating {
            if let transition, let accrualStart, let maturity {
                if !(accrualStart < transition && transition < maturity) {
                    reasons.append("Fixed-to-floating transition must be strictly after accrual start and before maturity.")
                }
            } else {
                reasons.append("Fixed-to-floating transition, accrual start and maturity are required.")
            }
        }
        return TermsAssessment(reasons: reasons, warnings: [])
    }
}

extension FloatingBondTerms {
    init(from decoder: Decoder) throws {
        let box = try decoder.container(keyedBy: CodingKeys.self)
        indexTenorMonths = try box.decodeIfPresent(Int.self, forKey: .indexTenorMonths)
        spreadBps = try box.decodeIfPresent(Double.self, forKey: .spreadBps)
        gearing = try box.decodeIfPresent(Double.self, forKey: .gearing)
        resetLagTARGETDays = try box.decodeIfPresent(Int.self, forKey: .resetLagTARGETDays)
        resetTiming = try box.decodeIfPresent(FloatingResetTiming.self, forKey: .resetTiming)
        resetAnchor = try box.decodeIfPresent(FloatingResetAnchor.self, forKey: .resetAnchor)
        dayCount = try box.decodeIfPresent(FloatingDayCount.self, forKey: .dayCount)
        frequency = try box.decodeIfPresent(Int.self, forKey: .frequency)
        firstFloatingCoupon = try box.decodeIfPresent(MarketDay.self, forKey: .firstFloatingCoupon)
        accrualAdjustment = try box.decodeIfPresent(FloatingAccrualAdjustment.self, forKey: .accrualAdjustment)
        paymentAdjustment = try box.decodeIfPresent(FloatingPaymentAdjustment.self, forKey: .paymentAdjustment)
        roll = try box.decodeIfPresent(CouponRoll.self, forKey: .roll)
        payoff = try box.decodeIfPresent(FloatingPayoff.self, forKey: .payoff)
        confirmedFields = try box.decodeIfPresent(Set<String>.self, forKey: .confirmedFields) ?? []
    }
}
