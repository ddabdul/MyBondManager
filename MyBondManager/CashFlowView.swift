import SwiftUI
import CoreData

struct CashFlowView: View {
    @Binding var selectedDepotBank: String
    var reviewTerms: (() -> Void)? = nil
    var displayModeSelection: Binding<String>? = nil
    var navigationSelection: Binding<CashFlowCalendarNavigation>? = nil
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \BondEntity.depotBank, ascending: true)]) private var allBonds: FetchedResults<BondEntity>
    @State private var localDisplayMode = "List"
    @State private var allFuturePayments = true
    @State private var pastExpectedPayments = false
    @State private var previousDateRange: (start: Date, end: Date)?
    @State private var calendarNavigation = CashFlowCalendarNavigation()
    @State private var searchText = ""
    @State private var paymentKind: BondPayment.Kind?
    @State private var startDate = Date()
    @State private var endDate = MarketDay.calendar.date(byAdding: .year, value: 1, to: Date())!
    private var displayMode: String { displayModeSelection?.wrappedValue ?? localDisplayMode }
    private var lastPastDate: Date { MarketDay.calendar.date(byAdding: .day, value: -1, to: MarketDay(date: Date()).instant)! }
    private var banks: [String] { Set(allBonds.map(\.depotBank) + [selectedDepotBank]).subtracting(["All"]).sorted() }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                title
                Spacer()
            }
            .padding()
            .background(AppTheme.tileBackground)
            ViewThatFits(in: .horizontal) {
                HStack { workflow; Spacer(); viewPicker }
                VStack(alignment: .leading, spacing: 10) { workflow; viewPicker }
            }.padding(.horizontal)
            filters
            if pastExpectedPayments {
                PastPaymentsView(from: MarketDay(date: startDate), through: MarketDay(date: endDate),
                    bank: selectedDepotBank, search: searchText, kind: paymentKind)
            } else {
                CashFlowUpcomingResults(searchText: searchText, bank: selectedDepotBank,
                    from: allFuturePayments ? MarketDay(date: Date()) : max(MarketDay(date: Date()), MarketDay(date: startDate)),
                    through: allFuturePayments ? try! MarketDay("2199-12-31") : MarketDay(date: endDate), kind: paymentKind,
                    navigation: navigationSelection ?? $calendarNavigation, reviewTerms: reviewTerms, displayMode: displayMode)
            }
        }.padding(.bottom, 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(CashFlowStyle.background)
        .onChange(of: pastExpectedPayments) { _, past in
            if past {
                previousDateRange = (startDate, endDate)
                endDate = lastPastDate
                startDate = MarketDay.calendar.date(byAdding: .year, value: -1, to: lastPastDate)!
            } else if let previousDateRange {
                startDate = previousDateRange.start; endDate = previousDateRange.end
                self.previousDateRange = nil
            }
        }
        .onChange(of: startDate) { if startDate > endDate { endDate = startDate } }
        .onChange(of: endDate) { if endDate < startDate { startDate = endDate } }
    }
    private var title: some View { Text("My Cash Flows").font(.system(.largeTitle, design: .rounded)).foregroundStyle(.white) }
    private var workflow: some View {
        Picker("Payment period", selection: $pastExpectedPayments) {
            Text("Upcoming").tag(false)
            Text("Past report").tag(true)
        }.pickerStyle(.segmented).labelsHidden().fixedSize()
    }
    @ViewBuilder private var viewPicker: some View {
        if !pastExpectedPayments {
            Picker("Cash-flow view", selection: displayModeSelection ?? $localDisplayMode) {
                Text("List").tag("List")
                Text("Calendar").tag("Calendar")
            }.pickerStyle(.segmented).labelsHidden().fixedSize()
        }
    }
    private var filters: some View {
        VStack(alignment: .leading, spacing: 10) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { bankPicker; search; typePicker }
                VStack(alignment: .leading, spacing: 10) { search; HStack { bankPicker; Spacer(); typePicker } }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { period; dates }
                VStack(alignment: .leading, spacing: 8) { period; dates }
            }
        }.padding(.horizontal)
    }
    private var bankPicker: some View {
        Picker("Bank", selection: $selectedDepotBank) {
            Text("All").tag("All")
            ForEach(banks, id: \.self) { Text($0).tag($0) }
        }.fixedSize()
    }
    private var search: some View { TextField("Search bonds…", text: $searchText).textFieldStyle(.roundedBorder).frame(minWidth: 160) }
    private var typePicker: some View {
        Picker("Payment type", selection: $paymentKind) {
            Text("All").tag(BondPayment.Kind?.none)
            Text("Coupons").tag(BondPayment.Kind?.some(.interest))
            Text("Repayments").tag(BondPayment.Kind?.some(.maturity))
        }.fixedSize()
    }
    @ViewBuilder private var period: some View {
        if pastExpectedPayments {
            Label("Past expected payments", systemImage: "clock.arrow.circlepath").font(.callout).foregroundStyle(.secondary)
        } else {
            Picker("Period", selection: $allFuturePayments) {
                Text("All future payments").tag(true)
                Text("Custom dates").tag(false)
            }.fixedSize()
        }
    }
    @ViewBuilder private var dates: some View {
        if pastExpectedPayments {
            HStack {
                DatePicker("From", selection: $startDate, in: ...lastPastDate, displayedComponents: .date)
                DatePicker("To", selection: $endDate, in: ...lastPastDate, displayedComponents: .date)
            }.environment(\.calendar, MarketDay.calendar).environment(\.timeZone, MarketDay.calendar.timeZone).fixedSize()
        } else if !allFuturePayments {
            HStack {
                DatePicker("From", selection: $startDate, in: MarketDay(date: Date()).instant..., displayedComponents: .date)
                DatePicker("To", selection: $endDate, in: MarketDay(date: Date()).instant..., displayedComponents: .date)
            }.environment(\.calendar, MarketDay.calendar).environment(\.timeZone, MarketDay.calendar.timeZone).fixedSize()
        }
    }
}

private struct CashFlowUpcomingResults: View {
    @FetchRequest private var bonds: FetchedResults<BondEntity>
    let from: MarketDay
    let through: MarketDay
    let kind: BondPayment.Kind?
    @Binding var navigation: CashFlowCalendarNavigation
    let reviewTerms: (() -> Void)?
    let displayMode: String
    init(searchText: String, bank: String, from: MarketDay, through: MarketDay, kind: BondPayment.Kind?,
         navigation: Binding<CashFlowCalendarNavigation>, reviewTerms: (() -> Void)?, displayMode: String) {
        var predicates: [NSPredicate] = []
        if bank != "All" { predicates.append(NSPredicate(format: "depotBank == %@", bank)) }
        if !searchText.isEmpty { predicates.append(NSPredicate(format: "name CONTAINS[cd] %@", searchText)) }
        _bonds = FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \BondEntity.name, ascending: true)],
            predicate: NSCompoundPredicate(andPredicateWithSubpredicates: predicates))
        self.from = from; self.through = through; self.kind = kind
        _navigation = navigation; self.reviewTerms = reviewTerms; self.displayMode = displayMode
    }
    var body: some View {
        let data = CashFlowCalendarData.build(bonds: Array(bonds), from: from, through: through, kind: kind)
        if displayMode == "Calendar" { CashFlowCalendarView(data: data, navigation: $navigation, reviewTerms: reviewTerms) }
        else { CashFlowReceiptList(data: data, reviewTerms: reviewTerms) }
    }
}
