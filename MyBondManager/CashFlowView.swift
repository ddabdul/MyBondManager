// CashFlowView.swift
// MyBondManager
// Redesigned on 02/05/2025 with upgraded colors, fonts, layout & hover effects

import SwiftUI
import CoreData

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
    let label: String     // "MM/yy"
    let total: Double
    let events: [CouponEvent]
}

fileprivate struct YearGroup: Identifiable {
    let id: Int
    let label: String     // "YYYY"
    let total: Double
    let months: [MonthGroup]

    static func build(from cashFlows: FetchedResults<CashFlowEntity>,
                      calendar: Calendar) -> [YearGroup] {
        // Map to CouponEvent
        let events = cashFlows.map { cf in
            CouponEvent(
                bondName: cf.bond?.name ?? "–",
                depotBank: cf.bond?.depotBank ?? "–",
                date: cf.date,
                amount: cf.amount,
                nature: cf.natureEnum
            )
        }
        // Group by year
        let byYear = Dictionary(grouping: events) {
            calendar.component(.year, from: $0.date)
        }
        // Build YearGroups
        return byYear.map { year, evts in
            let totalYear = evts.reduce(0) { $0 + $1.amount }
            // Group by month
            let byMonth = Dictionary(grouping: evts) { evt in
                let comps = calendar.dateComponents([.year, .month], from: evt.date)
                return calendar.date(from: comps)!
            }
            let monthGroups = byMonth.map { period, mes in
                let totalMonth = mes.reduce(0) { $0 + $1.amount }
                let sorted = mes.sorted { $0.date < $1.date }
                return MonthGroup(
                    id: period,
                    label: Formatters.monthYear.string(from: period),
                    total: totalMonth,
                    events: sorted
                )
            }.sorted { $0.id < $1.id }
            return YearGroup(
                id: year,
                label: String(year),
                total: totalYear,
                months: monthGroups
            )
        }.sorted { $0.id < $1.id }
    }
}

// MARK: – CashFlowView

struct CashFlowView: View {
    @Environment(\.managedObjectContext) private var moc

    // Exclude expectedProfit events
    @FetchRequest(
        entity: CashFlowEntity.entity(),
        sortDescriptors: [ NSSortDescriptor(keyPath: \CashFlowEntity.date, ascending: true) ],
        predicate: NSPredicate(
            format: "bond.maturityDate >= %@ AND date >= %@ AND nature != %@",
            Date() as NSDate,
            Date() as NSDate,
            CashFlowEntity.Nature.expectedProfit.rawValue
        ),
        animation: .default
    )
    private var cashFlows: FetchedResults<CashFlowEntity>

    @State private var expandedYears: Set<Int> = []
    @State private var expandedMonths: Set<Date> = []

