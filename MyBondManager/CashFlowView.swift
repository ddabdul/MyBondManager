// CashFlowView.swift
// MyBondManager
// Adjusted to CoreData and persisted CashFlowEntity
// Updated on 28/04/2025.

import SwiftUI
import CoreData

/// Hierarchical Cash Flow View: Year → Month → Coupon Details
struct CashFlowView: View {
    @Environment(\.managedObjectContext) private var moc

    // Only load cash flows for bonds that haven't matured
    // and whose event date is today or later
    @FetchRequest(
        entity: CashFlowEntity.entity(),
        sortDescriptors: [
            NSSortDescriptor(keyPath: \CashFlowEntity.date, ascending: true)
        ],
        predicate: NSPredicate(
            format: "bond.maturityDate >= %@ AND date >= %@",
            Date() as NSDate,
            Date() as NSDate
        ),
        animation: .default
    )
    private var cashFlowEntities: FetchedResults<CashFlowEntity>

    // … rest of your CashFlowView unchanged …

    @State private var expandedYears: Set<Int> = []
    @State private var expandedMonths: Set<Date> = []

    // MARK: - Models
    private struct CouponEvent: Identifiable {
        let id = UUID()
        let bondName: String
        let date: Date
        let amount: Double
    }
    private struct MonthGroup: Identifiable {
        let id: Date
        let label: String        // "MM/yy"
        let total: Double
        let events: [CouponEvent]
    }
    private struct YearGroup: Identifiable {
        let id: Int
        let label: String        // "YYYY"
        let total: Double
        let months: [MonthGroup]
    }

    // MARK: - Compute Groups
    private var yearGroups: [YearGroup] {
        let calendar = Calendar.current

        // Map CashFlowEntity to events
        let events: [CouponEvent] = cashFlowEntities.map { cf in
            CouponEvent(
                bondName: cf.bond?.name ?? "–",
                date: cf.date,
                amount: cf.amount
            )
        }

        // Group by year
        let byYear = Dictionary(grouping: events) { evt in
            calendar.component(.year, from: evt.date)
        }

        // Map to YearGroup
        return byYear.map { year, evts in
            let totalYear = evts.reduce(0) { $0 + $1.amount }
            // Group by month
            let byMonth = Dictionary(grouping: evts) { evt in
                let comps = calendar.dateComponents([.year, .month], from: evt.date)
                return calendar.date(from: comps)! // first-of-month
            }
            let monthGroups = byMonth.map { period, mes in
                let label = Formatters.monthYear.string(from: period)
                let totalMonth = mes.reduce(0) { $0 + $1.amount }
                let sorted = mes.sorted { $0.date < $1.date }
                return MonthGroup(id: period, label: label, total: totalMonth, events: sorted)
            }
            .sorted { $0.id < $1.id }

            return YearGroup(
                id: year,
                label: String(year),
                total: totalYear,
                months: monthGroups
            )
        }
        .sorted { $0.id < $1.id }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header and controls
                HStack {
                    Text("Cash Flows")
                        .font(.title2).bold()
                    Spacer()
                    Button("Expand All") {
                        withAnimation {
                            expandedYears = Set(yearGroups.map { $0.id })
                            expandedMonths = Set(
                                yearGroups.flatMap { $0.months.map { $0.id } }
                            )
                        }
                    }
                    .buttonStyle(.bordered)
                    Button("Collapse All") {
                        withAnimation {
                            expandedYears.removeAll()
                            expandedMonths.removeAll()
                        }
                    }
                    .buttonStyle(.bordered)
                }

                // Year list
                ForEach(yearGroups) { yg in
                    DisclosureGroup(
                        isExpanded: Binding(
                            get: { expandedYears.contains(yg.id) },
                            set: { open in
                                withAnimation {
                                    if open { expandedYears.insert(yg.id) }
                                    else { expandedYears.remove(yg.id) }
                                }
                            }
                        ),
                        content: {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(yg.months) { mg in
                                    DisclosureGroup(
                                        isExpanded: Binding(
                                            get: { expandedMonths.contains(mg.id) },
                                            set: { open in
                                                withAnimation {
                                                    if open { expandedMonths.insert(mg.id) }
                                                    else { expandedMonths.remove(mg.id) }
                                                }
                                            }
                                        ),
                                        content: {
                                            ForEach(mg.events) { e in
                                                HStack {
                                                    VStack(alignment: .leading) {
                                                        Text(e.bondName)
                                                            .font(.subheadline)
                                                        Text(Formatters.mediumDate.string(from: e.date))
                                                            .font(.caption)
                                                            .foregroundColor(.secondary)
                                                    }
                                                    Spacer()
                                                    Text(Formatters.currency.string(from: NSNumber(value: e.amount)) ?? "–")
                                                        .bold()
                                                }
                                                .padding(.vertical, 4)
                                                .padding(.horizontal)
                                                .background(AppTheme.tileBackground)
                                                .cornerRadius(6)
                                            }
                                        },
                                        label: {
                                            HStack {
                                                Text(mg.label)
                                                    .font(.body)
                                                Spacer()
                                                Text(Formatters.currency.string(from: NSNumber(value: mg.total)) ?? "–")
                                                    .bold()
                                            }
                                            .padding(6)
                                            .background(AppTheme.tileBackground)
                                            .cornerRadius(6)
                                            .accentColor(.primary)
                                        }
                                    )
                                }
                            }
                            .padding(.leading)
                        },
                        label: {
                            HStack {
                                Text(yg.label)
                                    .font(.headline)
                                Spacer()
                                Text(Formatters.currency.string(from: NSNumber(value: yg.total)) ?? "–")
                                    .bold()
                            }
                            .padding(8)
                            .background(AppTheme.tileBackground)
                            .cornerRadius(8)
                            .accentColor(.primary)
                        }
                    )
                }
            }
            .padding()
        }
    }
}
