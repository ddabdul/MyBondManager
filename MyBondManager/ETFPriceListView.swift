//  ETFPriceListView.swift
//  MyBondManager
//  Shows the full timestamped history of prices for one ETF.

import SwiftUI
import CoreData

@available(macOS 13.0, *)
struct ETFPriceListView: View {
    // 1) Allows us to dismiss the sheet/popover
    @Environment(\.dismiss) private var dismiss

    // 2) Keep track of sort order so we can use closure‐based columns
    @State private var sortOrder: [KeyPathComparator<ETFPrice>] = [
        // newest first
        KeyPathComparator(\.datePrice, order: .reverse)
    ]

    // 3) FetchRequest scoped to a single ETF
    @FetchRequest private var prices: FetchedResults<ETFPrice>
    
    init(etf: ETFEntity) {
        _prices = FetchRequest(
            entity: ETFPrice.entity(),
            sortDescriptors: [],  // we sort in the Table via sortOrder
            predicate: NSPredicate(format: "etfPriceHistory == %@", etf),
            animation: .default
        )
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Close button row
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
                .padding(.trailing)
            }
            .padding(.top)
            
            // Price history table
            Table(prices, sortOrder: $sortOrder) {
                // — Date column —
                TableColumn("Date", value: \.datePrice) { (entry: ETFPrice) in
                    Text(entry.datePrice,
                         format: Date.FormatStyle(date: .numeric, time: .standard))
                }
                .width(min: 150, ideal: 200)
                
                // — Price column —
                TableColumn("Price", value: \.price) { (entry: ETFPrice) in
                    Text(String(format: "%.2f", entry.price))
                        .multilineTextAlignment(.trailing)
                }
                .width(min: 80, ideal: 100)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
            .background(AppTheme.panelBackground)
        }
        .frame(minWidth: 300, minHeight: 200)
    }
}