    private var yearGroups: [YearGroup] {
        YearGroup.build(from: cashFlows, calendar: .current)
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                header
                ForEach(yearGroups) { yg in
                    YearBlock(
                        yearGroup: yg,
                        expandedYears: $expandedYears,
                        expandedMonths: $expandedMonths
                    )
                }
            }
            .padding()
            .background(Color(hex: 0x1C1C1E)) // deep charcoal bg
        }
    }

    private var header: some View {
        HStack {
            Text("Cash Flows")
                .font(.system(.largeTitle, design: .rounded))
                .foregroundColor(.white)
            Spacer()
            HStack(spacing: 8) {
                Button("Expand All") {
                    withAnimation(.spring()) {
                        expandedYears = Set(yearGroups.map(\.id))
                        expandedMonths = Set(yearGroups.flatMap { $0.months.map(\.id) })
                    }
                }
                .buttonStyle(.borderedProminent)
                Button("Collapse All") {
                    withAnimation(.spring()) {
                        expandedYears.removeAll()
                        expandedMonths.removeAll()
                    }
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(.horizontal)
    }
}

// MARK: – YearBlock

fileprivate struct YearBlock: View {
    let yearGroup: YearGroup
    @Binding var expandedYears: Set<Int>
    @Binding var expandedMonths: Set<Date>

    // gradient: purple→blue
    private let gradient = LinearGradient(
        gradient: Gradient(colors: [
            Color(hex: 0x6B5BFF),
            Color(hex: 0x4A90E2)
        ]),
        startPoint: .leading,
        endPoint: .trailing
    )
    @State private var isHovered = false

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedYears.contains(yearGroup.id) },
                set: { open in
                    withAnimation(.spring()) {
                        if open { expandedYears.insert(yearGroup.id) }
                        else     { expandedYears.remove(yearGroup.id) }
                    }
                }
            )
        ) {
            VStack(spacing: 12) {
                ForEach(yearGroup.months) { mg in
                    MonthBlock(
                        monthGroup: mg,
                        expandedMonths: $expandedMonths
                    )
                }
            }
            .padding(.leading, 16)
        } label: {
            HStack {
                Text(yearGroup.label)
                    .font(.system(.title2, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text(Formatters.currency.string(from: NSNumber(value: yearGroup.total)) ?? "–")
                    .font(.system(.title2, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding()
            .background(gradient)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(isHovered ? 0.4 : 0.2),
                    radius: isHovered ? 8 : 4,
                    x: 0, y: 4)
            .scaleEffect(isHovered ? 1.02 : 1.0)
            .onHover { isHovered = $0 }
        }
        .padding(.horizontal)
    }
}

// MARK: – MonthBlock

fileprivate struct MonthBlock: View {
    let monthGroup: MonthGroup
    @Binding var expandedMonths: Set<Date>

    // gradient: gray→indigo
    private let gradient = LinearGradient(
        gradient: Gradient(colors: [
            Color(hex: 0x2C2C2E),
            Color(hex: 0x3D3D47)
        ]),
        startPoint: .leading,
        endPoint: .trailing
    )
    @State private var isHovered = false

    var body: some View {
        DisclosureGroup(
            isExpanded: Binding(
                get: { expandedMonths.contains(monthGroup.id) },
                set: { open in
                    withAnimation(.spring()) {
                        if open { expandedMonths.insert(monthGroup.id) }
                        else     { expandedMonths.remove(monthGroup.id) }
                    }
                }
            )
        ) {
            VStack(spacing: 12) {
                // group by bond
                let byBond = Dictionary(grouping: monthGroup.events) { $0.bondName }
                ForEach(byBond.keys.sorted(), id: \.self) { name in
                    if let evts = byBond[name] {
                        BondCardView(bondName: name, events: evts)
                    }
                }
            }
            .padding(.leading, 16)
        } label: {
            HStack {
                Text(monthGroup.label)
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.white)
                Spacer()
                Text(Formatters.currency.string(from: NSNumber(value: monthGroup.total)) ?? "–")
                    .font(.system(.headline, design: .monospaced))
                    .foregroundColor(.white)
            }
            .padding()
            .background(gradient)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(isHovered ? 0.3 : 0.15),
                    radius: isHovered ? 6 : 3,
                    x: 0, y: 3)
            .scaleEffect(isHovered ? 1.015 : 1.0)
            .onHover { isHovered = $0 }
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
    private var date: Date { events.first?.date ?? Date() }

    // gradient: dark slate
    private let gradient = LinearGradient(
        gradient: Gradient(colors: [
            Color(hex: 0x2A2A2E),
            Color(hex: 0x414149)
        ]),
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    var body: some View {
        DisclosureGroup(isExpanded: $expanded) {
            VStack(alignment: .leading, spacing: 6) {
                Text(Formatters.mediumDate.string(from: date))
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundColor(.secondary)

                ForEach(events.sorted(by: { $0.nature.rawValue < $1.nature.rawValue })) { e in
                    HStack {
                        Image(systemName: iconName(for: e.nature))
                        Text(label(for: e.nature) + ":")
                        Spacer()
                        Text(Formatters.currency.string(from: NSNumber(value: e.amount)) ?? "–")
                    }
                    .font(.system(.body, design: .rounded))
                    .foregroundColor(color(for: e.nature))
                }
            }
            .padding(.top, 8)
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(bondName)
                        .font(.system(.headline, design: .rounded))
                        .foregroundColor(.white)
                    Spacer()
                    Text(Formatters.currency.string(from: NSNumber(value: total)) ?? "–")
                        .font(.system(.title3, design: .monospaced))
                        .foregroundColor(.white)
                }
                Text(depotBank)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding()
            .background(gradient)
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(isHovered ? 0.25 : 0.1),
                    radius: isHovered ? 4 : 2,
                    x: 0, y: 2)
            .scaleEffect(isHovered ? 1.01 : 1.0)
            .onHover { isHovered = $0 }
        }
        .padding(.vertical, 4)
    }

    private func iconName(for nature: CashFlowEntity.Nature) -> String {
        switch nature {
        case .interest:     return "arrow.down.circle"
        case .principal:    return "banknote"
        case .capitalGains: return "arrow.up.circle"
        case .capitalLoss:  return "arrow.down.circle.fill"
        default:            return "questionmark"
        }
    }

    private func color(for nature: CashFlowEntity.Nature) -> Color {
        switch nature {
        case .interest:     return Color(hex: 0x34C759)
        case .principal:    return Color(hex: 0x5E5CE6)
        case .capitalGains: return Color(hex: 0xFFD60A)
        case .capitalLoss:  return Color(hex: 0xFF453A)
        default:            return .secondary
        }
    }

    private func label(for nature: CashFlowEntity.Nature) -> String {
        switch nature {
        case .interest:     return "Interest"
        case .principal:    return "Principal"
        case .capitalGains: return "Capital gain"
        case .capitalLoss:  return "Capital loss"
        default:            return nature.rawValue.capitalized
        }
    }
}

// MARK: – Color helper

extension Color {
    /// Create from hex 0xRRGGBB
    init(hex: UInt, alpha: Double = 1) {
        let r = Double((hex >> 16) & 0xFF) / 255
        let g = Double((hex >> 8)  & 0xFF) / 255
        let b = Double(hex         & 0xFF) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

// MARK: – Preview

struct CashFlowView_Previews: PreviewProvider {
    static var previews: some View {
        CashFlowView()
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
            .frame(minWidth: 800, minHeight: 600)
    }
}
