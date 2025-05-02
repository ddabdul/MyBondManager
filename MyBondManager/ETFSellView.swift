//
//  ETFSellView.swift
//  MyBondManager
//
//  Created by Olivier on 02/05/2025.
//


//  SellETFView.swift
//  MyBondManager
//
//  Created by You on 02/05/2025.
//  Sell ETF shares using FIFO against existing holdings.

import SwiftUI
import CoreData

@available(macOS 13.0, *)
struct SellETFView: View {
    // MARK: – Environment
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss)           private var dismiss

    // MARK: – Fetch ETFs
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ETFEntity.etfName, ascending: true)],
        animation: .default)
    private var etfs: FetchedResults<ETFEntity>

    // MARK: – UI State
    @State private var selectedETF: ETFEntity?
    @State private var saleDate: Date = Date()
    @State private var saleShares: String = ""
    @State private var errorMessage: String?

    var body: some View {
        Form {
            // 1) Select your ETF
            Section(header: Text("Select ETF")) {
                Picker("ETF", selection: $selectedETF) {
                    Text("(none)").tag(Optional<ETFEntity>(nil))
                    ForEach(etfs) { etf in
                        Text(etf.etfName).tag(Optional(etf))
                    }
                }
                .labelsHidden()
            }

            // 2) Enter sale details
            if let etf = selectedETF {
                Section(header: Text("Sale Details")) {
                    let maxShares = etf.totalShares
                    HStack {
                        TextField("Shares to Sell", text: $saleShares)
                        Text("/ \(maxShares)")
                            .foregroundColor(.secondary)
                    }

                    DatePicker("Sale Date", selection: $saleDate, in: ...Date(), displayedComponents: .date)
                }

                // validation errors
                if let err = errorMessage {
                    Section {
                        Text(err)
                            .foregroundColor(.red)
                    }
                }

                // 3) Buttons
                Section {
                    HStack {
                        Button("Close") { dismiss() }
                            .keyboardShortcut(.cancelAction)

                        Spacer()

                        Button("Save Sale") { saveSale() }
                            .disabled(!canSave(etf: etf))
                    }
                }
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 300)
    }

    // MARK: – Validation
    private func canSave(etf: ETFEntity) -> Bool {
        guard let shares = Int32(saleShares),
              shares > 0,
              shares <= etf.totalShares
        else { return false }
        return true
    }

    // MARK: – FIFO sale logic
    private func saveSale() {
        guard let etf = selectedETF else { return }
        guard let sharesToSell = Int32(saleShares),
              sharesToSell > 0,
              sharesToSell <= etf.totalShares
        else {
            errorMessage = "Enter a valid number of shares (≤ your total)."
            return
        }

        var remaining = sharesToSell
        // sort holdings oldest first
        let fifo = (etf.etftoholding as? Set<ETFHoldings>)?
            .sorted { $0.acquisitionDate < $1.acquisitionDate } ?? []

        for lot in fifo {
            guard remaining > 0 else { break }
            let available = lot.numberOfShares
            if available <= remaining {
                remaining -= available
                viewContext.delete(lot)
            } else {
                lot.numberOfShares = available - remaining
                remaining = 0
            }
        }

        do {
            try viewContext.save()
            dismiss()
        } catch {
            errorMessage = "Failed saving sale: \(error.localizedDescription)"
        }
    }
}
