import SwiftUI
import CoreData
import Charts

struct ReportingView: View {
    @Binding var selectedDepotBank: String
    var today = MarketDay(date: Date())
    var reviewTerms: (() -> Void)? = nil
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \BondEntity.issuer, ascending: true)]) private var bonds: FetchedResults<BondEntity>
    @AppStorage("reporting.annualInterestTarget") private var annualTarget = 150000.0
    @State private var showForecastDetails = false
    private var banks: [String] { Set(bonds.map(\.depotBank) + [selectedDepotBank]).subtracting(["All"]).sorted() }
    private var validTarget: Bool { annualTarget.isFinite && annualTarget >= 0 }

    init(selectedDepotBank: Binding<String>, today: MarketDay = MarketDay(date: Date()),
         reviewTerms: (() -> Void)? = nil, preferences: UserDefaults = .standard) {
        _selectedDepotBank = selectedDepotBank
        self.today = today
        self.reviewTerms = reviewTerms
        _annualTarget = AppStorage(wrappedValue: 150000.0, "reporting.annualInterestTarget", store: preferences)
    }

    var body: some View {
        let report = PortfolioReportData.build(bonds: Array(bonds), bank: selectedDepotBank, today: today)
        GeometryReader { geometry in
            VStack(spacing: 0) {
                HStack {
                    Text("My Reporting").font(.system(.largeTitle, design: .rounded)).foregroundStyle(.white)
                    Spacer()
                }.padding().background(AppTheme.tileBackground)
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        scope(report)
                        if !report.exclusions.isEmpty { CashFlowExclusionNotice(exclusions: report.exclusions, review: reviewTerms) }
                        if report.holdingCount == 0 {
                            ContentUnavailableView("No active bonds", systemImage: "chart.bar",
                                description: Text("Choose another bank or add a bond to see portfolio reports."))
                        } else {
                            interestChart(report)
                            if geometry.size.width >= 900 {
                                HStack(alignment: .top, spacing: 16) {
                                    maturityTable(report)
                                    issuerTable(report)
                                }
                            } else {
                                VStack(spacing: 16) { maturityTable(report); issuerTable(report) }
                            }
                        }
                    }.padding()
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
            .background(AppTheme.panelBackground)
    }

    private func scope(_ report: PortfolioReportData) -> some View {
        ViewThatFits(in: .horizontal) {
            HStack { bankPicker; Spacer(); scopeSummary(report) }
            VStack(alignment: .leading, spacing: 8) { bankPicker; scopeSummary(report) }
        }
    }
    private var bankPicker: some View {
        Picker("Depot Bank", selection: $selectedDepotBank) {
            Text("All").tag("All")
            ForEach(banks, id: \.self) { Text($0).tag($0) }
        }.fixedSize()
    }
    private func scopeSummary(_ report: PortfolioReportData) -> some View {
        VStack(alignment: .trailing, spacing: 3) {
            Text("\(report.holdingCount) active holding\(report.holdingCount == 1 ? "" : "s") · \(CashFlowStyle.money(report.principal)) nominal").fontWeight(.medium)
            Text("As of " + Formatters.marketMediumDate.string(from: today.instant)).font(.caption)
        }.monospacedDigit()
    }
    private func interestChart(_ report: PortfolioReportData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            ViewThatFits(in: .horizontal) {
                HStack { Text("Expected Interest by Year").font(.title2).fontWeight(.semibold); Spacer(); targetControl }
                VStack(alignment: .leading, spacing: 8) { Text("Expected Interest by Year").font(.title2).fontWeight(.semibold); targetControl }
            }
            Text("Remaining expected interest: " + CashFlowStyle.money(report.interest.reduce(0) { $0 + $1.amount })).font(.headline).monospacedDigit()
            if report.interest.isEmpty {
                Text("No approved coupon payments remain. Nominal exposure is still shown below.").padding(.vertical)
            } else {
                GeometryReader { geometry in
                    ScrollView(.horizontal) {
                        Chart {
                            ForEach(report.interest) { row in
                                BarMark(x: .value("Year", String(row.year)), y: .value("Expected interest", row.amount))
                                    .foregroundStyle(AppTheme.tileBackground)
                                    .accessibilityLabel("Expected interest in \(row.year)")
                                    .accessibilityValue(CashFlowStyle.money(row.amount, precise: true))
                            }
                            if validTarget {
                                RuleMark(y: .value("Annual target", annualTarget))
                                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [6, 4])).foregroundStyle(.white)
                            }
                        }
                        .chartYAxis {
                            AxisMarks(position: .leading) { _ in
                                AxisGridLine()
                                AxisValueLabel(format: .currency(code: "EUR").notation(.compactName))
                            }
                        }
                        .chartXAxisLabel("Payment year")
                        .frame(width: max(geometry.size.width, CGFloat(report.interest.count) * 48), height: 260)
                        .padding(.top, 10)
                    }
                }.frame(height: 280)
            }
            Text("\(String(today.year)) includes payments from the report date onward, not a full-year estimate.").font(.caption)
            forecastDetails(report)
        }.padding(16).background(CashFlowStyle.surface, in: RoundedRectangle(cornerRadius: 10))
    }
    @ViewBuilder private func forecastDetails(_ report: PortfolioReportData) -> some View {
        let warnings = Set(report.interestReceipts.flatMap(\.warnings)).sorted()
        let projected = report.interestReceipts.contains { $0.rateSource == .projected }
        let conditional = report.interestReceipts.contains(where: \.conditional)
        if projected || conditional || !warnings.isEmpty {
            DisclosureGroup(isExpanded: $showForecastDetails) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 8) {
                        if projected { Label("Projected coupons use frozen market data.", systemImage: "chart.line.uptrend.xyaxis") }
                        if conditional { Label("Conditional payments may be deferred.", systemImage: "clock") }
                        ForEach(warnings, id: \.self) { Text($0).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 160).padding(.top, 8)
            } label: {
                Text("Forecast details").frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle()).onTapGesture { showForecastDetails.toggle() }
            }.font(.callout)
        }
    }
    private var targetControl: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text("Annual target (EUR)").font(.callout)
                TextField("Annual target", value: $annualTarget, format: .number.precision(.fractionLength(0)))
                    .textFieldStyle(.roundedBorder).frame(width: 110).monospacedDigit()
                    .accessibilityLabel("Annual interest target in EUR")
            }
            if !validTarget { Text("Enter a non-negative amount.").font(.caption) }
        }
    }
    private func maturityTable(_ report: PortfolioReportData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Maturity Schedule").font(.title2).fontWeight(.semibold)
            HStack {
                Text("Year").frame(maxWidth: .infinity, alignment: .leading)
                Text("Principal (EUR)").frame(width: 110, alignment: .trailing)
                Text("Share").frame(width: 55, alignment: .trailing)
                Text("Purchase YTM").frame(width: 100, alignment: .trailing)
            }.font(.caption).fontWeight(.semibold).padding(.horizontal, 8)
            VStack(spacing: 4) {
                ForEach(Array(report.maturities.enumerated()), id: \.element.id) { index, row in
                    HStack {
                        Text(String(row.year)).frame(maxWidth: .infinity, alignment: .leading)
                        Text(CashFlowStyle.money(row.principal)).frame(width: 110, alignment: .trailing)
                        Text(row.share, format: .percent.precision(.fractionLength(1))).frame(width: 55, alignment: .trailing)
                        Text(yieldText(row)).frame(width: 100, alignment: .trailing)
                            .help("Yield available for \(CashFlowStyle.money(row.yieldCoveredPrincipal)) of \(CashFlowStyle.money(row.principal)) nominal.")
                    }.font(.callout).monospacedDigit().padding(8)
                        .background(index.isMultiple(of: 2) ? AppTheme.panelBackground : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            if report.missingYieldCount > 0 {
                Label("\(report.missingYieldCount) holdings lack a validated yield. An asterisk marks partial yield coverage.", systemImage: "exclamationmark.triangle").font(.caption)
            }
            Text("Principal uses contractual maturity years. Purchase YTM is weighted by nominal principal across holdings with a validated yield.").font(.caption)
        }.padding(16).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(CashFlowStyle.surface, in: RoundedRectangle(cornerRadius: 10))
    }
    private func yieldText(_ row: PortfolioReportData.Maturity) -> String {
        guard let value = row.purchaseYTM else { return "–" }
        return String(format: "%.2f%%", value) + (row.yieldCoveredPrincipal < row.principal ? " *" : "")
    }
    private func issuerTable(_ report: PortfolioReportData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Issuer Breakdown").font(.title2).fontWeight(.semibold)
            HStack {
                Text("Issuer").frame(maxWidth: .infinity, alignment: .leading)
                Text("Principal (EUR)").frame(width: 110, alignment: .trailing)
                Text("Share").frame(width: 55, alignment: .trailing)
            }.font(.caption).fontWeight(.semibold).padding(.horizontal, 8)
            VStack(spacing: 4) {
                ForEach(Array(report.issuers.enumerated()), id: \.element.id) { index, row in
                    HStack(alignment: .firstTextBaseline) {
                        Text(row.name).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
                        Text(CashFlowStyle.money(row.principal)).frame(width: 110, alignment: .trailing)
                        Text(row.share, format: .percent.precision(.fractionLength(1))).frame(width: 55, alignment: .trailing)
                    }.font(.callout).monospacedDigit().padding(8)
                        .background(index.isMultiple(of: 2) ? AppTheme.panelBackground : .clear, in: RoundedRectangle(cornerRadius: 6))
                }
            }
            Text("Includes all purchases of each issuer, sorted by nominal exposure. Shares use the selected portfolio's total nominal principal.").font(.caption)
        }.padding(16).frame(maxWidth: .infinity, alignment: .topLeading)
            .background(CashFlowStyle.surface, in: RoundedRectangle(cornerRadius: 10))
    }
}
