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

    var body: some View {
        Table(etfs, selection: $selectedID) {
            TableColumn("ETF Name") { (etf: ETFEntity) in
                Text(etf.etfName)
                    .multilineTextAlignment(.leading)
                    .lineLimit(nil)
            }
            .width(min: 160) // Set a minimum width for the flexible column

            TableColumn("Holdings") { (etf: ETFEntity) in
                Text("\(etf.numberOfHoldings)")
                    .frame(maxWidth: .infinity, alignment: .center) // Center alignment
            }
            .width(ideal: 60) // Adjust to content

            TableColumn("Total Shares") { (etf: ETFEntity) in
                Text("\(etf.totalShares)")
                    .frame(maxWidth: .infinity, alignment: .center) // Center alignment
            }
            .width(ideal: 60) // Adjust to content

            TableColumn("Last Price") { (etf: ETFEntity) in
                Text(String(format: "%.2f", etf.lastPrice))
                    .frame(maxWidth: .infinity, alignment: .center) // Center alignment
            }
            .width(ideal: 60) // Adjust to content

            TableColumn("Total Value") { (etf: ETFEntity) in
                Text(String(format: "%.2f", etf.totalValue))
                    .frame(maxWidth: .infinity, alignment: .center) // Center alignment
            }
            .width(ideal: 100) // Adjust to content
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
        .background(AppTheme.panelBackground)
        .onChange(of: selectedID) { _old, newID in
            guard let id = newID,
                  let etf = etfs.first(where: { $0.id == id })
            else { return }
            popoverETF = etf
            selectedID = nil
        }
        .popover(item: $popoverETF, arrowEdge: .bottom) { etf in
            ETFHoldingsPopoverView(etf: etf)
                .frame(minWidth: 600, minHeight: 400)
        }
        .frame(minWidth: 700, minHeight: 400)
    }
}
