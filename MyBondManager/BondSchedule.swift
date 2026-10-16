import Foundation

struct BondTrade: Codable, Equatable, Sendable {
    let id: UUID
    let isin: String
    let nominal: Double
    let cost: Double
    let acquisitionDay: MarketDay
    let bank: String
}
struct BondPayment: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Equatable, Sendable { case interest, maturity }
    let kind: Kind
    let contractualDay: MarketDay
    let paymentDay: MarketDay
    let amount: Double
    let identity: String
}
struct ProjectedFlow: Codable, Equatable, Sendable {
    let contractualDay: MarketDay
    let paymentDay: MarketDay
    let amount: Double
    let nature: CashFlowEntity.Nature
    let eventIdentity: String?
}
struct BondSchedulePreview: Equatable, Sendable {
    let assessment: TermsAssessment
    let payments: [BondPayment]
    let flows: [ProjectedFlow]
    let redemptionDay: MarketDay?
    let estimatedYTM: Double?
}
enum BondSchedule {
    static func preview(trade: BondTrade, terms: BondTerms, from: MarketDay) throws -> BondSchedulePreview {
        guard trade.nominal.isFinite, trade.nominal > 0, trade.cost.isFinite, trade.cost > 0 else {
            throw PortfolioError("Nominal and acquisition cost must be finite positive amounts.")
        }
        var reasons: [String] = []
        func require(_ condition: Bool, _ reason: String) { if !condition { reasons.append(reason) } }
        require(!trade.isin.isEmpty && ETFPurchase.normalizedISIN(terms.isin) == ETFPurchase.normalizedISIN(trade.isin), "Instrument identity does not match the holding.")
        require(terms.currency == "EUR", "Only EUR payments are supported.")
        require(terms.structure == .fixed || terms.structure == .zero, "Interest structure is missing or unsupported.")
        require(terms.callable != nil, "Callable status is missing.")
        require(terms.restrictions.isEmpty, "Unsupported terms: " + terms.restrictions.joined(separator: ", "))
        require(terms.couponRate.map { $0.isFinite && $0 >= 0 } == true, "Coupon rate is missing or invalid.")
        require(terms.redemptionPercent.map { $0.isFinite && $0 > 0 } == true, "Redemption percentage is missing or invalid.")
        require(terms.maturity != nil, "Contractual maturity is missing.")
        require(terms.conventions.dayCount == "actualActualICMA" && terms.conventions.calendar == "TARGET" && terms.conventions.adjustment == "following", "Selected conventions are not supported.")
        if let maturity = terms.maturity { require(maturity >= trade.acquisitionDay, "Maturity precedes acquisition.") }
        if terms.structure == .zero { require(terms.couponRate == 0, "Zero-coupon structure contradicts the coupon rate.") }
        let warnings = terms.callable == true ? ["Early redemption is not modeled."] : []
        func unsupported() -> BondSchedulePreview {
            BondSchedulePreview(assessment: TermsAssessment(reasons: reasons, warnings: warnings), payments: [], flows: [], redemptionDay: nil, estimatedYTM: nil)
        }
        guard reasons.isEmpty, let maturity = terms.maturity, let rate = terms.couponRate,
              let redemptionPercent = terms.redemptionPercent else { return unsupported() }
        var couponDays: [MarketDay] = []
        if terms.structure == .fixed {
            guard let frequency = terms.frequency, [1,2,4].contains(frequency) else {
                reasons.append("Coupon frequency is missing or unsupported."); return unsupported()
            }
            guard let start = terms.accrualStart, start < maturity else {
                reasons.append("Accrual start is missing or inconsistent."); return unsupported()
            }
            guard let checkpoint = terms.nextCoupon, let observed = terms.checkpointObservedOn else {
                reasons.append("Next coupon checkpoint is missing."); return unsupported()
            }
            var reachedStart = false
            for index in 0..<1200 {
                let day = try maturity.addingMonths(-index * (12 / frequency), anchorDay: maturity.day, endOfMonth: terms.roll == .endOfMonth)
                if terms.roll == nil, day >= start,
                   maturity.day == MarketDay.calendar.range(of: .day, in: .month, for: maturity.instant)?.count {
                    let endRoll = try maturity.addingMonths(-index * (12 / frequency), anchorDay: maturity.day, endOfMonth: true)
                    if day != endRoll { reasons.append("Confirm the coupon month-end roll."); return unsupported() }
                }
                if day == start { reachedStart = true; break }
                if day < start { break }
                couponDays.append(day)
            }
            guard reachedStart else { reasons.append("Irregular accrual period or schedule exceeds supported range."); return unsupported() }
            couponDays.reverse()
            guard couponDays.first(where: { $0 >= observed }) == checkpoint else {
                reasons.append("Next coupon contradicts the contractual schedule."); return unsupported()
            }
        }
        let redemption = trade.nominal * redemptionPercent / 100
        let coupon = terms.structure == .fixed ? trade.nominal * rate / 100 / Double(terms.frequency!) : 0
        guard redemption.isFinite, coupon.isFinite else { throw PortfolioError("Calculated payment amount is out of range.") }
        var payments: [BondPayment] = []
        var flows: [ProjectedFlow] = []
        for contractual in couponDays where contractual >= trade.acquisitionDay {
            let paid = try TargetCalendar.following(contractual)
            guard paid >= from else { continue }
            let identity = "\(trade.id.uuidString)|interest|\(contractual.rawValue)"
            payments.append(BondPayment(kind: .interest, contractualDay: contractual, paymentDay: paid, amount: coupon, identity: identity))
            flows.append(ProjectedFlow(contractualDay: contractual, paymentDay: paid, amount: coupon, nature: .interest, eventIdentity: identity))
        }
        let paid = try TargetCalendar.following(maturity)
        let delta = redemption - trade.cost
        if paid >= from {
            let identity = "\(trade.id.uuidString)|maturity|\(maturity.rawValue)"
            payments.append(BondPayment(kind: .maturity, contractualDay: maturity, paymentDay: paid, amount: redemption, identity: identity))
            flows.append(ProjectedFlow(contractualDay: maturity, paymentDay: paid, amount: delta > 0 ? trade.cost : redemption, nature: .principal, eventIdentity: identity))
            if delta != 0 { flows.append(ProjectedFlow(contractualDay: maturity, paymentDay: paid, amount: delta, nature: delta > 0 ? .capitalGains : .capitalLoss, eventIdentity: nil)) }
            let interest = payments.filter { $0.kind == .interest }.reduce(0) { $0 + $1.amount }
            flows.append(ProjectedFlow(contractualDay: maturity, paymentDay: paid, amount: interest + delta, nature: .expectedProfit, eventIdentity: nil))
        }
        let years = maturity.instant.timeIntervalSince(trade.acquisitionDay.instant) / (365 * 86400)
        let estimate: Double? = years > 0 ? ((trade.nominal * rate / 100 + delta / years) / ((redemption + trade.cost) / 2)) * 100 : nil
        guard estimate?.isFinite != false, flows.allSatisfy({ $0.amount.isFinite }) else { throw PortfolioError("Calculated return is out of range.") }
        return BondSchedulePreview(assessment: TermsAssessment(reasons: [], warnings: warnings), payments: payments, flows: flows, redemptionDay: paid, estimatedYTM: estimate)
    }
}
