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

// —————————————————————————————
// MARK: – Detail View
// —————————————————————————————
struct BondDetailView: View {
    let bond: Bond
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(bond.name)
                    .font(.title2)
                    .bold()
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            Divider()

            Group {
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
            Spacer()
        }
        .padding()
        .frame(minWidth: 400, minHeight: 200)
    }
}

// —————————————————————————————
// MARK: – BondTableView
// —————————————————————————————
struct BondTableView: View {
    @ObservedObject var viewModel: BondPortfolioViewModel

    /// drive sorting
    @State private var sortOrder: [KeyPathComparator<Bond>] = [
        .init(\.maturityDate, order: .forward)
    ]

    /// track the selected bond's ID for selection
    @State private var selectedBondID: Bond.ID?

    /// we sort on‑the‑fly rather than mutating the VM
    private var sortedBonds: [Bond] {
        viewModel.bonds.sorted(using: sortOrder)
    }

    /// binding adapter to show the BondDetailView
    private var selectedBondForSheet: Binding<Bond?> {
        Binding<Bond?>(
            get: {
                guard let id = selectedBondID else { return nil }
                return sortedBonds.first { $0.id == id }
            },
            set: { newBond in
                selectedBondID = newBond?.id
            }
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            bondTable
        }
        .frame(minWidth: 800, minHeight: 400)
        .sheet(item: selectedBondForSheet) { bond in
            BondDetailView(bond: bond)
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
            // re-add your “Add” + “Matured” buttons here…
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
            sortedBonds,
            selection: $selectedBondID,
            sortOrder: $sortOrder
        ) {
            // 1) Bond Name
            TableColumn("Bond Name", value: \.name) { bond in
                Text(bond.name)
                    .multilineTextAlignment(.leading)
            }
            .width(min: 150, ideal: 200, max: 300)

            // 2) Issuer
            TableColumn("Issuer", value: \.issuer) { bond in
                Text(bond.issuer)
                    .multilineTextAlignment(.leading)
            }
            .width(min: 120, ideal: 160, max: 240)

            // 3) Nominal
            TableColumn("Nominal", value: \.parValue) { bond in
                Text(bond.parValueFormatted)
                    .multilineTextAlignment(.trailing)
            }
            .width(min: 80, ideal: 100)

            // 4) Coupon
            TableColumn("Coupon", value: \.couponRate) { bond in
                Text(bond.couponFormatted)
                    .multilineTextAlignment(.trailing)
            }
            .width(min: 60, ideal: 80)

            // 5) Maturity Date
            TableColumn("Mat. Date", value: \.maturityDate) { bond in
                Text(bond.maturityDate, formatter: bondDateFormatter)
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
