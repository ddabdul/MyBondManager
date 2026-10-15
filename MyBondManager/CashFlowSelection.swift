import CoreData

enum CashFlowSelection {
    static func predicate(searchText: String, nature: CashFlowEntity.Nature?, bank: String,
                          start: Date, end: Date, now: Date = Date(),
                          calendar: Calendar = .current) -> NSPredicate {
        let firstDay = calendar.startOfDay(for: start)
        let lastDay = calendar.startOfDay(for: end)
        guard let afterLastDay = calendar.date(byAdding: .day, value: 1, to: lastDay) else {
            return NSPredicate(value: false)
        }
        var predicates = [
            NSPredicate(format: "bond.maturityDate >= %@", calendar.startOfDay(for: now) as NSDate),
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
                           calendar: Calendar = .current) -> NextCoupon? {
        let today = calendar.startOfDay(for: now)
        let flows = bonds.flatMap { bond in
            bond.cashFlowsArray.filter {
                $0.nature == CashFlowEntity.Nature.interest.rawValue && $0.amount > 0
                    && $0.date >= today && $0.date >= bond.acquisitionDate && $0.date <= bond.maturityDate
            }
        }
        guard let nextDay = flows.map({ calendar.startOfDay(for: $0.date) }).min() else { return nil }
        let payments = flows.filter { calendar.isDate($0.date, inSameDayAs: nextDay) }
        return NextCoupon(date: nextDay, amount: payments.reduce(0) { $0 + $1.amount },
            payer: payments.count == 1 ? (payments.first?.bond?.name ?? "-") : "Multiple")
    }
}
