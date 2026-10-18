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
    var rateSource: CouponRateSource? = nil
    var fixingDay: MarketDay? = nil
    var indexRate: Double? = nil
    var effectiveCouponRate: Double? = nil
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
    static let previousYieldMethod = "annualEffectiveActual365Fixed"
    static let yieldMethod = "annualEffectiveActual365FixedCleanPrice"
    static func preview(trade: BondTrade, terms: BondTerms, from: MarketDay, context: ProjectionContext? = nil) throws -> BondSchedulePreview {
        guard trade.nominal.isFinite, trade.nominal > 0, trade.cost.isFinite, trade.cost > 0 else {
            throw PortfolioError("Nominal and acquisition cost must be finite positive amounts.")
        }
        let floating = [.floating, .fixedToFloating].contains(terms.structure)
        let pureFloating = terms.structure == .floating
        var reasons: [String] = []
        func require(_ condition: Bool, _ reason: String) { if !condition { reasons.append(reason) } }
        require(!trade.isin.isEmpty && ETFPurchase.normalizedISIN(terms.isin) == ETFPurchase.normalizedISIN(trade.isin), "Instrument identity does not match the holding.")
        require(terms.currency == "EUR", "Only EUR payments are supported.")
        if !floating, let issue = terms.unsupportedInterestReason { reasons.append(issue) }
        require(terms.callable != nil, "Callable status is missing.")
        let structuralMarkers = ["floating", "variabel", "fixed-to-floating", "Unsupported interest structure: Variabel"]
        let restrictions = terms.restrictions.filter { !structuralMarkers.contains($0) }
        require(restrictions.isEmpty, "Unsupported terms: " + restrictions.joined(separator: ", "))
        require(pureFloating || terms.couponRate.map { $0.isFinite && $0 >= 0 } == true, "Coupon rate is missing or invalid.")
        require(terms.redemptionPercent.map { $0.isFinite && $0 > 0 } == true, "Redemption percentage is missing or invalid.")
        require(terms.maturity != nil, "Contractual maturity is missing.")
        require(terms.conventions.calendar == "TARGET" && (pureFloating || (terms.conventions.dayCount == "actualActualICMA" && terms.conventions.adjustment == "following")), "Selected conventions are not supported.")
        if let maturity = terms.maturity { require(maturity >= trade.acquisitionDay, "Maturity precedes acquisition.") }
        if terms.structure == .zero { require(terms.couponRate == 0, "Zero-coupon structure contradicts the coupon rate.") }
        var warnings = terms.callable == true ? ["Early redemption is not modeled."] : []
        if let warning = terms.paymentDeferralWarning { warnings.append(warning) }
        if let warning = terms.fixedStructureOverrideWarning { warnings.append(warning) }
        func unsupported() -> BondSchedulePreview {
            BondSchedulePreview(assessment: TermsAssessment(reasons: reasons, warnings: warnings), payments: [], flows: [], redemptionDay: nil, estimatedYTM: nil)
        }
        guard reasons.isEmpty, let maturity = terms.maturity,
              let redemptionPercent = terms.redemptionPercent else { return unsupported() }
        if floating {
            guard let context else { reasons.append("Select a frozen market snapshot and valuation day."); return unsupported() }
            do {
                let days = try QuantLibBondMath.floatingCouponDays(terms: terms)
                guard let observed = terms.checkpointObservedOn, let supplied = terms.nextCoupon else {
                    reasons.append("Next coupon checkpoint is missing."); return unsupported()
                }
                let expected = days.first { $0 >= observed }
                guard expected == supplied else {
                    reasons.append("Next coupon contradicts the contractual schedule: supplied \(supplied.rawValue), expected \(expected?.rawValue ?? "none"), observed \(observed.rawValue)."); return unsupported()
                }
                let values = try QuantLibBondMath.floatingPayments(terms: terms, nominal: trade.nominal, context: context,
                    window: FloatingCalculationWindow(acquisitionDay: trade.acquisitionDay, paymentFrom: from))
                let payments = values.map { value in
                    let p = value.payment
                    return BondPayment(kind: p.kind, contractualDay: p.contractualDay, paymentDay: p.paymentDay,
                        amount: p.amount, identity: "\(trade.id.uuidString)|\(p.kind == .interest ? "interest" : "maturity")|\(p.contractualDay.rawValue)",
                        rateSource: value.rateSource, fixingDay: value.fixingDay, indexRate: value.indexRate, effectiveCouponRate: value.effectiveCouponRate)
                }
                var flows = payments.filter { $0.kind == .interest }.map {
                    ProjectedFlow(contractualDay: $0.contractualDay, paymentDay: $0.paymentDay, amount: $0.amount, nature: .interest, eventIdentity: $0.identity)
                }
                if let redemption = payments.first(where: { $0.kind == .maturity }) {
                    let delta = redemption.amount - trade.cost
                    flows.append(ProjectedFlow(contractualDay: maturity, paymentDay: redemption.paymentDay,
                        amount: delta > 0 ? trade.cost : redemption.amount, nature: .principal, eventIdentity: redemption.identity))
                    if delta != 0 { flows.append(ProjectedFlow(contractualDay: maturity, paymentDay: redemption.paymentDay,
                        amount: delta, nature: delta > 0 ? .capitalGains : .capitalLoss, eventIdentity: nil)) }
                    flows.append(ProjectedFlow(contractualDay: maturity, paymentDay: redemption.paymentDay,
                        amount: payments.filter { $0.kind == .interest }.reduce(delta) { $0 + $1.amount }, nature: .expectedProfit, eventIdentity: nil))
                }
                guard flows.allSatisfy({ $0.amount.isFinite }) else { throw PortfolioError("Calculated floating return is out of range.") }
                warnings.append("Frozen valuation \(context.valuationDay.rawValue); market quotes \(context.marketData.payload.quotes.quoteDay.rawValue). Future reset rates are projected.")
                if try MarketDataStore.isStale(quoteDay: context.marketData.payload.quotes.quoteDay, on: context.valuationDay) {
                    warnings.append("Market quotes are more than two TARGET business days old.")
                }
                let redemptionDay = try terms.floatingTerms?.paymentAdjustment == .modifiedFollowing
                    ? QuantLibBondMath.modifiedFollowing(maturity) : QuantLibBondMath.following(maturity)
                return BondSchedulePreview(assessment: TermsAssessment(reasons: [], warnings: warnings), payments: payments,
                    flows: flows, redemptionDay: redemptionDay, estimatedYTM: nil)
            } catch let failure as PortfolioError { reasons.append(failure.localizedDescription); return unsupported() }
            catch let failure as MarketDataError { reasons.append(failure.localizedDescription); return unsupported() }
        }
        let dates = [terms.maturity, terms.accrualStart, terms.firstCoupon, terms.nextCoupon,
                     terms.checkpointObservedOn, Optional(trade.acquisitionDay), Optional(from)].compactMap { $0 }
        guard dates.allSatisfy({ (1901...2199).contains($0.year) }) else {
            reasons.append("QuantLib dates must be in 1901...2199."); return unsupported()
        }
        var calculated: [QuantLibPayment]
        do { calculated = try QuantLibBondMath.payments(terms: terms, nominal: trade.nominal) }
        catch let failure as PortfolioError {
            reasons.append(failure.localizedDescription); return unsupported()
        }
        var completePurchaseSchedule = true
        if terms.structure == .fixed {
            guard let checkpoint = terms.nextCoupon, let observed = terms.checkpointObservedOn else {
                reasons.append("Next coupon checkpoint is missing."); return unsupported()
            }
            let coupons = calculated.filter { $0.kind == .interest }
            let expected = coupons.first { $0.contractualDay >= observed }?.contractualDay
            guard expected == checkpoint else {
                reasons.append("Next coupon contradicts the contractual schedule: supplied \(checkpoint.rawValue), expected \(expected?.rawValue ?? "none"), observed \(observed.rawValue)."); return unsupported()
            }
            if coupons.first?.irregularOpening == true {
                if terms.firstCoupon != nil {
                    warnings.append("Opening coupon is prorated using Actual/Actual (ICMA) reference periods.")
                } else {
                    let opening = Array(coupons.prefix(2))
                    guard coupons.count > 2, checkpoint >= coupons[2].contractualDay,
                          !opening.contains(where: { $0.contractualDay >= trade.acquisitionDay && $0.paymentDay >= from }) else {
                        reasons.append("Irregular opening coupon needs a confirmed first-coupon date for Actual/Actual (ICMA) calculation."); return unsupported()
                    }
                    completePurchaseSchedule = !opening.contains { $0.contractualDay >= trade.acquisitionDay }
                    let excluded = Set(opening.map(\.contractualDay))
                    calculated.removeAll { $0.kind == .interest && excluded.contains($0.contractualDay) }
                    warnings.append("Historical opening coupon periods are excluded; only the remaining regular coupons are calculated.")
                }
            }
        }
        let redemption = trade.nominal * redemptionPercent / 100
        guard redemption.isFinite else { throw PortfolioError("Calculated payment amount is out of range.") }
        var payments: [BondPayment] = []
        var flows: [ProjectedFlow] = []
        for coupon in calculated where coupon.kind == .interest && coupon.contractualDay >= trade.acquisitionDay && coupon.paymentDay >= from {
            let identity = "\(trade.id.uuidString)|interest|\(coupon.contractualDay.rawValue)"
            payments.append(BondPayment(kind: .interest, contractualDay: coupon.contractualDay,
                paymentDay: coupon.paymentDay, amount: coupon.amount, identity: identity))
            flows.append(ProjectedFlow(contractualDay: coupon.contractualDay, paymentDay: coupon.paymentDay,
                amount: coupon.amount, nature: .interest, eventIdentity: identity))
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
        var estimate: Double?
        if completePurchaseSchedule {
            let accrued = try QuantLibBondMath.accruedInterest(terms: terms, nominal: trade.nominal, acquisitionDay: trade.acquisitionDay)
            estimate = try QuantLibBondMath.purchaseYield(payments: calculated, acquisitionDay: trade.acquisitionDay, cost: trade.cost + accrued)
        }
        if !completePurchaseSchedule {
            warnings.append("Purchase yield is unavailable because opening coupons entitled at acquisition are unknown.")
        }
        guard flows.allSatisfy({ $0.amount.isFinite }) else { throw PortfolioError("Calculated return is out of range.") }
        return BondSchedulePreview(assessment: TermsAssessment(reasons: [], warnings: warnings), payments: payments, flows: flows, redemptionDay: paid, estimatedYTM: estimate)
    }
}
