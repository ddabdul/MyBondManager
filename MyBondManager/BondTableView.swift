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
// MARK: – BondTableView
// —————————————————————————————
struct BondTableView: View {
    @ObservedObject var viewModel: BondPortfolioViewModel

    /// drive sorting
    @State private var sortOrder: [KeyPathComparator<Bond>] = [
        .init(\.maturityDate, order: .forward)
    ]

    /// we sort on‑the‑fly rather than mutating the VM
    private var sortedBonds: [Bond] {
        viewModel.bonds.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            bondTable
        }
        .frame(minWidth: 800, minHeight: 400)
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
            // you can re‑add your “Add” + “Matured” buttons here…
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
        Table(sortedBonds, sortOrder: $sortOrder) {
            // 1) Bond Name (left‑aligned text)
            TableColumn("Bond Name", value: \.name) { bond in
                Text(bond.name)
                    .multilineTextAlignment(.leading)
            }
            .width(min: 150, ideal: 200, max: 300)

            // 2) Issuer (left)
            TableColumn("Issuer", value: \.issuer) { bond in
                Text(bond.issuer)
                    .multilineTextAlignment(.leading)
            }
            .width(min: 120, ideal: 160, max: 240)

            // 3) Acq. Price (right)
            TableColumn("Acq. Price", value: \.initialPrice) { bond in
                Text(bond.acquisitionPriceFormatted)
                    .multilineTextAlignment(.trailing)
            }
            .width(min: 80, ideal: 100)

            // 4) Nominal (right)
            TableColumn("Nominal", value: \.parValue) { bond in
                Text(bond.parValueFormatted)
                    .multilineTextAlignment(.trailing)
            }
            .width(min: 80, ideal: 100)

            // 5) Coupon (right)
            TableColumn("Coupon", value: \.couponRate) { bond in
                Text(bond.couponFormatted)
                    .multilineTextAlignment(.trailing)
            }
            .width(min: 60, ideal: 80)

            // 6) Acq. Date (center)
            TableColumn("Acq. Date", value: \.acquisitionDate) { bond in
                Text(bond.acquisitionDate, formatter: bondDateFormatter)
                    .multilineTextAlignment(.center)
            }
            .width(min: 80)

            // 7) Mat. Date (center)
            TableColumn("Mat. Date", value: \.maturityDate) { bond in
                Text(bond.maturityDate, formatter: bondDateFormatter)
                    .multilineTextAlignment(.center)
            }
            .width(min: 80)

            // 8) Depot Bank (left)
            TableColumn("Depot Bank", value: \.depotBank) { bond in
                Text(bond.depotBank)
                    .multilineTextAlignment(.leading)
            }
            .width(min: 100, ideal: 120)

            // 9) YTM (right, not sortable)
            TableColumn("YTM") { bond in
              Text(bond.ytmFormatted)
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 60, ideal: 80)


        }
        // let SwiftUI handle the visuals — no manual .onChange needed
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
