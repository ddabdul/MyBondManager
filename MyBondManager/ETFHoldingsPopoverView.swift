//  ETFHoldingsPopoverView.swift
//  MyBondManager
//  Shows per‐acquisition ETF holdings in a table with annualized yield.

import SwiftUI

@available(macOS 13.0, *)
struct ETFHoldingsPopoverView: View {
    @ObservedObject var etf: ETFEntity
    @Environment(\.dismiss) private var dismiss

    @State private var sortOrder: [KeyPathComparator<ETFHoldings>] = [
        .init(\.acquisitionDate, order: .forward)
    ]

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

            Table(acquisitions, sortOrder: $sortOrder) {
                TableColumn("Date", value: \.acquisitionDate) { h in
                    Text(h.acquisitionDate,
                         format: Date.FormatStyle()
                             .day(.twoDigits)
                             .month(.twoDigits)
                             .year(.twoDigits))
                        .fixedSize(horizontal: true, vertical: false)
                }

                TableColumn("Shares", value: \.numberOfShares) { h in
                    Text("\(h.numberOfShares)")
                        .fixedSize(horizontal: true, vertical: false)
                }

                TableColumn("Cost") { h in
                    let cost = Double(h.numberOfShares) * h.acquisitionPrice
                    Text(String(format: "€%.0f", cost))
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: true, vertical: false)
                }

                TableColumn("Value") { h in
                    let value = Double(h.numberOfShares) * etf.lastPrice
                    Text(String(format: "€%.0f", value))
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: true, vertical: false)
                }

                TableColumn("P&L") { h in
                    let cost  = Double(h.numberOfShares) * h.acquisitionPrice
                    let value = Double(h.numberOfShares) * etf.lastPrice
                    let delta = value - cost
                    Text((delta >= 0 ? "+" : "") + String(format: "€%.0f", delta))
                        .foregroundColor(delta >= 0 ? .green : .red)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: true, vertical: false)
                }

                TableColumn("%") { h in
                    let cost  = Double(h.numberOfShares) * h.acquisitionPrice
                    let value = Double(h.numberOfShares) * etf.lastPrice
                    let pct   = cost > 0 ? (value - cost)/cost*100 : 0
                    Text(String(format: "%.2f%%", pct))
                        .foregroundColor(pct >= 0 ? .green : .red)
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: true, vertical: false)
                }

                // — Annualized yield column
                TableColumn("Ann. Yield") { h in
                    let now = Date()
                    // compute days as at least 1 to avoid division by zero
                    let daysElapsed = Calendar.current
                        .dateComponents([.day], from: h.acquisitionDate, to: now)
                        .day.map { max($0, 1) } ?? 1
                    let diff    = etf.lastPrice - h.acquisitionPrice
                    let annual  = diff / Double(daysElapsed) * 365
                    Text(String(format: "%.2f%%", annual))
                        .multilineTextAlignment(.trailing)
                        .fixedSize(horizontal: true, vertical: false)
                }
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
  //          .scrollContentBackground(.hidden)
            .padding([.horizontal, .bottom])
        }
        .background(AppTheme.panelBackground)
        .frame(minWidth: 600, minHeight: 400)
    }
}
