//  PortfolioSummaryView.swift
//  MyBondManager
//  Adjusted to CoreData
//  Created by Olivier on 26/04/2025.
//  Updated 11/05/2025 – restore full bond tiles + top combined metrics
//

import SwiftUI
import CoreData

struct PortfolioSummaryView: View {
    // MARK: – Core Data Fetch
    @Environment(\.managedObjectContext) private var moc

    /// Midnight of the current day, so bonds maturing *today* are still included
    private static var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    // — Bonds
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BondEntity.acquisitionDate, ascending: false)],
        predicate: NSPredicate(format: "maturityDate >= %@", Self.startOfToday as NSDate),
        animation: .default
    )
    private var bondEntities: FetchedResults<BondEntity>

    // — ETFs
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ETFEntity.etfName, ascending: true)],
        animation: .default
    )
    private var etfEntities: FetchedResults<ETFEntity>

    // MARK: – UI State
    @State private var selectedDepotBank: String   = "All"
    @State private var potentialPrice: String      = ""
    @State private var potentialCouponRate: String = ""
    @State private var potentialMaturityDate: Date = Date()
    @State private var calculatedYTM: Double?      = nil

    // MARK: – Bond Helpers

    private var depotBanks: [String] {
        let banks = Set(bondEntities.map { $0.depotBank })
        return ["All"] + banks.sorted()
    }

    private var filteredBonds: [BondEntity] {
        guard selectedDepotBank != "All" else { return Array(bondEntities) }
        return bondEntities.filter { $0.depotBank == selectedDepotBank }
    }

    private var futureCashFlows: [CashFlowEntity] {
        let now = Date()
        return filteredBonds
            .flatMap { $0.cashFlows ?? [] }
            .filter { $0.date >= now }
    }

    // MARK: – Bond Metrics

    private var numberOfBonds: Int { filteredBonds.count }

    private var totalAcquisitionCost: Double {
        filteredBonds.reduce(0) { $0 + $1.initialPrice }
    }

    private var totalPrincipal: Double {
        filteredBonds.reduce(0) { $0 + $1.parValue }
    }

    private var averageMaturityYears: Double {
        guard !filteredBonds.isEmpty else { return 0 }
        let totalYears = filteredBonds.reduce(0.0) { sum, bond in
            sum + bond.maturityDate
                    .timeIntervalSince(Date())
                    / (365 * 24 * 3600)
        }
        return totalYears / Double(filteredBonds.count)
    }

    private var totalInterestExpected: Double {
        futureCashFlows
            .filter { $0.natureEnum == .interest }
            .reduce(0) { $0 + $1.amount }
    }

    private var totalCapitalGainExpected: Double {
        futureCashFlows
            .filter { $0.natureEnum == .capitalGains }
            .reduce(0) { $0 + $1.amount }
    }

    private var totalCapitalLossExpected: Double {
        futureCashFlows
            .filter { $0.natureEnum == .capitalLoss }
            .reduce(0) { $0 + $1.amount }
    }

    /// Sum of all future interest + capital-gains – capital-loss cash-flows
    private var totalExpectedProfitCF: Double {
        totalInterestExpected
      + totalCapitalGainExpected
      - totalCapitalLossExpected
    }

    private var nextMaturingBond: BondEntity? {
        filteredBonds.min { $0.maturityDate < $1.maturityDate }
    }

    private func nextCouponDate(for bond: BondEntity) -> Date? {
        let cal = Calendar.current
        let comps = cal.dateComponents([.month, .day], from: bond.maturityDate)
        let candidate = DateComponents(
            year:  cal.component(.year, from: Date()),
            month: comps.month,
            day:   comps.day
        )
        guard let thisYear = cal.date(from: candidate) else { return nil }
        return thisYear < Date()
            ? cal.date(byAdding: .year, value: 1, to: thisYear)
            : thisYear
    }

    private var nextCouponInfo: String {
        guard
            let date = filteredBonds
                .compactMap(nextCouponDate(for:))
                .min()
        else { return "–" }

        let bonds = filteredBonds.filter { nextCouponDate(for: $0) == date }
        let payer = bonds.count == 1
            ? bonds.first!.name
            : (bonds.isEmpty ? "–" : "Multiple")
        let totalAmt = bonds.reduce(0) { sum, b in
            sum + b.parValue * (b.couponRate / 100)
        }
        let totalStr = Formatters.currency
            .string(from: NSNumber(value: totalAmt)) ?? "–"

        return """
        Payer: \(payer)
        Date:  \(Formatters.mediumDate.string(from: date))
        Total: \(totalStr)
        """
    }

    private func calculateYTM() {
        let par = 100.0
        guard
            let price = Double(potentialPrice),
            let rate  = Double(potentialCouponRate)
        else {
            calculatedYTM = nil; return
        }
        let couponAmt = par * rate / 100
        let yrs = potentialMaturityDate
            .timeIntervalSince(Date())
            / (365 * 24 * 3600)
        guard yrs > 0 else {
            calculatedYTM = nil; return
        }
        let numerator   = couponAmt + (par - price) / yrs
        let denominator = (par + price) / 2
        calculatedYTM = (numerator / denominator) * 100
    }

    // MARK: – ETF Metrics

    private var allETFHoldings: [ETFHoldings] {
        etfEntities.flatMap { ($0.etftoholding as? Set<ETFHoldings>) ?? [] }
    }

    private var totalETFInvested: Double {
        allETFHoldings.reduce(0) { sum, h in
            sum + Double(h.numberOfShares) * h.acquisitionPrice
        }
    }

    private var totalETFProfit: Double {
        allETFHoldings.reduce(0) { sum, h in
            let diff = h.holdingtoetf.lastPrice - h.acquisitionPrice
            return sum + Double(h.numberOfShares) * diff
        }
    }

    // MARK: – Combined Tiles

    private var totalCapital: Double {
        totalPrincipal + totalETFInvested
    }

    private var totalGains: Double {
        totalExpectedProfitCF + totalETFProfit
    }

    // MARK: – View Body

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header + Filter
                HStack {
                    Text("Portfolio Summary")
                        .font(.title2).bold()
                    Spacer()
                    Picker("Depot Bank", selection: $selectedDepotBank) {
                        ForEach(depotBanks, id: \.self) {
                            Text($0).tag($0)
                        }
                    }
                    .pickerStyle(MenuPickerStyle())
                    .frame(maxWidth: 150)
                }
                .padding(.bottom, 8)

                // Top Combined Metrics
                HStack(spacing: 12) {
                    MetricView(
                        icon:  "banknote.fill",
                        title: "Total Capital",
                        value: Formatters.currency
                            .string(from: NSNumber(value: totalCapital))
                            ?? "–"
                    )
                    MetricView(
                        icon:  "arrow.up.circle",
                        title: "Total Returns",
                        value: Formatters.currency
                            .string(from: NSNumber(value: totalGains))
                            ?? "–"
                    )
                }

                Divider().background(Color.white.opacity(0.3))

                // Full Bonds Section (8 tiles)
                LazyVGrid(
                    columns: [ GridItem(.flexible()), GridItem(.flexible()) ],
                    spacing: 12
                ) {
                    MetricView(icon: "doc.plaintext",
                               title: "Bonds",
                               value: "\(numberOfBonds)")
                    MetricView(icon: "eurosign.circle",
                               title: "Acquisition",
                               value: Formatters.currency
                                   .string(from: NSNumber(value: totalAcquisitionCost))
                                   ?? "–")
                    MetricView(icon: "banknote",
                               title: "Principal",
                               value: Formatters.currency
                                   .string(from: NSNumber(value: totalPrincipal))
                                   ?? "–")
                    MetricView(icon: "clock.arrow.circlepath",
                               title: "Maturity (yrs)",
                               value: String(format: "%.1f", averageMaturityYears))
                    MetricView(icon: "arrow.down.circle",
                               title: "Exp. Interest",
                               value: Formatters.currency
                                   .string(from: NSNumber(value: totalInterestExpected))
                                   ?? "–")
                    MetricView(icon: "arrow.up.circle",
                               title: "Exp. Capital Gains",
                               value: Formatters.currency
                                   .string(from: NSNumber(value: totalCapitalGainExpected))
                                   ?? "–")
                    MetricView(icon: "arrow.down.circle.fill",
                               title: "Exp. Capital Losses",
                               value: Formatters.currency
                                   .string(from: NSNumber(value: totalCapitalLossExpected))
                                   ?? "–")
                    MetricView(icon: "star.circle",
                               title: "Total Expected Returns",
                               value: Formatters.currency
                                   .string(from: NSNumber(value: totalExpectedProfitCF))
                                   ?? "–")
                }

                Divider().background(Color.white.opacity(0.3))

                // ETF Section (2 tiles)
                LazyVGrid(
                    columns: [ GridItem(.flexible()), GridItem(.flexible()) ],
                    spacing: 12
                ) {
                    MetricView(icon: "chart.bar",
                               title: "ETF Capital Invested",
                               value: Formatters.currency
                                   .string(from: NSNumber(value: totalETFInvested))
                                   ?? "–")
                    MetricView(icon: "chart.pie",
                               title: "ETF Profit",
                               value: Formatters.currency
                                   .string(from: NSNumber(value: totalETFProfit))
                                   ?? "–")
                }

                Divider().background(Color.white.opacity(0.3))

                // Next Maturity Tile
                MetricView(
                    icon:  "flag.checkered",
                    title: "Next Maturity",
                    value: nextMaturingBond.map {
                        "\($0.name)\nDate: \(Formatters.mediumDate.string(from: $0.maturityDate))\nNominal: \(Formatters.currency.string(from: NSNumber(value: $0.parValue)) ?? "–")"
                    } ?? "–"
                )
                .frame(maxWidth: .infinity)

                // Next Coupon Tile
                MetricView(
                    icon:  "calendar.badge.clock",
                    title: "Next Coupon",
                    value: nextCouponInfo
                )
                .frame(maxWidth: .infinity)

                // YTM Estimate Section
                VStack(alignment: .leading, spacing: 12) {
                    Text("Estimate Bond YTM")
                        .font(.headline)

                    HStack(spacing: 12) {
                        TextField("Price", text: $potentialPrice)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                        TextField("Coupon Rate (%)", text: $potentialCouponRate)
                            .textFieldStyle(RoundedBorderTextFieldStyle())
                    }

                    DatePicker("Maturity Date",
                               selection: $potentialMaturityDate,
                               displayedComponents: .date)
                        .datePickerStyle(.compact)

                    Button("Calculate YTM", action: calculateYTM)
                        .buttonStyle(.borderedProminent)

                    if let ytm = calculatedYTM {
                        Text("Yield to Maturity: \(String(format: "%.2f", ytm))%")
                            .font(.subheadline).bold()
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(.ultraThinMaterial)
                        .shadow(color: Color.primary.opacity(0.1),
                                radius: 4, x: 0, y: 2)
                )
                .frame(maxWidth: .infinity)
                .padding(.bottom)
            }
            .padding()
        }
    }
}

// -----------------------------------
// MARK: – MetricView
// -----------------------------------
struct MetricView: View {
    let icon: String
    let title: String
    let value: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.8))
                Text(value)
                    .font(.headline).bold()
                    .foregroundColor(.white)
                    .lineLimit(nil)
            }
            Spacer()
        }
        .padding(12)
        .background(AppTheme.tileBackground)
        .cornerRadius(8)
    }
}
