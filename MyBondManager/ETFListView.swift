//  ETFListView.swift
//  MyBondManager
//  Created by Olivier on 30/04/2025.
//  Updated 11/05/2025 – format Total Value as currency
//

import SwiftUI
import CoreData

@available(macOS 13.0, *)
struct ETFListView: View {
    @Environment(\.managedObjectContext) private var viewContext

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ETFEntity.etfName, ascending: true)],
        animation: .default
    )
    private var etfs: FetchedResults<ETFEntity>

    @State private var selectedID: UUID?
    @State private var popoverETF: ETFEntity?
    @State private var historyETF: ETFEntity?

    private var titleBar: some View {
        HStack {
            Text("My ETF Portfolio")
                .font(.system(.largeTitle, design: .rounded))
                .foregroundColor(.white)
            Spacer()
        }
        .padding()
        .background(AppTheme.tileBackground)
    }

    /// Only show ETFs whose total shares > 0
    private var displayedETFs: [ETFEntity] {
        etfs.filter { $0.totalShares > 0 }
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar

            Table(displayedETFs, selection: $selectedID) {
                TableColumn("ETF Name") { etf in
                    Text(etf.etfName)
                        .multilineTextAlignment(.leading)
                        .lineLimit(nil)
                }
                .width(min: 160)

                TableColumn("Holdings") { etf in
                    Text("\(etf.numberOfHoldings)")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .width(ideal: 60)

                TableColumn("Total Shares") { etf in
                    Text("\(etf.totalShares)")
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .width(ideal: 60)

                TableColumn("Last Price") { etf in
                    Text(String(format: "%.2f", etf.lastPrice))
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .width(ideal: 60)

                TableColumn("Total Value") { etf in
                    Text(
                        Formatters.currency
                            .string(from: NSNumber(value: etf.totalValue))
                            ?? "–"
                    )
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(ideal: 100)

                TableColumn("History") { etf in
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
            .onChange(of: selectedID) { _, newID in
                guard let id = newID,
                      let etf = displayedETFs.first(where: { $0.id == id })
                else { return }
                popoverETF = etf
                selectedID = nil
            }
            .popover(item: $popoverETF, arrowEdge: .bottom) { etf in
                ETFHoldingsPopoverView(etf: etf)
                    .frame(minWidth: 600, minHeight: 400)
            }
            .sheet(item: $historyETF) { etf in
                ETFPriceListView(etf: etf)
                    .frame(minWidth: 400, minHeight: 300)
            }
            .frame(minWidth: 700, minHeight: 400)
        }
    }
}
