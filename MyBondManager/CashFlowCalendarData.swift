import Foundation

struct CalendarReceipt: Identifiable, Sendable {
    let id: String
    let purchaseID: UUID
    let isin: String
    let name: String
    let bank: String
    let acquisitionDay: MarketDay
    let nominal: Double
    let cost: Double
    let paymentDay: MarketDay
    let contractualDay: MarketDay
    let kind: BondPayment.Kind
    let amount: Double
    let rateSource: CouponRateSource?
    let conditional: Bool
    let warnings: [String]
}

struct CalendarTotals {
    let coupons: Double
    let repayments: Double
    var total: Double { coupons + repayments }
    init(_ receipts: [CalendarReceipt]) {
        coupons = receipts.filter { $0.kind == .interest }.reduce(0) { $0 + $1.amount }
        repayments = receipts.filter { $0.kind == .maturity }.reduce(0) { $0 + $1.amount }
    }
}

struct CashFlowCalendarData: Sendable {
    struct Exclusion: Identifiable, Codable, Sendable {
        let id: UUID
        let name: String
        let reason: String
    }
    let receipts: [CalendarReceipt]
    let exclusions: [Exclusion]
    var totals: CalendarTotals { CalendarTotals(receipts) }
    var years: [Int] { Set(receipts.map { $0.paymentDay.year }).sorted() }

    static func build(bonds: [BondEntity], from: MarketDay, through: MarketDay,
                      kind: BondPayment.Kind? = nil, includeInactiveExclusions: Bool = false) -> Self {
        var receipts: [CalendarReceipt] = []
        var exclusions: [Exclusion] = []
        for bond in bonds {
            do {
                guard let preview = try BondTermsStore.validatedPreview(bond, from: from) else {
                    if includeInactiveExclusions || BondEligibility.isActive(bond, on: MarketDay(date: Date())) {
                        exclusions.append(Exclusion(id: bond.id, name: bond.name,
                            reason: try BondTermsStore.exclusionReason(bond, from: from)))
                    }
                    continue
                }
                let terms = try BondTermsStore.read(bond)
                let trade = try BondTermsStore.trade(bond)
                for payment in preview.payments where payment.paymentDay >= from && payment.paymentDay <= through {
                    guard kind == nil || payment.kind == kind else { continue }
                    // Canonical maturity payments contain full redemption; analytical gains are not extra receipts.
                    receipts.append(CalendarReceipt(id: payment.identity, purchaseID: bond.id, isin: trade.isin,
                        name: bond.name, bank: bond.depotBank, acquisitionDay: trade.acquisitionDay,
                        nominal: trade.nominal, cost: trade.cost, paymentDay: payment.paymentDay,
                        contractualDay: payment.contractualDay, kind: payment.kind, amount: payment.amount,
                        rateSource: payment.rateSource, conditional: terms?.interestDeferral == true, warnings: preview.assessment.warnings))
                }
            } catch {
                NSLog("Cannot prepare calendar for %@: %@", bond.id.uuidString, error.localizedDescription)
                if includeInactiveExclusions || BondEligibility.isActive(bond, on: MarketDay(date: Date())) {
                    exclusions.append(Exclusion(id: bond.id, name: bond.name, reason: error.localizedDescription))
                }
            }
        }
        return Self(receipts: receipts.sorted {
            ($0.paymentDay, $0.isin, $0.id) < ($1.paymentDay, $1.isin, $1.id)
        }, exclusions: exclusions.sorted { $0.name < $1.name })
    }
}

struct CalendarMonth {
    let year: Int
    let month: Int
    var title: String { MarketDay.calendar.monthSymbols[month - 1] }
    var days: [MarketDay?] {
        let calendar = MarketDay.calendar
        guard let first = calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let range = calendar.range(of: .day, in: .month, for: first) else { return [] }
        let offset = (calendar.component(.weekday, from: first) + 5) % 7
        return (0..<42).map { index in
            let day = index - offset + 1
            guard range.contains(day), let date = calendar.date(from: DateComponents(year: year, month: month, day: day)) else { return nil }
            return MarketDay(date: date)
        }
    }
}

struct CashFlowCalendarNavigation {
    enum Level: String, CaseIterable { case years = "Years", year = "Year", month = "Month" }
    var level: Level = .years
    var year = MarketDay(date: Date()).year
    var month = MarketDay(date: Date()).month
    var selectedDay: MarketDay?
    mutating func move(_ direction: Int) {
        let delta = level == .month ? direction : direction * 12
        guard let start = MarketDay.calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let next = MarketDay.calendar.date(byAdding: .month, value: delta, to: start) else { return }
        let value = MarketDay(date: next)
        guard (1901...2199).contains(value.year) else { return }
        year = value.year; month = value.month; selectedDay = nil
    }
}
