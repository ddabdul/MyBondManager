//
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
    private static let currencyFormatter: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.maximumFractionDigits = 0
        f.minimumFractionDigits = 0
        return f
    }()

    var acquisitionPriceFormatted: String {
        Self.currencyFormatter.string(from: NSNumber(value: initialPrice)) ?? "–"
    }

    var parValueFormatted: String {
        Self.currencyFormatter.string(from: NSNumber(value: parValue)) ?? "–"
    }

    var couponFormatted: String {
        String(format: "%.2f%%", couponRate)
    }

    var ytmFormatted: String {
        String(format: "%.2f%%", yieldAtAcquisition * 100)
    }
}

// date formatter for both table & detail
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
    let id: String          // the ISIN
    let name: String
    let issuer: String
    let couponRate: Double
    let maturityDate: Date
    let records: [Bond]

    /// Number of underlying records
    var recordCount: Int { records.count }

    /// Sum of all parValues
    var totalNominal: Double { records.reduce(0) { $0 + $1.parValue } }

    /// Formatted total nominal
    var formattedTotalParValue: String {
        summaryCurrencyFormatter
            .string(from: NSNumber(value: totalNominal)) ?? "–"
    }

    /// Re‑use Bond’s coupon formatter
    var couponFormatted: String {
        String(format: "%.2f%%", couponRate)
    }
}


// —————————————————————————————
// MARK: – BondTableView
// —————————————————————————————
struct BondTableView: View {
    @ObservedObject var viewModel: BondPortfolioViewModel

    @State private var sortOrder: [KeyPathComparator<BondSummary>] = [
        .init(\.maturityDate, order: .forward)
    ]
    @State private var selectedSummaryID: String?

    /// Group by ISIN
    private var summaries: [BondSummary] {
        Dictionary(grouping: viewModel.bonds, by: \.isin)
            .map { isin, bonds in
                let first = bonds[0]
                return BondSummary(
                    id: isin,
                    name: first.name,
                    issuer: first.issuer,
                    couponRate: first.couponRate,
                    maturityDate: first.maturityDate,
                    records: bonds
                )
            }
    }

    /// Apply sort
    private var sortedSummaries: [BondSummary] {
        summaries.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            bondTable
        }
        .frame(minWidth: 800, minHeight: 400)
        .sheet(item: Binding<BondSummary?>(
            get: {
                guard let id = selectedSummaryID else { return nil }
                return sortedSummaries.first { $0.id == id }
            },
            set: { new in
                selectedSummaryID = new?.id
            }
        )) { summary in
            BondSummaryDetailView(summary: summary)
        }
    }

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

    private var bondTable: some View {
        Table(sortedSummaries,
              selection: $selectedSummaryID,
              sortOrder: $sortOrder
        ) {

            // 1) Issuer
            TableColumn("Issuer", value: \.issuer) { s in
                Text(s.issuer)
                    .multilineTextAlignment(.leading)
            }
            .width(min: 120, ideal: 160, max: 240)

            // 2) Nominal with “+” on the left
            TableColumn("Nominal", value: \.totalNominal) { s in
                HStack(spacing: 4) {
                    if s.recordCount > 1 {
                        Text("+")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                    Text(s.formattedTotalParValue)
                        .multilineTextAlignment(.trailing)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 100)

            // 3) Coupon
            TableColumn("Coupon", value: \.couponRate) { s in
                Text(s.couponFormatted)
                    .multilineTextAlignment(.trailing)
            }
            .width(min: 60, ideal: 80)

            // 4) Maturity Date
            TableColumn("Maturity Date", value: \.maturityDate) { s in
                Text(s.maturityDate, formatter: bondDateFormatter)
                    .multilineTextAlignment(.center)
            }
            .width(min: 80)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
    }
}


// —————————————————————————————
// MARK: – Detail View for Summarized Bond
// —————————————————————————————
struct BondSummaryDetailView: View {
    let summary: BondSummary
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 16) {
                // Header
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

                // Summary Info
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

                // Detailed Records
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
        }
        .frame(minWidth: 400, minHeight: 300)
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
