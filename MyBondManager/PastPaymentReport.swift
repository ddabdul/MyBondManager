import Foundation
import CoreData

struct PastPaymentReport: Codable, Sendable {
    struct Payment: Codable, Identifiable, Sendable {
        enum PaymentType: String, Codable, Sendable { case coupon, redemption }
        let id: String
        let purchaseID: UUID
        let isin: String
        let name: String
        let bank: String
        let paymentDay: MarketDay
        let contractualDay: MarketDay
        let type: PaymentType
        let amount: Double
        let rateSource: CouponRateSource?
        let conditional: Bool
        let warnings: [String]
    }
    let version: Int
    let basis: String
    let description: String
    let currency: String
    let generatedAt: Date
    let from: MarketDay
    let through: MarketDay
    let bank: String
    let search: String
    let paymentType: String?
    let coupons: Double
    let redemptions: Double
    let total: Double
    let isComplete: Bool
    let payments: [Payment]
    let excludedHoldings: [CashFlowCalendarData.Exclusion]

    static func build(bonds: [BondEntity], from: MarketDay, through: MarketDay,
                      bank: String = "All", search: String = "", kind: BondPayment.Kind? = nil,
                      now: Date = Date()) throws -> Self {
        guard from <= through else { throw PortfolioError("The From date must be on or before the To date.") }
        guard through < MarketDay(date: now) else { throw PortfolioError("Choose two past dates; the To date must be before today.") }
        guard from.year >= 1901, through.year <= 2199 else { throw PortfolioError("Choose dates between 1901 and 2199.") }
        var candidates: [BondEntity] = []
        var exclusions: [CashFlowCalendarData.Exclusion] = []
        for bond in bonds where (bank == "All" || bond.depotBank == bank)
            && (search.isEmpty || bond.name.range(of: search, options: [.caseInsensitive, .diacriticInsensitive]) != nil) {
            guard BondEligibility.contractualMaturityDay(bond) >= MarketDay(date: now) else { continue }
            do {
                guard try BondTermsStore.trade(bond).acquisitionDay <= through else { continue }
                candidates.append(bond)
            } catch { exclusions.append(.init(id: bond.id, name: bond.name, reason: error.localizedDescription)) }
        }
        let data = CashFlowCalendarData.build(bonds: candidates, from: from, through: through,
            kind: kind, includeInactiveExclusions: true)
        exclusions.append(contentsOf: data.exclusions.map { exclusion in
            guard let holding = candidates.first(where: { $0.id == exclusion.id }) else { return exclusion }
            let isin = ETFPurchase.normalizedISIN(holding.isin)
            let reusable = bonds.contains { sibling in
                sibling.id != holding.id && ETFPurchase.normalizedISIN(sibling.isin) == isin
                    && BondTermsStore.isReady(sibling)
            }
            return .init(id: exclusion.id, name: exclusion.name, reason: exclusion.reason + (reusable
                ? " Another purchase has usable approved terms. Choose Reuse approved terms in the review; each purchase will be validated separately." : ""))
        })
        let values = data.totals
        guard values.total.isFinite else { throw PortfolioError("The payment total is out of range.") }
        return Self(version: 1, basis: "expected",
            description: "Reconstructed from current approved terms and retained holdings, excluding bonds that matured before the report generation day. Not confirmation of bank receipt. Deleted holdings and prior versions of terms are not available.",
            currency: "EUR", generatedAt: now, from: from, through: through, bank: bank, search: search,
            paymentType: kind.map { $0 == .interest ? "coupon" : "redemption" },
            coupons: values.coupons, redemptions: values.repayments, total: values.total, isComplete: exclusions.isEmpty,
            payments: data.receipts.map {
                Payment(id: $0.id, purchaseID: $0.purchaseID, isin: $0.isin, name: $0.name, bank: $0.bank,
                    paymentDay: $0.paymentDay, contractualDay: $0.contractualDay,
                    type: $0.kind == .interest ? .coupon : .redemption, amount: $0.amount,
                    rateSource: $0.rateSource, conditional: $0.conditional, warnings: $0.warnings)
            }, excludedHoldings: exclusions.sorted { ($0.name, $0.id.uuidString) < ($1.name, $1.id.uuidString) })
    }

    func json() throws -> Data {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }
}
