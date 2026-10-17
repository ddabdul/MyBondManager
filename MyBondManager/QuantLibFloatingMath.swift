import Foundation

enum CouponRateSource: String, Codable, Sendable { case fixed, publishedFixing, projected }
struct QuantLibFloatingPayment: Equatable, Sendable {
    let payment: QuantLibPayment
    let rateSource: CouponRateSource
    let fixingDay: MarketDay?
    let indexRate: Double?
    let effectiveCouponRate: Double?
}

extension QuantLibBondMath {
    private static func floatingRequest(terms: BondTerms, nominal: Double,
        context: ProjectionContext? = nil, window: FloatingCalculationWindow? = nil) throws -> MBMQLFloatingRequest {
        guard [.floating, .fixedToFloating].contains(terms.structure), let floating = terms.floatingTerms,
              let start = terms.accrualStart, let maturity = terms.maturity, let redemption = terms.redemptionPercent else {
            throw PortfolioError("Floating instrument terms are incomplete.")
        }
        let assessment = floating.assessment(structure: terms.structure, transition: terms.floatingStart,
            accrualStart: start, maturity: maturity)
        guard assessment.supported else { throw PortfolioError(assessment.reasons.joined(separator: " ")) }
        let mixed = terms.structure == .fixedToFloating
        guard !mixed || (terms.couponRate != nil && terms.frequency != nil) else { throw PortfolioError("Fixed-phase coupon terms are incomplete.") }
        func integer(_ value: Int?) throws -> Int32 {
            guard let value, let output = Int32(exactly: value) else { throw PortfolioError("Floating numeric contract term is out of range.") }
            return output
        }
        return try MBMQLFloatingRequest(startDay: encoded(start), maturityDay: encoded(maturity),
            firstCouponDay: mixed ? terms.firstCoupon.map(encoded) ?? 0 : 0,
            transitionDay: mixed ? terms.floatingStart.map(encoded) ?? 0 : 0,
            firstFloatingCouponDay: floating.firstFloatingCoupon.map(encoded) ?? 0,
            fixedFrequency: mixed ? integer(terms.frequency) : 0, floatingFrequency: integer(floating.frequency),
            indexTenorMonths: integer(floating.indexTenorMonths), resetLagDays: integer(floating.resetLagTARGETDays),
            fixedRoll: terms.roll == .endOfMonth ? 1 : (terms.roll == .dayOfMonth ? 0 : 2),
            floatingRoll: floating.roll == .endOfMonth ? 1 : 0,
            accrualAdjustment: floating.accrualAdjustment == .modifiedFollowing ? 1 : 0,
            paymentAdjustment: floating.paymentAdjustment == .modifiedFollowing ? 1 : 0,
            floatingDayCount: 0, resetAnchor: floating.resetAnchor == .adjustedAccrualStart ? 1 : 0,
            acquisitionDay: encoded(window?.acquisitionDay ?? start), paymentFromDay: encoded(window?.paymentFrom ?? start),
            valuationDay: context.map { encoded($0.valuationDay) } ?? 0, nominal: nominal,
            fixedAnnualRate: mixed ? (terms.couponRate ?? 0) / 100 : 0,
            spreadBps: floating.spreadBps ?? .nan, gearing: floating.gearing ?? .nan, redemptionPercent: redemption)
    }
    static func floatingCouponDays(terms: BondTerms) throws -> [MarketDay] {
        var request = try floatingRequest(terms: terms, nominal: 1)
        var days = [Int32](repeating: 0, count: 1200), count = 0
        var error = [CChar](repeating: 0, count: 512)
        let status = days.withUnsafeMutableBufferPointer { output in
            error.withUnsafeMutableBufferPointer { MBMQLFloatingCouponDays(&request, output.baseAddress, output.count, &count, $0.baseAddress, $0.count) }
        }
        guard status == 0 else { throw PortfolioError(String(cString: error)) }
        guard (0...days.count).contains(count) else { throw PortfolioError("Invalid floating date count.") }
        return try days.prefix(count).map(decoded)
    }
    static func floatingPayments(terms: BondTerms, nominal: Double, context: ProjectionContext,
        window: FloatingCalculationWindow) throws -> [QuantLibFloatingPayment] {
        try context.validate()
        var request = try floatingRequest(terms: terms, nominal: nominal, context: context, window: window)
        let quotes = context.marketData.payload.quotes
        guard quotes.indexTenorMonths == terms.floatingTerms?.indexTenorMonths else { throw PortfolioError("Market snapshot index tenor differs from the instrument.") }
        let swaps = try quotes.swaps.map { quote -> MBMQLSwapQuote in
            guard let years = Int32(exactly: quote.years) else { throw PortfolioError("Swap maturity is out of range.") }
            return MBMQLSwapQuote(years: years, rate: quote.rate)
        }
        let fixings = context.marketData.payload.historicalFixings.map { MBMQLPublishedFixing(day: encoded($0.day), rate: $0.rate) }
        var output = [MBMQLFloatingPayment](repeating: MBMQLFloatingPayment(), count: 1201), count = 0
        var error = [CChar](repeating: 0, count: 512)
        let status = swaps.withUnsafeBufferPointer { swaps in
            var curve = MBMQLCurveRequest(quoteDay: encoded(quotes.quoteDay), indexTenorMonths: Int32(quotes.indexTenorMonths),
                depositRate: quotes.depositRate, swaps: swaps.baseAddress, swapCount: swaps.count)
            return fixings.withUnsafeBufferPointer { fixings in
                output.withUnsafeMutableBufferPointer { output in
                    error.withUnsafeMutableBufferPointer { error in
                        MBMQLFloatingPayments(&request, &curve, fixings.baseAddress, fixings.count,
                            output.baseAddress, output.count, &count, error.baseAddress, error.count)
                    }
                }
            }
        }
        guard status == 0 else { throw PortfolioError(String(cString: error)) }
        guard (0...output.count).contains(count) else { throw PortfolioError("Invalid floating payment count.") }
        return try output.prefix(count).map { value in
            guard [0,1].contains(value.payment.kind), [0,1,2].contains(value.rateSource), value.payment.amount.isFinite else {
                throw PortfolioError("Invalid floating payment result.")
            }
            let source: CouponRateSource = value.rateSource == 0 ? .fixed : (value.rateSource == 1 ? .publishedFixing : .projected)
            return QuantLibFloatingPayment(payment: QuantLibPayment(kind: value.payment.kind == 0 ? .interest : .maturity,
                contractualDay: try decoded(value.payment.contractualDay), paymentDay: try decoded(value.payment.paymentDay),
                amount: value.payment.amount, irregularOpening: value.payment.irregularOpening != 0), rateSource: source,
                fixingDay: value.fixingDay == 0 ? nil : try decoded(value.fixingDay),
                indexRate: value.fixingDay == 0 ? nil : value.indexRate,
                effectiveCouponRate: value.payment.kind == 1 ? nil : value.effectiveCouponRate)
        }
    }
}
