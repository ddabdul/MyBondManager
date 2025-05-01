//
//  ETFHoldingsPopoverView.swift
//  MyBondManager
//
//  Created by Olivier on 01/05/2025.
//


import SwiftUI

@available(macOS 13.0, *)
struct ETFHoldingsPopoverView: View {
    @ObservedObject var etf: ETFEntity
    @Environment(\.dismiss) private var dismiss

    // Sort acquisitions by date
    private var acquisitions: [ETFHoldings] {
        (etf.etftoholding as? Set<ETFHoldings>)?
            .sorted { $0.acquisitionDate < $1.acquisitionDate }
        ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header row with Close button
            HStack {
                Text(etf.etfName)
                    .font(.title2)
                    .foregroundColor(.white)
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.8))

            // Column titles
            HStack {
                Text("Date")
                Spacer()
                Text("Shares")
                    .frame(minWidth: 80, alignment: .trailing)
                Spacer()
                Text("Cost")
                    .frame(minWidth: 80, alignment: .trailing)
                Spacer()
                Text("Value")
                    .frame(minWidth: 80, alignment: .trailing)
                Spacer()
                Text("P&L")
                    .frame(minWidth: 80, alignment: .trailing)
                Spacer()
                Text("%")
                    .frame(minWidth: 60, alignment: .trailing)
            }
            .font(.headline)
            .foregroundColor(.white)
            .padding(.horizontal)
            .padding(.vertical, 6)
            .background(Color.gray.opacity(0.7))

            // Data rows
            ForEach(Array(acquisitions.enumerated()), id: \.element) { idx, h in
                let cost  = Double(h.numberOfShares) * h.acquisitionPrice
                let value = Double(h.numberOfShares) * etf.lastPrice
                let delta = value - cost
                let pct   = cost > 0 ? delta / cost * 100 : 0

                HStack {
                    Text(h.acquisitionDate, format: Date.FormatStyle()
                                                .day(.twoDigits)
                                                .month(.twoDigits)
                                                .year(.twoDigits))
                    Spacer()
                    Text("\(h.numberOfShares)")
                        .frame(minWidth: 80, alignment: .trailing)
                    Spacer()
                    Text(String(format: "€%.0f", cost))
                        .frame(minWidth: 80, alignment: .trailing)
                    Spacer()
                    Text(String(format: "€%.0f", value))
                        .frame(minWidth: 80, alignment: .trailing)
                    Spacer()
                    Text((delta >= 0 ? "+" : "") + String(format: "€%.0f", delta))
                        .frame(minWidth: 80, alignment: .trailing)
                        .foregroundColor(delta >= 0 ? .green : .red)
                    Spacer()
                    Text(String(format: "%.2f%%", pct))
                        .frame(minWidth: 60, alignment: .trailing)
                        .foregroundColor(pct >= 0 ? .green : .red)
                }
                .padding(.horizontal)
                .padding(.vertical, 6)
                .background(
                    (idx.isMultiple(of: 2)
                        ? Color.gray.opacity(0.3)
                        : Color.gray.opacity(0.25))
                )
                .foregroundColor(.white)
            }

            Spacer()
        }
        .background(AppTheme.panelBackground)
    }
}
