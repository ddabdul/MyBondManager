//
//  BondTableView.swift
//  MyBondManager
//
//  Created by Olivier on 19/04/2025.
//


import SwiftUI

/// Reuse your existing formatters:
private let bondDateFormatter: DateFormatter = {
    let f = DateFormatter()
    f.dateStyle = .short
    return f
}()

struct BondTableView: View {
    @ObservedObject var viewModel: BondPortfolioViewModel
    
    /// We'll drive sorting with these SwiftUI comparators.
    @State private var sortOrder: [KeyPathComparator<Bond>] = [
        .init(\.maturityDate, order: .forward)
    ]
    
    var body: some View {
        VStack {
            // Top toolbar with “Add” and “Matured” just like before
            HStack {
                Text("My Bond Portfolio")
                    .font(.largeTitle)
                Spacer()
                Button {
                    // your add‑bond action
                } label: {
                    Image(systemName: "plus")
                        // use standard “add” style for macOS:
                        .imageScale(.large)
                }
            }
            .padding()
            
            // The magical Table!
            Table(viewModel.bonds, sortOrder: $sortOrder) {
                // Column definitions:
                TableColumn("Bond Name", value: \.name) { bond in
                    Text(bond.name)
                }
                TableColumn("Issuer", value: \.issuer) { bond in
                    Text(bond.issuer)
                }
                TableColumn("Acq. Price", value: \.initialPrice) { bond in
                    Text(NumberFormatter.zeroDecimalCurrency
                            .string(from: NSNumber(value: bond.initialPrice)) ?? "-")
                }
                TableColumn("Nominal", value: \.parValue) { bond in
                    Text(NumberFormatter.zeroDecimalCurrency
                            .string(from: NSNumber(value: bond.parValue)) ?? "-")
                }
                TableColumn("Coupon", value: \.couponRate) { bond in
                    Text(String(format: "%.2f%%", bond.couponRate))
                }
                TableColumn("Acq. Date", value: \.acquisitionDate) { bond in
                    Text(bond.acquisitionDate, formatter: bondDateFormatter)
                }
                TableColumn("Mat. Date", value: \.maturityDate) { bond in
                    Text(bond.maturityDate, formatter: bondDateFormatter)
                }
                TableColumn("Depot Bank", value: \.depotBank) { bond in
                    Text(bond.depotBank)
                }
                // YTM isn’t sortable here, so we supply a custom column:
                TableColumn("YTM") { bond in
                    Text(String(format: "%.2f%%", bond.yieldAtAcquisition * 100))
                }
            }
            // react to sortOrder changes using the new two‑parameter onChange API
            .onChange(of: sortOrder) { oldOrder, newOrder in
                viewModel.bonds.sort(using: newOrder)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
        }
        .frame(minWidth: 800, minHeight: 400)
    }
}

struct BondTableView_Previews: PreviewProvider {
    static var previews: some View {
        BondTableView(viewModel: BondPortfolioViewModel())
    }
}
