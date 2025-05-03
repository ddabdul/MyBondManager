//  ETFHoldingsPopoverView.swift
//  MyBondManager
//  Shows per‐acquisition ETF holdings in a fully sortable table.
//

import SwiftUI

@available(macOS 13.0, *)
struct ETFHoldingsPopoverView: View {
    @ObservedObject var etf: ETFEntity
    @Environment(\.dismiss) private var dismiss

    @State private var sortOrder: [KeyPathComparator<ETFHoldings>] = [
        // default to sort by acquisitionDate ascending
        KeyPathComparator(\.acquisitionDate, order: .forward)
    ]

    private var acquisitions: [ETFHoldings] {
        let allHoldings = (etf.etftoholding as? Set<ETFHoldings>)?
            .sorted { $0.acquisitionDate < $1.acquisitionDate } // Initial sort (optional, but can maintain a consistent starting order)
        ?? []

        // Sort the data based on the current sortOrder
        return allHoldings.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header + X‐button
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .padding(.leading)

                Spacer()

                Text(etf.etfName)
                    .font(.title2)
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Spacer()
                    .frame(width: 30) // match button width
            }
            .padding(.vertical, 8)
            .background(AppTheme.tileBackground) // Assuming AppTheme is defined elsewhere

            // Sortable Table
            Table(acquisitions, sortOrder: $sortOrder) {
                // 1) Date
                TableColumn(
                    "Date",
                    sortUsing: KeyPathComparator(\.acquisitionDate)
                ) { h in
                    Text(h.acquisitionDate,
                         format:
                            Date.FormatStyle()
                                .day(.twoDigits)
                                .month(.twoDigits)
                                .year(.twoDigits))

                }

                // 2) Shares
                TableColumn(
                    "Shares",
                    sortUsing: KeyPathComparator(\.numberOfShares)
                ) { h in
                    Text("\(h.numberOfShares)")
                        .multilineTextAlignment(.center)
                }

                // 3) Cost
                TableColumn(
                    "Cost",
                    sortUsing: KeyPathComparator(\.cost) // Assuming 'cost' is a property in ETFHoldings
                ) { h in
                    Text(h.cost, format: .currency(code: "EUR"))
                        .multilineTextAlignment(.trailing)
                }

                // 4) Value
                TableColumn(
                    "Value",
                    sortUsing: KeyPathComparator(\.marketValue) // Assuming 'marketValue' is a property in ETFHoldings
                ) { h in
                    Text(h.marketValue, format: .currency(code: "EUR"))
                        .multilineTextAlignment(.trailing)
                }

                // 5) P&L
                TableColumn(
                    "P&L",
                    sortUsing: KeyPathComparator(\.profit) // Assuming 'profit' is a property in ETFHoldings
                ) { h in
                    Text(h.profit, format: .currency(code: "EUR"))
                        .foregroundColor(h.profit >= 0 ? .green : .red)
                        .multilineTextAlignment(.trailing)
                }

                // 6) % Gain (2 decimals)
                TableColumn(
                    "%",
                    sortUsing: KeyPathComparator(\.pctGain) // Assuming 'pctGain' is a property in ETFHoldings
                ) { h in
                    Text(String(format: "%.2f%%", h.pctGain))
                        .foregroundColor(h.pctGain >= 0 ? .green : .red)
                        .multilineTextAlignment(.trailing)
                }

                // 7) Annualized Yield (2 decimals)
                TableColumn(
                    "Ann. Yield",
                    sortUsing: KeyPathComparator(\.annualYield) // Assuming 'annualYield' is a property in ETFHoldings
                ) { h in
                    Text(String(format: "%.2f%%", h.annualYield))
                        .multilineTextAlignment(.trailing)
                }
            }
            .tableStyle(.inset) // Use the inset style
            .alternatingRowBackgrounds() // Apply the alternatingRowBackgrounds modifier
            // .scrollContentBackground(.hidden) // Removed as it interfered with alternating backgrounds
            // .background(AppTheme.panelBackground) // Removed from Table to allow alternating backgrounds
            .padding([.horizontal, .bottom])
        }
        .background(AppTheme.panelBackground) // Apply panel background to the VStack
        .frame(minWidth: 800, minHeight: 400)
    }
}
