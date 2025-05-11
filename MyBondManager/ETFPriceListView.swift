//  ETFPriceListView.swift
//  MyBondManager
//  Shows the full timestamped history of prices for one ETF.
//

import SwiftUI
import CoreData
import Algorithms    // for the “sorted(using:)” extension

@available(macOS 13.0, *)
struct ETFPriceListView: View {
    // 1) Allows us to dismiss the sheet/popover
    @Environment(\.dismiss) private var dismiss

    // 2) Keep track of sort order so we can use closure‐based columns
    @State private var sortOrder: [KeyPathComparator<ETFPrice>] = [
        // newest first
        .init(\.datePrice, order: .reverse)
    ]

    // 3) FetchRequest scoped to a single ETF — unsorted on purpose
    @FetchRequest private var prices: FetchedResults<ETFPrice>
    
    init(etf: ETFEntity) {
        _prices = FetchRequest(
            entity: ETFPrice.entity(),
            sortDescriptors: [],  // no Core Data sort; we’ll do it in-memory
            predicate: NSPredicate(format: "etfPriceHistory == %@", etf),
            animation: .default
        )
    }
    
    /// A little Array wrapper around the FetchedResults,
    /// kept in sync with `sortOrder`.
    private var sortedPrices: [ETFPrice] {
        prices.sorted(using: sortOrder)
    }
    
    var body: some View {
        VStack(spacing: 0) {
                // Title Bar
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.title3)
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                    .keyboardShortcut(.cancelAction)

                    Text("ETF Prices")
                        .font(.headline)
                        .frame(maxWidth: .infinity, alignment: .center)

                    Spacer()
                        .frame(width: 30)
                }
                .padding()
                .background(AppTheme.tileBackground)
            
            // Price history table, now driven by our sortedPrices array
            Table(sortedPrices, sortOrder: $sortOrder) {
                // — Date column —
                TableColumn("Date", value: \.datePrice) { (entry: ETFPrice) in
                    Text(entry.datePrice,
                         format: Date.FormatStyle(date: .numeric))
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
