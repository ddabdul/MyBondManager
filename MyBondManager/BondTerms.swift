import Foundation

enum BondStructure: String, Codable, Equatable, Sendable { case fixed, zero, unknown }
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
