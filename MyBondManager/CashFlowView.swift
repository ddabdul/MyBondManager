//
//  CashFlowView.swift
//  MyBondManager (macOS only)
//  Updated 14/05/2025: filter on shared Depot Bank selection + modernized onChange
//

import SwiftUI
import CoreData

// MARK: – Model types & builder

// MARK: – CashFlowView

struct CashFlowView: View {
    @Binding var selectedDepotBank: String
    @Environment(\.managedObjectContext) private var moc

    // — Filter state
    @State private var searchText        = ""
    @State private var selectedNature: CashFlowEntity.Nature? = nil

    // — Date range (today → one year ahead)
    @State private var startDate = Date()
    @State private var endDate   = Calendar.current.date(byAdding: .year, value: 1, to: Date())!

    // — Core Data fetched array
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \CashFlowEntity.date, ascending: true)],
                  predicate: NSPredicate(value: false), animation: .default)
    private var cashFlows: FetchedResults<CashFlowEntity>

    // — Pickable natures
    private let natures: [CashFlowEntity.Nature] = [
        .principal, .capitalGains, .interest
    ]

    // — Build year/month groups
    private var yearGroups: [YearGroup] {
        let bonds = Set(cashFlows.compactMap(\.bond))
        let allowed = Set(bonds.flatMap { bond -> [CashFlowEntity] in
            do { return try BondEligibility.flows(bond, from: MarketDay(date: startDate), through: MarketDay(date: endDate)) }
            catch { NSLog("Cannot validate cash-flow view: %@", error.localizedDescription); return [] }
        }.map(\.objectID))
        return YearGroup.build(from: cashFlows.filter { allowed.contains($0.objectID) }, calendar: MarketDay.calendar)
    }

    var body: some View {
        VStack(spacing: 16) {
            // 1) Title Bar
            HStack {
                Text("My Cash Flows")
                    .font(.system(.largeTitle, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
            }
            .padding()
            .background(AppTheme.tileBackground)

            // 2) Filter Bar
            filterBar

            // 3) Scrollable List
            cashFlowList
        }
        .onAppear { fetchCashFlows() }
        .onChange(of: searchText)        { fetchCashFlows() }
        .onChange(of: selectedNature)    { fetchCashFlows() }
        .onChange(of: startDate)         {
            if startDate > endDate { endDate = startDate }
            fetchCashFlows()
        }
        .onChange(of: endDate)           {
            if endDate < startDate { startDate = endDate }
            fetchCashFlows()
        }
        .onChange(of: selectedDepotBank) { fetchCashFlows() }
        .background(
            AppTheme.panelBackground
                .edgesIgnoringSafeArea(.all)
        )
    }

    // MARK: – Sub-view #1: Filter Bar

    private var filterBar: some View {
        HStack(spacing: 12) {
            TextField("Search bond…", text: $searchText)
                .textFieldStyle(.roundedBorder)
     //           .frame(minWidth: 200)

            Picker("Nature", selection: Binding(
                get:  { selectedNature },
                set:  { selectedNature = $0 }
            )) {
                Text("All").tag(CashFlowEntity.Nature?.none)
                ForEach(natures, id: \.self) { nat in
                    Text(nat.label).tag(CashFlowEntity.Nature?.some(nat))
                }
            }
            .pickerStyle(.menu)

            DatePicker("From", selection: $startDate, displayedComponents: .date)
            DatePicker("To",   selection: $endDate,   displayedComponents: .date)
        }
        .padding(.horizontal)
        .background(AppTheme.panelBackground)
    }

    // MARK: – Sub-view #2: Cash‐flow List

    private var cashFlowList: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(yearGroups) { yg in
                    YearBlock(yearGroup: yg)
                }
            }
            .padding(.horizontal)
        }
    }

    // MARK: – Fetch Logic

    private func fetchCashFlows() {
        cashFlows.nsPredicate = CashFlowSelection.predicate(searchText: searchText, nature: selectedNature,
            bank: selectedDepotBank, start: startDate, end: endDate)
    }
}

// MARK: – YearBlock

fileprivate struct YearBlock: View {
    let yearGroup: YearGroup
    @State private var stage     = 0    // 0=closed,1=summary,2=months
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
            Button { stage = (stage + 1) % 3 } label: {
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
                        startPoint: .leading,
                        endPoint: .trailing
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
    @State private var stage     = 0
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
            Button { stage = (stage + 1) % 3 } label: {
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
                        startPoint: .leading,
                        endPoint: .trailing
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
                VStack(spacing: 6) {
                    ForEach(monthGroup.bondGroups) { entry in
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

    @State private var expanded  = false
    @State private var isHovered = false

    private var total: Double { events.reduce(0) { $0 + $1.amount } }
    private var depotBank: String { events.first?.depotBank ?? "–" }
    private var date: String {
        Formatters.marketMediumDate.string(from: events.first?.date ?? Date())
    }

    private let order: [CashFlowEntity.Nature] = [.principal, .capitalGains, .interest]
    private var sums: [(CashFlowEntity.Nature, Double)] {
        order.compactMap { n in
            let amt = events.filter { $0.nature == n }
                            .reduce(0) { $0 + $1.amount }
            return amt != 0 ? (n, amt) : nil
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            Button { expanded.toggle() } label: {
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
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
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
