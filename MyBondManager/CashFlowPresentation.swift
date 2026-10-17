import Foundation
import CoreData

struct CouponEvent: Identifiable {
    let id: NSManagedObjectID
    let bondID: NSManagedObjectID
    let bondName: String
    let depotBank: String
    let date: Date
    let amount: Double
    let nature: CashFlowEntity.Nature
}

struct MonthGroup: Identifiable {
    let id: Date
    let label: String      // "MM/yy"
    let total: Double      // excludes capitalLoss
    let events: [CouponEvent]

    struct BondGroup: Identifiable {
        let id: NSManagedObjectID
        let name: String
        let events: [CouponEvent]
    }
    var bondGroups: [BondGroup] {
        Dictionary(grouping: events, by: \.bondID).compactMap { id, events in
            guard let first = events.first else { return nil }
            return BondGroup(id: id, name: first.bondName, events: events)
        }.sorted { ($0.events.first?.date ?? .distantPast) < ($1.events.first?.date ?? .distantPast) }
    }
}

struct YearGroup: Identifiable {
    let id: Int
    let label: String      // "YYYY"
    let total: Double      // excludes capitalLoss
    let months: [MonthGroup]

    static func build(
        from cashFlows: [CashFlowEntity],
        calendar: Calendar
    ) -> [YearGroup] {
        let events = cashFlows.compactMap { cf -> CouponEvent? in
            guard cf.natureEnum != .capitalLoss else { return nil }
            return CouponEvent(
                id: cf.objectID,
                bondID: cf.bond?.objectID ?? cf.objectID,
                bondName:  cf.bond?.name      ?? "–",
                depotBank: cf.bond?.depotBank ?? "–",
                date:      cf.date,
                amount:    cf.amount,
                nature:    cf.natureEnum
            )
        }

        let byYear = Dictionary(grouping: events) {
            calendar.component(.year, from: $0.date)
        }

        return byYear
            .map { year, evts in
                let totalYear = evts.reduce(0) { $0 + $1.amount }

                let byMonth = Dictionary(grouping: evts) { evt in
                    let comps = calendar.dateComponents([.year, .month], from: evt.date)
                    return calendar.date(from: comps)!
                }

                let monthGroups = byMonth
                    .map { period, mes in
                        let totalMonth = mes.reduce(0) { $0 + $1.amount }
                        return MonthGroup(
                            id:     period,
                            label:  Formatters.marketMonthYear.string(from: period),
                            total:  totalMonth,
                            events: mes.sorted { $0.date < $1.date }
                        )
                    }
                    .sorted { $0.id < $1.id }

                return YearGroup(
                    id:     year,
                    label:  String(year),
                    total:  totalYear,
                    months: monthGroups
                )
            }
            .sorted { $0.id < $1.id }
    }
}
