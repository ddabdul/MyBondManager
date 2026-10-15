import CoreData

enum CashFlowSelection {
    static func predicate(searchText: String, nature: CashFlowEntity.Nature?, bank: String,
                          start: Date, end: Date, now: Date = Date(),
                          calendar: Calendar = MarketDay.calendar) -> NSPredicate {
        let firstDay = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end)
        guard let afterLastDay = calendar.date(byAdding: .day, value: 1, to: lastDay) else {
            return NSPredicate(value: false)
        }
        var predicates = [
            NSPredicate(format: "bond.termsReady == YES AND generatedFromTerms == YES"),
            NSPredicate(format: "date >= %@ AND date < %@", firstDay as NSDate, afterLastDay as NSDate),
            NSPredicate(format: "nature != %@", CashFlowEntity.Nature.expectedProfit.rawValue)
        ]
        if !searchText.isEmpty { predicates.append(NSPredicate(format: "bond.name CONTAINS[cd] %@", searchText)) }
        if let nature { predicates.append(NSPredicate(format: "nature == %@", nature.rawValue)) }
        if bank != "All" { predicates.append(NSPredicate(format: "bond.depotBank == %@", bank)) }
        return NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
    }

    struct NextCoupon {
        let date: Date
        let amount: Double
        let payer: String
    }

    static func nextCoupon(in bonds: [BondEntity], now: Date = Date(),
                           calendar: Calendar = MarketDay.calendar) -> NextCoupon? {
        let today = MarketDay(date: now)
        guard let first = BondEligibility.nextCoupon(bonds, on: today) else { return nil }
        let nextDay = MarketDay(date: first.date)
        let flows = bonds.flatMap { bond -> [CashFlowEntity] in
            do { return try BondEligibility.flows(bond, from: nextDay, through: nextDay).filter { $0.natureEnum == .interest && $0.amount > 0 } }
            catch { NSLog("Cannot validate coupon group: %@", error.localizedDescription); return [] }
        }
        return NextCoupon(date: nextDay.instant, amount: flows.reduce(0) { $0 + $1.amount },
            payer: flows.count == 1 ? (first.bond?.name ?? "-") : "Multiple")
    }
}
