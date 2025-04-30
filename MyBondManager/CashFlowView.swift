// CashFlowView.swift
// MyBondManager (macOS only)
// Updated 07/05/2025: bonds within each month now sorted chronologically
// End date initialized one year from today; date‐pickers clamped accordingly

import SwiftUI
import CoreData
import AppKit

// MARK: – Model types & builder

fileprivate struct CouponEvent: Identifiable {
    let id = UUID()
    let bondName: String
    let depotBank: String
    let date: Date
    let amount: Double
    let nature: CashFlowEntity.Nature
}

fileprivate struct MonthGroup: Identifiable {
    let id: Date
    let label: String      // "MM/yy"
    let total: Double      // excludes capitalLoss
    let events: [CouponEvent]
}

fileprivate struct YearGroup: Identifiable {
    let id: Int
    let label: String      // "YYYY"
    let total: Double      // excludes capitalLoss
    let months: [MonthGroup]

    static func build(
        from cashFlows: [CashFlowEntity],
        calendar: Calendar
    ) -> [YearGroup] {
        let events = cashFlows.compactMap { cf -> CouponEvent? in
            let nat = cf.natureEnum
            guard nat != .capitalLoss else { return nil }
            return CouponEvent(
                bondName: cf.bond?.name ?? "–",
                depotBank: cf.bond?.depotBank ?? "–",
                date: cf.date,
                amount: cf.amount,
                nature: nat
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
                            id: period,
                            label: Formatters.monthYear.string(from: period),
                            total: totalMonth,
                            events: mes.sorted { $0.date < $1.date }
                        )
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
}

// MARK: – CashFlowView

struct CashFlowView: View {
    @Environment(\.managedObjectContext) private var moc

    // — Filter state
    @State private var searchText        = ""
    @State private var selectedNature: CashFlowEntity.Nature? = nil

    // start date is today; end date is one year from today (initial values)
    @State private var startDate       = Date()
    @State private var endDate         = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

    // — Fetched array
    @State private var cashFlowsArray: [CashFlowEntity] = []

    // — Our 3 pickable natures
    private let natures: [CashFlowEntity.Nature] = [
        .principal, .capitalGains, .interest
    ]

    // — Build the year/month groups
    private var yearGroups: [YearGroup] {
        YearGroup.build(from: cashFlowsArray, calendar: .current)
    }

    var body: some View {
        VStack(spacing: 12) {
            filterBar
            cashFlowList
        }
        .onAppear         { fetchCashFlows() }
        .onChange(of: searchText)    { fetchCashFlows() }
        .onChange(of: selectedNature) { fetchCashFlows() }
        .onChange(of: startDate)     {
            if startDate > endDate {
                endDate = startDate
            }
            fetchCashFlows()
        }
        .onChange(of: endDate)       {
            if endDate < startDate {
                startDate = endDate
            }
            fetchCashFlows()
        }
        .background(
            Color(nsColor: .windowBackgroundColor)
                .edgesIgnoringSafeArea(.all)
        )
    }

    // MARK: – Sub-view #1: Filter bar

    private var filterBar: some View {
        HStack {
            TextField("Search bond…", text: $searchText)
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 200)

            Picker("Nature", selection: Binding(
                get:  { selectedNature },
                set:  { selectedNature = $0 }
            )) {
                Text("All")
                    .tag(CashFlowEntity.Nature?.none)
                ForEach(natures, id: \.self) { nat in
                    Text(nat.label)
                        .tag(CashFlowEntity.Nature?.some(nat))
                }
            }
            .pickerStyle(.menu)

            DatePicker(
                "From",
                selection: $startDate,
                displayedComponents: .date
            )
            DatePicker(
                "To",
                selection: $endDate,
                displayedComponents: .date
            )
        }
        .padding(.horizontal)
    }

    // MARK: – Sub-view #2: Cash-flow list

    private var cashFlowList: some View {
        ScrollView {
            VStack(spacing: 16) {
                Text("Cash Flows")
                    .font(.system(.largeTitle, design: .rounded))
                    .foregroundColor(.primary)
                    .padding(.top)

                ForEach(yearGroups) { yg in
                    YearBlock(yearGroup: yg)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: – Fetch logic

    private func fetchCashFlows() {
        let req: NSFetchRequest<CashFlowEntity> = CashFlowEntity.fetchRequest()
        var predicates: [NSPredicate] = [
            NSPredicate(format: "bond.maturityDate >= %@", Date() as NSDate),
            NSPredicate(format: "date >= %@", startDate as NSDate),
            NSPredicate(format: "date <= %@", endDate  as NSDate),
            NSPredicate(format: "nature != %@", CashFlowEntity.Nature.expectedProfit.rawValue)
        ]

        if !searchText.isEmpty {
            predicates.append(
                NSPredicate(format: "bond.name CONTAINS[cd] %@", searchText)
            )
        }
        if let nat = selectedNature {
            predicates.append(
                NSPredicate(format: "nature == %@", nat.rawValue)
            )
        }

        req.predicate     = NSCompoundPredicate(andPredicateWithSubpredicates: predicates)
        req.sortDescriptors = [NSSortDescriptor(keyPath: \CashFlowEntity.date, ascending: true)]

        do {
            cashFlowsArray = try moc.fetch(req)
        } catch {
            print("Failed to fetch filtered cash-flows:", error)
            cashFlowsArray = []
        }
    }
}


// MARK: – YearBlock

fileprivate struct YearBlock: View {
    let yearGroup: YearGroup
    @State private var stage = 0    // 0=closed,1=summary,2=months
    @State private var isHovered = false

    private let order: [CashFlowEntity.Nature] = [.principal, .capitalGains, .interest]
    private var sums: [(CashFlowEntity.Nature, Double)] {
        order.compactMap { n in
            let total = yearGroup.months
                .flatMap { $0.events }
                .filter { $0.nature == n }
                .reduce(0) { $0 + $1.amount }
            return total != 0 ? (n, total) : nil
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Button { stage = (stage + 1) % 3 }
            label: {
                HStack {
                    Text(yearGroup.label)
                        .font(.system(.title2, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Text(
                        Formatters.currency
                            .string(from: NSNumber(value: yearGroup.total)) ?? "–"
                    )
                    .font(.system(.title2, design: .monospaced))
                    .foregroundColor(.white)
                }
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.indigo, Color.blue]),
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(
                    color: .black.opacity(isHovered ? 0.4 : 0.2),
                    radius: isHovered ? 8 : 4, x: 0, y: 4
                )
                .scaleEffect(isHovered ? 1.02 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help("")

            if stage >= 1 {
                ForEach(sums, id: \.0) { nature, amt in
                    SummaryRow(nature: nature, amount: amt)
                        .padding(.leading, 12)
                }
                if stage == 1 {
                    HStack { Spacer()
                        Text("Click again to view months »")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if stage == 2 {
                VStack(spacing: 12) {
                    ForEach(yearGroup.months) { mg in
                        MonthBlock(monthGroup: mg)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: – MonthBlock

fileprivate struct MonthBlock: View {
    let monthGroup: MonthGroup
    @State private var stage = 0    // 0=closed,1=summary,2=bonds
    @State private var isHovered = false

    private let order: [CashFlowEntity.Nature] = [.principal, .capitalGains, .interest]
    private var sums: [(CashFlowEntity.Nature, Double)] {
        order.compactMap { n in
            let total = monthGroup.events
                .filter { $0.nature == n }
                .reduce(0) { $0 + $1.amount }
            return total != 0 ? (n, total) : nil
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Button { stage = (stage + 1) % 3 }
            label: {
                HStack {
                    Text(monthGroup.label)
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Text(
                        Formatters.currency
                            .string(from: NSNumber(value: monthGroup.total)) ?? "–"
                    )
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.white)
                }
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.teal, Color.green]),
                        startPoint: .leading, endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(
                    color: .black.opacity(isHovered ? 0.3 : 0.15),
                    radius: isHovered ? 6 : 3, x: 0, y: 3
                )
                .scaleEffect(isHovered ? 1.015 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help("")

            if stage >= 1 {
                ForEach(sums, id: \.0) { nature, amt in
                    SummaryRow(nature: nature, amount: amt)
                        .padding(.leading, 12)
                }
                if stage == 1 {
                    HStack { Spacer()
                        Text("Click again to view bonds »")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if stage == 2 {
                let byBond = Dictionary(grouping: monthGroup.events) { $0.bondName }
                let sortedBonds = byBond
                    .map { (name: $0.key, events: $0.value) }
                    .sorted { lhs, rhs in
                        lhs.events.first!.date < rhs.events.first!.date
                    }

                VStack(spacing: 6) {
                    ForEach(sortedBonds, id: \.name) { entry in
                        BondCardView(bondName: entry.name, events: entry.events)
                    }
                }
                .padding(.leading, 16)
            }
        }
        .padding(.horizontal, 24)
    }
}

// MARK: – BondCardView

fileprivate struct BondCardView: View {
    let bondName: String
    let events: [CouponEvent]

    @State private var expanded = false
    @State private var isHovered = false

    private var total: Double { events.reduce(0) { $0 + $1.amount } }
    private var depotBank: String { events.first?.depotBank ?? "–" }
    private var date: String {
        Formatters.mediumDate.string(from: events.first?.date ?? Date())
    }

    private let order: [CashFlowEntity.Nature] = [.principal, .capitalGains, .interest]
    private var sums: [(CashFlowEntity.Nature, Double)] {
        order.compactMap { n in
            let sum = events
                .filter { $0.nature == n }
                .reduce(0) { $0 + $1.amount }
            return sum != 0 ? (n, sum) : nil
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Button { expanded.toggle() }
            label: {
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(bondName)
                            .font(.system(.headline, design: .rounded))
                            .foregroundColor(.white)
                        Spacer()
                        Text(
                            Formatters.currency
                                .string(from: NSNumber(value: total)) ?? "–"
                        )
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(.white)
                    }
                    HStack {
                        Text(depotBank)
                        Spacer()
                        Text(date)
                    }
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                }
                .padding()
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.orange, Color.red]),
                        startPoint: .topLeading, endPoint: .bottomTrailing
                    )
                )
                .cornerRadius(12)
                .shadow(
                    color: .black.opacity(isHovered ? 0.25 : 0.1),
                    radius: isHovered ? 4 : 2, x: 0, y: 2
                )
                .scaleEffect(isHovered ? 1.01 : 1.0)
            }
            .buttonStyle(.plain)
            .onHover { isHovered = $0 }
            .help("")

            if expanded {
                ForEach(sums, id: \.0) { nature, amt in
                    SummaryRow(nature: nature, amount: amt)
                        .padding(.leading, 12)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: – SummaryRow

fileprivate struct SummaryRow: View {
    let nature: CashFlowEntity.Nature
    let amount: Double

    var body: some View {
        HStack {
            Image(systemName: nature.iconName)
                .foregroundColor(nature.color)
            Text(nature.label + ":")
            Spacer()
            Text(
                Formatters.currency
                    .string(from: NSNumber(value: amount)) ?? "–"
            )
            .foregroundColor(nature.color)
            .font(.system(.body, design: .monospaced))
        }
        .font(.system(.caption, design: .rounded))
    }
}

// MARK: – Nature helpers

private extension CashFlowEntity.Nature {
    var iconName: String {
        switch self {
        case .interest:     return "arrow.down.circle"
        case .principal:    return "banknote"
        case .capitalGains: return "arrow.up.circle"
        default:            return "questionmark"
        }
    }
    var label: String {
        switch self {
        case .interest:     return "Interest"
        case .principal:    return "Principal"
        case .capitalGains: return "Capital gain"
        default:            return rawValue.capitalized
        }
    }

    var color: Color {
        switch self {
        case .interest:     return .green
        case .principal:    return .primary
        case .capitalGains: return .yellow
        default:            return .secondary
        }
    }
}
