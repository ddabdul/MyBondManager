import Foundation

struct QuantLibPayment: Equatable, Sendable {
    let kind: BondPayment.Kind
    let contractualDay: MarketDay
    let paymentDay: MarketDay
    let amount: Double
    let irregularOpening: Bool
}

struct ForwardObservation: Equatable, Sendable {
    let fixingDay: MarketDay
    let valueDay: MarketDay
    let indexEndDay: MarketDay
    let rate: Double
}
struct CurveCalculationResult: Equatable, Sendable {
    let observations: [ForwardObservation]
    let calibration: CurveCalibrationDiagnostics
}

enum QuantLibBondMath {
    static var version: String { String(cString: MBMQLVersion()) }

    static func following(_ day: MarketDay) throws -> MarketDay { try adjusted(day, modified: false) }
    static func modifiedFollowing(_ day: MarketDay) throws -> MarketDay { try adjusted(day, modified: true) }
    private static func adjusted(_ day: MarketDay, modified: Bool) throws -> MarketDay {
        var output: Int32 = 0
        var error = [CChar](repeating: 0, count: 512)
        let status = error.withUnsafeMutableBufferPointer {
            MBMQLAdjust(encoded(day), modified ? 1 : 0, &output, $0.baseAddress, $0.count)
        }
        guard status == 0 else { throw PortfolioError(String(cString: error)) }
        return try decoded(output)
    }

    static func payments(terms: BondTerms, nominal: Double) throws -> [QuantLibPayment] {
        guard let maturity = terms.maturity, let redemption = terms.redemptionPercent else {
            throw PortfolioError("Contractual maturity or redemption percentage is missing.")
        }
        let zero = terms.structure == .zero
        guard zero || terms.structure == .fixed else { throw PortfolioError("Unsupported interest structure.") }
        guard zero || (terms.accrualStart != nil && terms.couponRate != nil && terms.frequency != nil) else {
            throw PortfolioError("Fixed coupon terms are incomplete.")
        }
        var request = MBMQLRequest(structure: zero ? 1 : 0,
            startDay: zero ? 0 : terms.accrualStart.map(encoded) ?? 0, maturityDay: encoded(maturity),
            firstCouponDay: zero ? 0 : terms.firstCoupon.map(encoded) ?? 0,
            frequency: zero ? 0 : Int32(exactly: terms.frequency ?? 0) ?? 0,
            roll: terms.roll == .endOfMonth ? 1 : (terms.roll == .dayOfMonth ? 0 : 2),
            nominal: nominal, annualRate: zero ? 0 : (terms.couponRate ?? 0) / 100,
            redemptionPercent: redemption)
        var output = [MBMQLPayment](repeating: MBMQLPayment(), count: 1201)
        var count = 0
        var error = [CChar](repeating: 0, count: 512)
        let status = output.withUnsafeMutableBufferPointer { payments in
            error.withUnsafeMutableBufferPointer {
                MBMQLPayments(&request, payments.baseAddress, payments.count, &count, $0.baseAddress, $0.count)
            }
        }
        guard status == 0 else { throw PortfolioError(String(cString: error)) }
        guard (0...output.count).contains(count) else { throw PortfolioError("Native payment count is invalid.") }
        return try output.prefix(count).map { payment in
            guard payment.kind == 0 || payment.kind == 1, payment.amount.isFinite else {
                throw PortfolioError("Native payment is invalid.")
            }
            return QuantLibPayment(kind: payment.kind == 0 ? .interest : .maturity,
                contractualDay: try decoded(payment.contractualDay), paymentDay: try decoded(payment.paymentDay),
                amount: payment.amount, irregularOpening: payment.irregularOpening != 0)
        }
    }

    static func forwards(quotes: CurveMarketQuotes, fixingDays: [MarketDay]) throws -> CurveCalculationResult {
        guard fixingDays.count <= 1201 else { throw PortfolioError("Too many forward probes.") }
        let swaps = try quotes.swaps.map { quote -> MBMQLSwapQuote in
            guard let years = Int32(exactly: quote.years) else { throw PortfolioError("Swap maturity is out of range.") }
            return MBMQLSwapQuote(years: years, rate: quote.rate)
        }
        guard let tenor = Int32(exactly: quotes.indexTenorMonths) else { throw PortfolioError("Index tenor is out of range.") }
        let probes = fixingDays.map { MBMQLForwardProbe(fixingDay: encoded($0)) }
        var output = [MBMQLForwardResult](repeating: MBMQLForwardResult(), count: max(1, probes.count))
        var count = 0
        var diagnostics = MBMQLCurveDiagnostics()
        var error = [CChar](repeating: 0, count: 512)
        let status = swaps.withUnsafeBufferPointer { swaps in
            var request = MBMQLCurveRequest(quoteDay: encoded(quotes.quoteDay), indexTenorMonths: tenor,
                depositRate: quotes.depositRate, swaps: swaps.baseAddress, swapCount: swaps.count)
            return probes.withUnsafeBufferPointer { probes in
                output.withUnsafeMutableBufferPointer { output in
                    error.withUnsafeMutableBufferPointer { error in
                        MBMQLCurveForwards(&request, probes.baseAddress, probes.count, output.baseAddress,
                            output.count, &count, &diagnostics, error.baseAddress, error.count)
                    }
                }
            }
        }
        guard status == 0 else { throw PortfolioError(String(cString: error)) }
        guard count == probes.count else { throw PortfolioError("Invalid native forward count.") }
        let observations = try output.prefix(count).map {
            ForwardObservation(fixingDay: try decoded($0.fixingDay), valueDay: try decoded($0.valueDay),
                indexEndDay: try decoded($0.indexEndDay), rate: $0.rate)
        }
        return CurveCalculationResult(observations: observations, calibration: CurveCalibrationDiagnostics(
            quantLibVersion: version, maxDepositResidual: diagnostics.maxDepositResidual,
            maxSwapResidual: diagnostics.maxSwapResidual, lastCurveDay: try decoded(diagnostics.lastCurveDay)))
    }

    static func encoded(_ day: MarketDay) -> Int32 {
        Int32(day.year * 10000 + day.month * 100 + day.day)
    }

    static func decoded(_ value: Int32) throws -> MarketDay {
        try MarketDay(String(format: "%04d-%02d-%02d", value / 10000, value / 100 % 100, value % 100))
    }
}
