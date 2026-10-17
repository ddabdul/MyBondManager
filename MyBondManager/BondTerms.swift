import Foundation

enum BondStructure: String, Codable, Equatable, Sendable { case fixed, zero, floating, fixedToFloating, unknown }
enum TermSource: String, Codable, Equatable, Sendable { case ing, assumed, confirmed }
enum CouponRoll: String, Codable, Equatable, Sendable { case dayOfMonth, endOfMonth }
struct BondConventions: Codable, Equatable, Sendable {
    var dayCount = "actualActualICMA"
    var calendar = "TARGET"
    var adjustment = "following"
    var sources: [String: TermSource] = ["dayCount": .assumed, "calendar": .assumed, "adjustment": .assumed]
}
struct BondTerms: Codable, Equatable, Sendable {
    var isin = ""
    var currency: String?
    var structure: BondStructure = .unknown
    var rawStructure: String?
    var frequency: Int?
    var rawFrequency: String?
    var couponRate: Double?
    var maturity: MarketDay?
    var accrualStart: MarketDay?
    var issueDay: MarketDay?
    var nextCoupon: MarketDay?
    var firstCoupon: MarketDay?
    var interestDeferral: Bool?
    var floatingStart: MarketDay?
    var floatingTerms: FloatingBondTerms?
    var verifiedTermsSource: String?
    var checkpointObservedOn: MarketDay?
    var redemptionPercent: Double?
    var callable: Bool?
    var roll: CouponRoll?
    var conventions = BondConventions()
    var confirmedFields: Set<String> = []
    var restrictions: [String] = []
    var collectedAt: Date?
    var approvedAt: Date?
}
struct TermsAssessment: Equatable, Sendable {
    let reasons: [String]
    let warnings: [String]
    var supported: Bool { reasons.isEmpty }
}

extension BondTerms {
    var paymentDeferralWarning: String? {
        interestDeferral == true ? "Payments may be deferred under the instrument terms. Forecasts assume scheduled payment; automatic receipt recording is disabled." : nil
    }
    var fixedStructureOverrideWarning: String? {
        guard structure == .fixed, confirmedFields.contains("structure") else { return nil }
        let markers = ["floating", "variabel", "fixed-to-floating", "Unsupported interest structure: Variabel"]
        guard rawStructure?.localizedCaseInsensitiveContains("variabel") == true ||
              restrictions.contains(where: { markers.contains($0) }) else { return nil }
        return "Manual Fixed override: using the entered rate as constant for every remaining coupon despite the provider's floating-rate classification."
    }
    var unsupportedInterestReason: String? {
        if fixedStructureOverrideWarning != nil { return nil }
        if structure == .fixedToFloating || restrictions.contains("fixed-to-floating") {
            let date = floatingStart.map { " from " + $0.rawValue } ?? ""
            return "Fixed-to-floating interest is not supported. Reference-rate resets" + date + " require a separate schedule."
        }
        if structure == .floating || rawStructure?.localizedCaseInsensitiveContains("variabel") == true || restrictions.contains("floating") || restrictions.contains("variabel") || restrictions.contains("Unsupported interest structure: Variabel") {
            return "Floating-rate interest is not supported. Reference-rate fixings, reset dates and spreads are required."
        }
        return structure == .unknown ? "Interest structure is missing or unsupported." : nil
    }
}

extension BondTerms {
    func preservingSafeguards(from old: BondTerms) -> BondTerms {
        var result = self
        var restrictions = result.restrictions + old.restrictions
        if old.structure == .floating { restrictions.append("floating") }
        if old.structure == .fixedToFloating { restrictions.append("fixed-to-floating") }
        result.restrictions = Array(Set(restrictions)).sorted()
        if old.interestDeferral == true { result.interestDeferral = true }
        if result.firstCoupon == nil, !result.confirmedFields.contains("firstCoupon"), old.verifiedTermsSource != nil {
            result.firstCoupon = old.firstCoupon
        }
        if result.floatingStart == nil { result.floatingStart = old.floatingStart }
        if result.verifiedTermsSource == nil { result.verifiedTermsSource = old.verifiedTermsSource }
        return result
    }
}
