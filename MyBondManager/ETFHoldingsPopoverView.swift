//  ETFHoldingsPopoverView.swift
//  MyBondManager
//  Shows per‐acquisition ETF holdings in a table.
//

import SwiftUI

@available(macOS 13.0, *)
struct ETFHoldingsPopoverView: View {
    @ObservedObject var etf: ETFEntity
    @Environment(\.dismiss) private var dismiss

    // Sort holdings by acquisitionDate ascending by default
    @State private var sortOrder: [KeyPathComparator<ETFHoldings>] = [
        .init(\.acquisitionDate, order: .forward)
    ]

    // Extract + sort the holdings set
    private var acquisitions: [ETFHoldings] {
        (etf.etftoholding as? Set<ETFHoldings>)?
            .sorted { $0.acquisitionDate < $1.acquisitionDate }
        ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header with title + close (replaced with x button)
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white) // Adjust color as needed
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
                .padding(.leading) // Add some leading padding

                Spacer() // Push the x button to the left if needed

                Text(etf.etfName)
                    .font(.title2)
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer() // Keep some space on the right
                    .frame(width: 30) // Match the width of the button

            }
            .padding(.horizontal)
            .padding(.vertical, 8) // Adjusted vertical padding to match AddBondView
            .background(AppTheme.tileBackground) // Using AppTheme.tileBackground

            // Add some vertical space here
            Spacer()
                .frame(height: 10) // Adjust the height as needed

            // Table of holdings
            Table(acquisitions, sortOrder: $sortOrder) {
                // Date column
                TableColumn("Date", value: \.acquisitionDate) { h in
                    Text(h.acquisitionDate,
                         format: Date.FormatStyle()
                            .day(.twoDigits)
                            .month(.twoDigits)
                            .year(.twoDigits))
                        .fixedSize(horizontal: true, vertical: false)
                }

                // Shares column
                TableColumn("Shares", value: \.numberOfShares) { h in
                    Text("\(h.numberOfShares)")
                        .fixedSize(horizontal: true, vertical: false)
                }

                // Cost column
                TableColumn("Cost") { h in
                    let cost = Double(h.numberOfShares) * h.acquisitionPrice
                    Text(String(format: "€%.0f", cost))
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: true, vertical: false)
                }

                // Value column
                TableColumn("Value") { h in
                    let value = Double(h.numberOfShares) * etf.lastPrice
                    Text(String(format: "€%.0f", value))
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: true, vertical: false)
                }

                // P&L column
                TableColumn("P&L") { h in
                    let cost  = Double(h.numberOfShares) * h.acquisitionPrice
                    let value = Double(h.numberOfShares) * etf.lastPrice
                    let delta = value - cost
                    Text((delta >= 0 ? "+" : "") + String(format: "€%.0f", delta))
                        .foregroundColor(delta >= 0 ? .green : .red)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: true, vertical: false)
                }

                // % column
                TableColumn("%") { h in
                    let cost  = Double(h.numberOfShares) * h.acquisitionPrice
                    let value = Double(h.numberOfShares) * etf.lastPrice
                    let pct   = cost > 0 ? (value - cost) / cost * 100 : 0
                    Text(String(format: "%.2f%%", pct))
                        .foregroundColor(pct >= 0 ? .green : .red)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
    //        .background(AppTheme.panelBackground)
            .padding([.horizontal, .bottom])
        }
        .frame(minWidth: 800, minHeight: 400)
    }
}
