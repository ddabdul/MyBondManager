import Foundation

struct PaymentCalendarOptions: Codable, Equatable, Sendable {
    var hour = 9
    var dayBefore = false
    var showAmounts = true
}

struct PaymentCalendarEvent: Equatable, Sendable {
    let key: String
    let day: MarketDay
    let title: String
    let notes: String
    let start: Date
    let end: Date
    let alarms: [Date]
    var allDay = true
    static let urlPrefix = "mybondmanager://payment/"
}

struct PaymentCalendarEntry: Sendable {
    let identifier: String
    let event: PaymentCalendarEvent
}

struct PaymentCalendarChanges {
    struct Upsert {
        let identifier: String?
        let event: PaymentCalendarEvent
    }
    var upserts: [Upsert] = []
    var removals: [String] = []

    init(desired: [PaymentCalendarEvent], existing: [PaymentCalendarEntry], from day: MarketDay) {
        var remaining = Dictionary(grouping: existing.filter { $0.event.day >= day }, by: { $0.event.key })
        for event in desired where event.day >= day {
            let matches = remaining.removeValue(forKey: event.key) ?? []
            if matches.first?.event != event {
                upserts.append(Upsert(identifier: matches.first?.identifier, event: event))
            }
            removals.append(contentsOf: matches.dropFirst().map(\.identifier))
        }
        removals.append(contentsOf: remaining.values.flatMap { $0.map(\.identifier) })
    }
}

enum PaymentCalendarProjection {
    static func make(data: CashFlowCalendarData, options: PaymentCalendarOptions,
                     timeZone: TimeZone) throws -> [PaymentCalendarEvent] {
        guard (0...23).contains(options.hour) else { throw PortfolioError("Choose an alert hour between 0 and 23.") }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let formatter = NumberFormatter(); formatter.numberStyle = .currency; formatter.currencyCode = "EUR"
        formatter.locale = Locale(identifier: "en_IE"); formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 2
        func money(_ value: Double) -> String { formatter.string(from: NSNumber(value: value))! }
        let groups = Dictionary(grouping: data.receipts) {
            ETFPurchase.normalizedISIN($0.isin) + "/" + $0.paymentDay.rawValue
        }
        return try groups.keys.sorted().map { key in
            let receipts = groups[key]!.sorted { ($0.name, $0.bank, $0.id) < ($1.name, $1.bank, $1.id) }
            let first = receipts[0], day = first.paymentDay
            let total = CalendarTotals(receipts)
            guard total.total.isFinite else { throw PortfolioError("Payment amount is not finite for " + first.isin) }
            let count = Set(receipts.map(\.purchaseID)).count
            var notes = ["Expected payment; not confirmation of bank receipt.",
                "ISIN: " + ETFPurchase.normalizedISIN(first.isin),
                "Payment date: " + day.rawValue,
                "Coupons: " + money(total.coupons), "Redemption: " + money(total.repayments),
                "\(count) purchase\(count == 1 ? "" : "s")", "Banks: " + Set(receipts.map(\.bank)).sorted().joined(separator: ", ")]
            let contractual = Set(receipts.map(\.contractualDay)).sorted().filter { $0 != day }
            if !contractual.isEmpty { notes.append("Unadjusted dates: " + contractual.map(\.rawValue).joined(separator: ", ")) }
            if receipts.contains(where: { $0.rateSource == .projected }) { notes.append("Projected amount based on frozen market data; subject to change.") }
            if receipts.contains(where: \.conditional) { notes.append("Conditional payment; the issuer may defer it.") }
            notes.append(contentsOf: Set(receipts.flatMap(\.warnings)).sorted())
            guard let start = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)),
                  let end = calendar.date(byAdding: .day, value: 1, to: start),
                  let alarm = calendar.date(bySettingHour: options.hour, minute: 0, second: 0, of: start),
                  let previous = calendar.date(byAdding: .day, value: -1, to: alarm) else {
                throw PortfolioError("Cannot determine calendar alert time.")
            }
            let prefix = receipts.contains(where: { $0.rateSource == .projected }) ? "Projected payment: " : "Expected payment: "
            let title = prefix + first.name + (options.showAmounts ? " — " + money(total.total) : "")
            return PaymentCalendarEvent(key: key, day: day, title: title, notes: notes.joined(separator: "\n"),
                start: start, end: end, alarms: options.dayBefore ? [previous, alarm] : [alarm])
        }
    }
}
