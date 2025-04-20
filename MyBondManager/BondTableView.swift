//  BondTableView.swift
//  MyBondManager
//
//  Created by Olivier on 19/04/2025.
//

import SwiftUI

// —————————————————————————————
// MARK: – Bond + Formatters
// —————————————————————————————
extension Bond {
    // Reusable currency formatter
    private static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f
    }()

    /// “€98 000”
    var acquisitionPriceFormatted: String {
        Self.currency.string(from: NSNumber(value: initialPrice)) ?? "–"
    }

    /// “€100 000”
    var parValueFormatted: String {
        Self.currency.string(from: NSNumber(value: parValue)) ?? "–"
    }

    /// “2.50%”
    var couponFormatted: String {
        String(format: "%.2f%%", couponRate)
    }

    /// “2.97%”  (assumes `yieldAtAcquisition` is 0.0297)
    var ytmFormatted: String {
        String(format: "%.2f%%", yieldAtAcquisition * 100)
    }
}

// date formatter
private let bondDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    return f
}()

// summarization currency formatter
private let summaryCurrencyFormatter: NumberFormatter = {
    let f = NumberFormatter()
    f.numberStyle = .currency
    f.maximumFractionDigits = 0
    f.minimumFractionDigits = 0
    return f
}()

// —————————————————————————————
// MARK: – BondSummary Model
// —————————————————————————————
struct BondSummary: Identifiable {
    let id: String              // ISIN
    let name: String
    let issuer: String
    let couponFormatted: String
    let maturityDate: Date
    let totalParValue: Double
    let formattedTotalParValue: String
    let recordCount: Int
    let records: [Bond]

    init(records: [Bond]) {
        let first = records.first!
        self.id = first.isin
        self.name = first.name
        self.issuer = first.issuer
        self.couponFormatted = first.couponFormatted
        self.maturityDate = first.maturityDate
        self.totalParValue = records.reduce(0) { $0 + $1.parValue }
        self.formattedTotalParValue = summaryCurrencyFormatter.string(
            from: NSNumber(value: totalParValue)
        ) ?? "–"
        self.recordCount = records.count
        self.records = records
    }
}

// —————————————————————————————
// MARK: – Detail View for Summarized Bond
// —————————————————————————————
struct BondSummaryDetailView: View {
    let summary: BondSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text(summary.name)
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            Divider()
            VStack(alignment: .leading, spacing: 8) {
                Text("Issuer: \(summary.issuer)")
                Text("Coupon: \(summary.couponFormatted)")
                Text("Maturity: \(bondDateFormatter.string(from: summary.maturityDate))")
                Text("Total Nominal: \(summary.formattedTotalParValue)")
                if summary.recordCount > 1 {
                    Text("(Summarized \(summary.recordCount) records)")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            }
            Divider()
            Text("Details:")
                .font(.headline)
            ForEach(summary.records) { bond in
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Nominal:")
                        Spacer()
                        Text(bond.parValueFormatted)
                    }
                    HStack {
                        Text("Acquisition Price:")
                        Spacer()
                        Text(bond.acquisitionPriceFormatted)
                    }
                    HStack {
                        Text("Acquisition Date:")
                        Spacer()
                        Text(bond.acquisitionDate, formatter: bondDateFormatter)
                    }
                    HStack {
                        Text("Depot Bank:")
                        Spacer()
                        Text(bond.depotBank)
                    }
                    HStack {
                        Text("YTM:")
                        Spacer()
                        Text(bond.ytmFormatted)
                    }
                }
                .padding(.vertical, 4)
                Divider()
            }
            Spacer()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }
}

// —————————————————————————————
// MARK: – BondTableView
// —————————————————————————————
struct BondTableView: View {
    @ObservedObject var viewModel: BondPortfolioViewModel

    /// drive sorting on summaries
    @State private var sortOrder: [KeyPathComparator<BondSummary>] = [
        .init(\.maturityDate, order: .forward)
    ]

    /// track selected ISIN
    @State private var selectedISIN: String?

    /// grouped summaries
    private var summaries: [BondSummary] {
        Dictionary(grouping: viewModel.bonds, by: \.isin)
            .values
            .map(BondSummary.init)
    }

    /// sorted summaries
    private var sortedSummaries: [BondSummary] {
        summaries.sorted(using: sortOrder)
    }

    /// adapter to pass a BondSummary into the sheet
    private var selectedSummaryForSheet: Binding<BondSummary?> {
        Binding<BondSummary?>(
            get: {
                guard let isin = selectedISIN else { return nil }
                return sortedSummaries.first { $0.id == isin }
            },
            set: { new in
                selectedISIN = new?.id
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            bondTable
        }
        .frame(minWidth: 800, minHeight: 400)
        .sheet(item: selectedSummaryForSheet) { summary in
            BondSummaryDetailView(summary: summary)
        }
    }

    // ————————————————————————
    // Title bar with gradient
    // ————————————————————————
    private var titleBar: some View {
        HStack {
            Text("My Bond Portfolio")
                .font(.largeTitle)
                .foregroundColor(.white)
            Spacer()
        }
        .padding()
        .background(
            LinearGradient(
                gradient: Gradient(colors: [
                    Color.purple.opacity(0.8),
                    Color.blue.opacity(0.8)
                ]),
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    // ————————————————————————
    // The Table
    // ————————————————————————
    private var bondTable: some View {
        Table(
            sortedSummaries,
            selection: $selectedISIN,
            sortOrder: $sortOrder
        ) {
            // 1) Bond Name
            TableColumn("Bond Name", value: \.name) { summary in
                Text(summary.name)
                    .multilineTextAlignment(.leading)
            }
            .width(min: 150, ideal: 200, max: 300)

            // 2) Issuer
            TableColumn("Issuer", value: \.issuer) { summary in
                Text(summary.issuer)
                    .multilineTextAlignment(.leading)
            }
            .width(min: 120, ideal: 160, max: 240)

            // 3) Nominal (summed)
            TableColumn("Nominal", value: \.totalParValue) { summary in
                HStack(spacing: 2) {
                    Text(summary.formattedTotalParValue)
                        .multilineTextAlignment(.trailing)
                    if summary.recordCount > 1 {
                        Text("+")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 100)

            // 4) Coupon
            TableColumn("Coupon", value: \.couponFormatted) { summary in
                Text(summary.couponFormatted)
                    .multilineTextAlignment(.trailing)
            }
            .width(min: 60, ideal: 80)

            // 5) Maturity Date
            TableColumn("Mat. Date", value: \.maturityDate) { summary in
                Text(summary.maturityDate, formatter: bondDateFormatter)
                    .multilineTextAlignment(.center)
            }
            .width(min: 80)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }
}

// —————————————————————————————
// MARK: – Preview
// —————————————————————————————
struct BondTableView_Previews: PreviewProvider {
    static var previews: some View {
        BondTableView(viewModel: BondPortfolioViewModel())
    }
}
