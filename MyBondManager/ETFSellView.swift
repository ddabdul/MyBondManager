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
    @Environment(\.portfolioContainer) private var portfolioContainer
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss)           private var dismiss: DismissAction // Explicitly specify DismissAction

    // MARK: – Fetch ETFs
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ETFEntity.etfName, ascending: true)],
        animation: .default)
    private var etfs: FetchedResults<ETFEntity>

    // MARK: – UI State
    @State private var selectedETF: ETFEntity?
    @State private var saleDate: Date = Date()
    @State private var salePrice = ""
    @State private var isSaving = false
    @State private var saleShares: String = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            // Title Bar with Custom Styling
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white) // Match title color
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Text("Sell an ETF holding (FIFO)")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer()
                    .frame(width: 30)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(AppTheme.tileBackground) // Use the specified background

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

                        TextField("Execution Price Per Share", text: $salePrice)
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
                            Spacer()
                            Button("Save Sale") { saveSale() }
                                .disabled(!canSave(etf: etf))
                                .keyboardShortcut(.defaultAction)
                        }
                    }
                }
            }
            .padding()
            Spacer() // Push content up if needed
        }
        .frame(minWidth: 400, minHeight: 300)
    }

    // MARK: – Validation
    private func canSave(etf: ETFEntity) -> Bool {
        guard !isSaving, let price = Double(salePrice), price.isFinite, price > 0,
              let shares = Int32(saleShares),
              shares > 0,
              shares <= etf.totalShares
        else { return false }
        return true
    }

    // MARK: – FIFO sale logic
    private func saveSale() {
        guard !isSaving, let container = portfolioContainer else {
            errorMessage = "Portfolio store is unavailable."
            return
        }
        guard let etf = selectedETF, canSave(etf: etf),
              let shares = Int32(saleShares), let price = Double(salePrice) else {
            errorMessage = "Enter valid shares and an execution price."
            return
        }
        let etfID = etf.objectID
        let date = saleDate
        isSaving = true; errorMessage = nil
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await PortfolioTransaction.run(in: container) { context in
                    guard let stored = try context.existingObject(with: etfID) as? ETFEntity else {
                        throw PortfolioError("The selected ETF no longer exists.")
                    }
                    try ETFSale.stage(etf: stored, shares: shares, executionPrice: price,
                        date: date, context: context)
                }
                dismiss()
            } catch { errorMessage = "Could not save sale: \(error.localizedDescription)" }
        }
    }
}
