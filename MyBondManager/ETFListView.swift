//
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

    // drive selection off the ETF’s UUID
    @State private var selectedID: UUID?
    @State private var popoverETF: ETFEntity?

    var body: some View {
        Table(etfs, selection: $selectedID) {
            TableColumn("ETF Name") { (etf: ETFEntity) in
                Text(etf.etfName)
            }
            TableColumn("Holdings") { (etf: ETFEntity) in
                Text("\(etf.numberOfHoldings)")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            TableColumn("Total Shares") { (etf: ETFEntity) in
                Text("\(etf.totalShares)")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            TableColumn("Last Price") { (etf: ETFEntity) in
                Text(String(format: "%.2f", etf.lastPrice))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            TableColumn("Total Value") { (etf: ETFEntity) in
                Text(String(format: "%.2f", etf.totalValue))
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
        }
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
