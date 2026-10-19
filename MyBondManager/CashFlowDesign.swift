import SwiftUI

// Reuse the portfolio panel and table surfaces across all cash-flow presentations.
enum CashFlowStyle {
    static let background = AppTheme.panelBackground
    static let surface = Color(nsColor: .windowBackgroundColor)
    static let coupon = Color.green
    static let repayment = Color.blue
    static func money(_ amount: Double, precise: Bool = false) -> String {
        amount.formatted(.currency(code: "EUR").precision(.fractionLength(precise ? 2 : 0)))
    }
}

struct CashFlowTotalsView: View {
    let coupons: Double
    let repayments: Double
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 24) {
                total
                Spacer(minLength: 16)
                breakdown
            }
            VStack(alignment: .leading, spacing: 8) { total; breakdown }
        }.padding(14).monospacedDigit()
            .background(CashFlowStyle.surface, in: RoundedRectangle(cornerRadius: 10))
    }
    private var total: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Expected receipts").font(.callout).foregroundStyle(.secondary)
            Text(CashFlowStyle.money(coupons + repayments)).font(.system(size: 24, weight: .semibold))
        }
    }
    private var breakdown: some View {
        HStack(spacing: 20) {
            VStack(alignment: .trailing, spacing: 3) {
                Label("Coupons", systemImage: "circle.fill").font(.caption).foregroundStyle(CashFlowStyle.coupon)
                Text(CashFlowStyle.money(coupons)).font(.callout)
            }
            VStack(alignment: .trailing, spacing: 3) {
                Label("Repayments", systemImage: "square.fill").font(.caption).foregroundStyle(CashFlowStyle.repayment)
                Text(CashFlowStyle.money(repayments)).font(.callout)
            }
        }.fixedSize()
    }
}

struct CashFlowExclusionNotice: View {
    let exclusions: [CashFlowCalendarData.Exclusion]
    var review: (() -> Void)? = nil
    @State private var expanded = false
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            DisclosureGroup(isExpanded: $expanded) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(exclusions) { holding in
                            VStack(alignment: .leading, spacing: 4) {
                                Text(holding.name).fontWeight(.medium)
                                Text(holding.reason).font(.callout).foregroundStyle(.primary).textSelection(.enabled)
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.frame(maxHeight: 220).padding(.top, 8)
            } label: {
                Label {
                    Text("Incomplete: \(exclusions.count) holding\(exclusions.count == 1 ? " needs" : "s need") attention")
                        .foregroundStyle(.primary)
                } icon: {
                    Image(systemName: "exclamationmark.triangle").foregroundStyle(.orange)
                }.font(.callout).contentShape(Rectangle()).onTapGesture { expanded.toggle() }
            }
            if let review { Button("Review", action: review).help("Review excluded instruments") }
        }.padding(12).background(Color.orange.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct CashFlowAssumptionsView: View {
    let receipts: [CalendarReceipt]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { labels }
            VStack(alignment: .leading, spacing: 6) { labels }
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading)
    }
    @ViewBuilder private var labels: some View {
        if receipts.contains(where: { $0.rateSource == .projected }) {
            Label { Text("Projected coupons").foregroundStyle(.primary) } icon: {
                Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(.blue)
            }
        }
        if receipts.contains(where: \.conditional) {
            Label { Text("Conditional payments").foregroundStyle(.primary) } icon: {
                Image(systemName: "clock").foregroundStyle(.orange)
            }
        }
        if receipts.contains(where: { !$0.warnings.isEmpty }) {
            Label("Saved assumptions; open a payment for details", systemImage: "info.circle").foregroundStyle(.primary)
        }
    }
}

struct CashFlowReceiptRow: View {
    let day: MarketDay
    let name: String
    let bank: String
    let isin: String
    let kind: String
    let amount: Double
    let contractualDay: MarketDay
    var projected = false
    var conditional = false
    var warnings: [String] = []
    var returnDetail: String? = nil
    var alternating = false
    var body: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 5) {
                Text("ISIN: " + isin).textSelection(.enabled)
                if contractualDay != day { Text("Contractual date: " + contractualDay.rawValue) }
                if let returnDetail { Text(returnDetail) }
                if projected {
                    Label { Text("Projected using frozen market data").foregroundStyle(.primary) } icon: {
                        Image(systemName: "chart.line.uptrend.xyaxis").foregroundStyle(.blue)
                    }
                }
                if conditional {
                    Label { Text("Conditional payment; may be deferred").foregroundStyle(.primary) } icon: {
                        Image(systemName: "clock").foregroundStyle(.orange)
                    }
                }
                ForEach(warnings, id: \.self) { Text($0).foregroundStyle(.primary) }
            }.font(.callout).padding(.leading, 108).padding(.vertical, 8)
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(Formatters.marketMediumDate.string(from: day.instant)).font(.callout).frame(width: 96, alignment: .leading)
                VStack(alignment: .leading, spacing: 3) {
                    Text(name).font(.callout).fontWeight(.medium).lineLimit(2)
                    HStack(spacing: 8) {
                        Image(systemName: kind == "Coupon" ? "circle.fill" : "square.fill")
                            .foregroundStyle(kind == "Coupon" ? CashFlowStyle.coupon : CashFlowStyle.repayment)
                            .accessibilityHidden(true)
                        Text(kind).foregroundStyle(.primary)
                        Text(bank).foregroundStyle(.primary)
                        if projected { Image(systemName: "chart.line.uptrend.xyaxis").accessibilityLabel("Projected coupon") }
                        if conditional { Image(systemName: "clock").accessibilityLabel("Conditional payment") }
                    }.font(.caption)
                }.frame(maxWidth: .infinity, alignment: .leading)
                Text(CashFlowStyle.money(amount, precise: true)).font(.callout).fontWeight(.medium).monospacedDigit()
                    .fixedSize().frame(minWidth: 100, alignment: .trailing)
            }.padding(.vertical, 6)
        }
        .padding(.horizontal, 10)
        .background(alternating ? CashFlowStyle.background : CashFlowStyle.surface, in: RoundedRectangle(cornerRadius: 8))
    }
}
