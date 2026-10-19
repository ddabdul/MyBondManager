import SwiftUI

struct CashFlowCalendarView: View {
    let data: CashFlowCalendarData
    @Binding var navigation: CashFlowCalendarNavigation
    var reviewTerms: (() -> Void)? = nil

    private var periodReceipts: [CalendarReceipt] {
        data.receipts.filter {
            navigation.level == .years || ($0.paymentDay.year == navigation.year &&
                (navigation.level == .year || $0.paymentDay.month == navigation.month))
        }
    }
    var body: some View {
        VStack(spacing: 12) {
            toolbar
            if !data.exclusions.isEmpty { exclusionNotice }
            totals(CalendarTotals(periodReceipts))
            CashFlowAssumptionsView(receipts: periodReceipts)
            if navigation.level == .years {
                if data.years.isEmpty {
                    ContentUnavailableView("No payments in this period", systemImage: "calendar",
                        description: Text("Change the bank, search or payment filters, or review excluded holdings."))
                } else {
                    ScrollView {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 16)], spacing: 16) {
                            ForEach(data.years, id: \.self) { year in yearSummary(year) }
                        }.padding(2)
                    }
                }
            } else if navigation.level == .year {
                ScrollView { yearPanel(navigation.year).padding(2) }
            } else {
                ScrollView {
                    monthGrid
                }
            }
        }
        .padding(.horizontal)
    }

    private var toolbar: some View {
        ViewThatFits(in: .horizontal) {
            HStack { breadcrumbs; Spacer(); navigationControls; levelPicker }
            VStack(alignment: .leading, spacing: 10) {
                breadcrumbs
                HStack { navigationControls; Spacer(); levelPicker }
            }
        }
    }
    private var breadcrumbs: some View {
        HStack(spacing: 6) {
            Button("All years") { navigation.level = .years }.buttonStyle(.link)
            if navigation.level != .years {
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                Button(String(navigation.year)) { navigation.level = .year }.buttonStyle(.link)
            }
            if navigation.level == .month {
                Image(systemName: "chevron.right").foregroundStyle(.secondary)
                Text(CalendarMonth(year: navigation.year, month: navigation.month).title)
            }
        }.font(.headline)
    }
    private var navigationControls: some View {
        HStack(spacing: 6) {
            if navigation.level != .years {
                Button { navigation.move(-1) } label: { Image(systemName: "chevron.left") }
                    .accessibilityLabel("Previous period")
                Button { navigation.move(1) } label: { Image(systemName: "chevron.right") }
                    .accessibilityLabel("Next period")
            }
            Button("Today") {
                let today = MarketDay(date: Date())
                navigation.year = today.year; navigation.month = today.month
                navigation.level = .month; navigation.selectedDay = today
            }
        }
    }
    private var levelPicker: some View {
        Picker("Calendar detail", selection: $navigation.level) {
            ForEach(CashFlowCalendarNavigation.Level.allCases, id: \.self) { Text($0.rawValue).tag($0) }
        }.pickerStyle(.segmented).labelsHidden().fixedSize()
    }
    private var exclusionNotice: some View {
        CashFlowExclusionNotice(exclusions: data.exclusions, review: reviewTerms)
    }
    private func totals(_ value: CalendarTotals) -> some View {
        CashFlowTotalsView(coupons: value.coupons, repayments: value.repayments)
    }
    private func yearSummary(_ year: Int) -> some View {
        let value = CalendarTotals(data.receipts.filter { $0.paymentDay.year == year })
        return Button {
            navigation.year = year; navigation.level = .year; navigation.selectedDay = nil
        } label: {
            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .firstTextBaseline) {
                    Text(String(year)).font(.system(size: 28, weight: .semibold))
                    Spacer()
                    Image(systemName: "chevron.right").font(.callout)
                }
                Text(money(value.total)).font(.title2).fontWeight(.medium).monospacedDigit()
                    .lineLimit(1).minimumScaleFactor(0.8)
                Divider()
                VStack(spacing: 8) {
                    HStack {
                        Text("Coupons")
                        Spacer(minLength: 8)
                        Text(money(value.coupons)).monospacedDigit()
                    }
                    HStack {
                        Text("Repayments")
                        Spacer(minLength: 8)
                        Text(money(value.repayments)).monospacedDigit()
                    }
                }.font(.callout).lineLimit(1).minimumScaleFactor(0.8)
            }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(.white)
                .background(AppTheme.tileBackground, in: RoundedRectangle(cornerRadius: 10))
                .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityLabel("Open year \(year)")
            .accessibilityValue("\(money(value.total)) total receipts")
    }
    private func yearPanel(_ year: Int) -> some View {
        let receipts = data.receipts.filter { $0.paymentDay.year == year }
        return VStack(alignment: .leading, spacing: 14) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 18)], spacing: 22) {
                ForEach(1...12, id: \.self) { month in
                    Button {
                        navigation.year = year; navigation.month = month
                        navigation.level = .month; navigation.selectedDay = nil
                    } label: {
                        miniMonth(year: year, month: month, receipts: receipts)
                    }.buttonStyle(.plain)
                        .accessibilityLabel("Open \(CalendarMonth(year: year, month: month).title) \(year)")
                }
            }
        }.padding(18)
            .background(CashFlowStyle.surface, in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color(nsColor: .separatorColor), lineWidth: 0.5))
    }
    private func miniMonth(year: Int, month: Int, receipts: [CalendarReceipt]) -> some View {
        let model = CalendarMonth(year: year, month: month)
        let values = receipts.filter { $0.paymentDay.month == month }
        let days = Set(values.map(\.paymentDay))
        return VStack(alignment: .leading, spacing: 6) {
            HStack { Text(model.title).fontWeight(.semibold); Spacer() }
            weekdays(compact: true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 1), count: 7), spacing: 3) {
                ForEach(Array(model.days.enumerated()), id: \.offset) { _, day in
                    Text(day.map { String($0.day) } ?? " ")
                        .font(.system(size: 12)).monospacedDigit()
                        .frame(maxWidth: .infinity, minHeight: 18)
                        .background(day.map { days.contains($0) } == true ? Color.blue.opacity(0.35) : .clear, in: Circle())
                        .foregroundStyle(day == MarketDay(date: Date()) ? Color.orange : Color.primary)
                }
            }
            Text(money(CalendarTotals(values).total)).font(.callout).fontWeight(.medium).monospacedDigit()
                .foregroundStyle(values.isEmpty ? .secondary : .primary)
            Text("Coupons \(money(CalendarTotals(values).coupons))").foregroundStyle(.green)
            Text("Repayments \(money(CalendarTotals(values).repayments))").foregroundStyle(.blue)
            Text(values.isEmpty ? "No payments" : "\(days.count) payment day\(days.count == 1 ? "" : "s")").foregroundStyle(.secondary)
        }.font(.caption).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
    }
    private func weekdays(compact: Bool) -> some View {
        HStack(spacing: 0) {
            ForEach(Array(["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"].enumerated()), id: \.offset) { _, day in
                Text(compact ? String(day.prefix(1)) : day)
                    .font(compact ? .system(size: 11) : .callout).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
            }
        }
    }
    private var monthGrid: some View {
        let month = CalendarMonth(year: navigation.year, month: navigation.month)
        let byDay = Dictionary(grouping: periodReceipts, by: \.paymentDay)
        return VStack(spacing: 0) {
            weekdays(compact: false).padding(.vertical, 8)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 0), count: 7), spacing: 0) {
                ForEach(Array(month.days.enumerated()), id: \.offset) { _, day in
                    if let day {
                        Button { navigation.selectedDay = day } label: {
                            dayCell(day, receipts: byDay[day] ?? [])
                        }.buttonStyle(.plain).accessibilityLabel("Payments on \(day.rawValue)")
                            .popover(isPresented: Binding(get: { navigation.selectedDay == day }, set: { if !$0 { navigation.selectedDay = nil } })) {
                                ScrollView { dayDetails(day).padding() }.frame(width: 440, height: 440)
                            }
                    } else { Color.clear.frame(height: 98) }
                }
            }
        }.background(CashFlowStyle.surface, in: RoundedRectangle(cornerRadius: 8))
    }
    private func dayCell(_ day: MarketDay, receipts: [CalendarReceipt]) -> some View {
        let value = CalendarTotals(receipts)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(String(day.day)).font(.system(size: 13, weight: .medium))
                    .foregroundStyle(day == MarketDay(date: Date()) ? Color.accentColor : Color.primary)
                Spacer(minLength: 0)
                if receipts.contains(where: { $0.conditional || $0.rateSource == .projected }) {
                    Image(systemName: "clock").foregroundStyle(.secondary).font(.caption)
                }
            }
            if !receipts.isEmpty {
                ViewThatFits(in: .horizontal) {
                    Text(money(value.total)).fixedSize()
                    Text(value.total.formatted(.currency(code: "EUR").notation(.compactName).precision(.fractionLength(0)))).fixedSize()
                }.font(.system(size: 13, weight: .semibold)).monospacedDigit()
                Text("\(receipts.count) payment\(receipts.count == 1 ? "" : "s")").font(.system(size: 12)).foregroundStyle(.secondary)
                HStack(spacing: 5) {
                    if receipts.contains(where: { $0.kind == .interest }) {
                        Image(systemName: "circle.fill").foregroundStyle(CashFlowStyle.coupon).accessibilityLabel("Coupons")
                    }
                    if receipts.contains(where: { $0.kind == .maturity }) {
                        Image(systemName: "square.fill").foregroundStyle(CashFlowStyle.repayment).accessibilityLabel("Repayments")
                    }
                }.font(.system(size: 6))
            }
            Spacer(minLength: 0)
        }.padding(8).frame(maxWidth: .infinity, minHeight: 98, maxHeight: 98, alignment: .topLeading)
            .background(navigation.selectedDay == day ? Color.accentColor.opacity(0.12) : .clear)
            .overlay(Rectangle().stroke(navigation.selectedDay == day ? Color.blue : Color.secondary.opacity(0.18), lineWidth: 0.5))
            .contentShape(Rectangle())
    }
    private func dayDetails(_ day: MarketDay) -> some View {
        let receipts = data.receipts.filter { $0.paymentDay == day }
        let instruments = Dictionary(grouping: receipts, by: \.isin)
        return VStack(alignment: .leading, spacing: 12) {
            Text(Formatters.marketMediumDate.string(from: day.instant)).font(.title2).fontWeight(.semibold)
            if receipts.isEmpty { Text("No payments on this day.").foregroundStyle(.secondary) }
            else {
                totals(CalendarTotals(receipts))
                ForEach(instruments.keys.sorted(), id: \.self) { isin in
                    let values = instruments[isin] ?? []
                    DisclosureGroup {
                        ForEach(Dictionary(grouping: values, by: \.purchaseID).keys.sorted(by: { $0.uuidString < $1.uuidString }), id: \.self) { id in
                            let purchase = values.filter { $0.purchaseID == id }
                            if let first = purchase.first {
                                VStack(alignment: .leading, spacing: 5) {
                                    Text("\(first.bank) · acquired \(first.acquisitionDay.rawValue)").fontWeight(.semibold)
                                    Text("Nominal \(preciseMoney(first.nominal)) · purchase cost \(preciseMoney(first.cost))")
                                    ForEach(purchase) { receipt in
                                        Text("\(receipt.kind == .interest ? "Coupon" : "Repayment"): \(preciseMoney(receipt.amount))")
                                        if receipt.kind == .maturity {
                                            Text("Gain/loss on purchase: \(preciseMoney(receipt.amount - receipt.cost)) (included in repayment)").foregroundStyle(.secondary)
                                        }
                                        if receipt.contractualDay != receipt.paymentDay {
                                            Text("Contractual date: \(receipt.contractualDay.rawValue)").foregroundStyle(.secondary)
                                        }
                                    }
                                }.font(.callout).padding(.vertical, 6)
                            }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(values.first?.name ?? isin).fontWeight(.semibold)
                                Spacer(); Text(money(CalendarTotals(values).total)).monospacedDigit()
                            }
                            Text("\(isin) · \(Set(values.map(\.purchaseID)).count) purchases · \(Set(values.map(\.bank)).sorted().joined(separator: ", "))")
                                .font(.caption).foregroundStyle(.secondary)
                            if values.contains(where: { $0.rateSource == .projected }) {
                                Text("Projected coupon · frozen market snapshot").font(.caption).foregroundStyle(.blue)
                            }
                            if values.contains(where: \.conditional) {
                                Text("Conditional payment · receipt is not guaranteed").font(.caption).foregroundStyle(.orange)
                            }
                            ForEach(Set(values.flatMap(\.warnings)).sorted(), id: \.self) { warning in
                                Text(warning).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }.padding(12).background(Color(nsColor: .controlBackgroundColor).opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
                }
            }
        }.padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func money(_ amount: Double) -> String {
        amount.formatted(.currency(code: "EUR").precision(.fractionLength(0)))
    }
    private func preciseMoney(_ amount: Double) -> String {
        amount.formatted(.currency(code: "EUR").precision(.fractionLength(2)))
    }
}
