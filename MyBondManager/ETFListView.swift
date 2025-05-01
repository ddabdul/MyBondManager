//  ETFListView.swift
//  MyBondManager
//
//  Created by Olivier on 30/04/2025.
//

import SwiftUI
import CoreData

@available(macOS 13.0, *)
struct ETFListView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ETFEntity.etfName, ascending: true)],
        animation: .default)
    private var etfs: FetchedResults<ETFEntity>

    @State private var selectedID: UUID?
    @State private var popoverETF: ETFEntity?
    @State private var historyETF: ETFEntity?

    var body: some View {
        Table(etfs, selection: $selectedID) {
            TableColumn("ETF Name") { (etf: ETFEntity) in
                Text(etf.etfName)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
            }
            .width(min: 160)

            TableColumn("Holdings") { (etf: ETFEntity) in
                Text("\(etf.numberOfHoldings)")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .width(ideal: 60)

            TableColumn("Total Shares") { (etf: ETFEntity) in
                Text("\(etf.totalShares)")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .width(ideal: 60)

            TableColumn("Last Price") { (etf: ETFEntity) in
                Text(String(format: "%.2f", etf.lastPrice))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .width(ideal: 60)

            TableColumn("Total Value") { (etf: ETFEntity) in
                Text(String(format: "%.2f", etf.totalValue))
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .width(ideal: 100)

            // ➤ New History column
            TableColumn("History") { (etf: ETFEntity) in
                Button {
                    historyETF = etf
                } label: {
                    Image(systemName: "clock")
                }
                .buttonStyle(.plain)
                .help("View price history")
            }
            .width(ideal: 40)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
        .background(AppTheme.panelBackground)
        
        // existing popover for holdings
        .onChange(of: selectedID) { _old, newID in
            guard let id = newID,
                  let etf = etfs.first(where: { $0.id == id }) else { return }
            popoverETF = etf
            selectedID = nil
        }
        .popover(item: $popoverETF, arrowEdge: .bottom) { etf in
            ETFHoldingsPopoverView(etf: etf)
                .frame(minWidth: 600, minHeight: 400)
        }
        // new sheet for history
        .sheet(item: $historyETF) { etf in
            ETFPriceListView(etf: etf)
                .frame(minWidth: 400, minHeight: 300)
        }
        .frame(minWidth: 700, minHeight: 400)
    }
}

