import SwiftUI

struct CashFlowReceiptList: View {
    let data: CashFlowCalendarData
    var reviewTerms: (() -> Void)? = nil
    @State private var openYears: Set<Int> = []
    @State private var openMonths: Set<String> = []
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CashFlowTotalsView(coupons: data.totals.coupons, repayments: data.totals.repayments)
            if !data.exclusions.isEmpty { CashFlowExclusionNotice(exclusions: data.exclusions, review: reviewTerms) }
            CashFlowAssumptionsView(receipts: data.receipts)
            if data.receipts.isEmpty {
                ContentUnavailableView("No payments in this period", systemImage: "calendar",
                    description: Text("Change the bank, search, payment type or period."))
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 4) {
                        ForEach(Array(data.years.enumerated()), id: \.element) { index, year in
                            let values = data.receipts.filter { $0.paymentDay.year == year }
                            DisclosureGroup(isExpanded: Binding(get: { openYears.contains(year) }, set: {
                                if $0 { openYears.insert(year) } else { openYears.remove(year) }
                            })) {
                                months(values, year: year)
                            } label: {
                                periodLabel(String(year), receipts: values, large: true)
                                    .onTapGesture {
                                        if openYears.contains(year) { openYears.remove(year) } else { openYears.insert(year) }
                                    }
                            }.padding(.horizontal, 12).padding(.vertical, 6)
                                .background(index.isMultiple(of: 2) ? CashFlowStyle.surface : CashFlowStyle.background, in: RoundedRectangle(cornerRadius: 8))
                        }
                    }.padding(2)
                }
            }
        }.padding(.horizontal)
    }
    @ViewBuilder private func months(_ receipts: [CalendarReceipt], year: Int) -> some View {
        let grouped = Dictionary(grouping: receipts, by: { $0.paymentDay.month })
        ForEach(grouped.keys.sorted(), id: \.self) { month in
            let values = grouped[month] ?? []
            let key = "\(year)-\(month)"
            DisclosureGroup(isExpanded: Binding(get: { openMonths.contains(key) }, set: {
                if $0 { openMonths.insert(key) } else { openMonths.remove(key) }
            })) {
                ForEach(Array(values.enumerated()), id: \.element.id) { index, payment in
                    CashFlowReceiptRow(day: payment.paymentDay, name: payment.name, bank: payment.bank, isin: payment.isin,
                        kind: payment.kind == .interest ? "Coupon" : "Repayment", amount: payment.amount, contractualDay: payment.contractualDay,
                        projected: payment.rateSource == .projected, conditional: payment.conditional, warnings: payment.warnings,
                        returnDetail: payment.kind == .maturity ? "Gain/loss on purchase: " + CashFlowStyle.money(payment.amount - payment.cost, precise: true) + " (included in repayment)" : nil,
                        alternating: !index.isMultiple(of: 2))
                }
            } label: {
                periodLabel(MarketDay.calendar.monthSymbols[month - 1], receipts: values, large: false)
                    .onTapGesture {
                        if openMonths.contains(key) { openMonths.remove(key) } else { openMonths.insert(key) }
                    }
            }.padding(.vertical, 4)
        }
    }
    private func periodLabel(_ title: String, receipts: [CalendarReceipt], large: Bool) -> some View {
        let totals = CalendarTotals(receipts)
        return HStack(alignment: .firstTextBaseline) {
            Text(title).font(large ? .system(size: 18, weight: .semibold) : .headline).fontWeight(.semibold)
            Spacer()
            Text(CashFlowStyle.money(totals.total)).font(large ? .title3 : .callout).monospacedDigit()
        }.padding(.vertical, 8).contentShape(Rectangle())
    }
}
