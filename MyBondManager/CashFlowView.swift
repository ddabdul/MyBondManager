//  CashFlowView.swift
//  MyBondManager
//
//  Updated by ChatGPT on 23/04/2025.
//

import SwiftUI
import CoreData

/// Hierarchical Cash Flow View: Year → Month → Coupon Details
struct CashFlowView: View {
    @Environment(\.managedObjectContext) private var moc
    
    // Fetch all bonds
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BondEntity.maturityDate, ascending: true)],
        animation: .default)
    private var bondEntities: FetchedResults<BondEntity>

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
        let now = Date()

        // Build raw events from Core Data entities
        let events: [CouponEvent] = bondEntities.flatMap { bond in
            let couponAmt = bond.parValue * bond.couponRate / 100
            let maturity = bond.maturityDate
            let comps = calendar.dateComponents([.month, .day], from: maturity)
            let year = calendar.component(.year, from: now)
            var result: [CouponEvent] = []
            var next = DateComponents(year: year, month: comps.month, day: comps.day)
            if let d = calendar.date(from: next), d < now {
                next.year! += 1
            }
            // Generate events up to maturity
            while let pay = calendar.date(from: next), pay <= maturity {
                result.append(CouponEvent(
                    bondName: bond.name,
                    date: pay,
                    amount: couponAmt
                ))
                next.year! += 1
            }
            return result
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
                let mcomps = calendar.dateComponents([.year, .month], from: evt.date)
                return calendar.date(from: mcomps)! // first-of-month
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
                                yearGroups
                                    .flatMap { $0.months.map { $0.id } }
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
                                                        Text(
                                                            Formatters.mediumDate
                                                                .string(from: e.date)
                                                        )
                                                        .font(.caption)
                                                        .foregroundColor(.secondary)
                                                    }
                                                    Spacer()
                                                    Text(
                                                        Formatters.currency
                                                            .string(from: NSNumber(value: e.amount))
                                                        ?? "–"
                                                    )
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
                                                Text(
                                                    Formatters.currency
                                                        .string(from: NSNumber(value: mg.total))
                                                    ?? "–"
                                                )
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
                                Text(
                                    Formatters.currency
                                        .string(from: NSNumber(value: yg.total))
                                    ?? "–"
                                )
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
