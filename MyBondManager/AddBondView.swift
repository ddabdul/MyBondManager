//
//  MyBondManager
//  AddBondViewAsync.swift
//  Adjusted to CoreData
//  Created by Olivier on 20/04/2025.

import SwiftUI
import CoreData

@available(macOS 13.0, *)
struct AddBondViewAsync: View {
    @Environment(\.portfolioContainer) private var portfolioContainer
    @State private var isSaving = false
    @Environment(\.dismiss) private var dismiss: DismissAction // Explicitly specify DismissAction
    @Environment(\.managedObjectContext) private var moc
    @StateObject private var collection = BondCollection()

    // MARK: – Inputs
    @State private var acquisitionDate = Date()
    @State private var parValueStr         = ""
    @State private var acquisitionPrice = ""
    @State private var depotBank           = ""

    @State private var errorMessage = ""

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

                Text("Add New Bond")
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
                Section("Please enter the required information") {
                    TextField("ISIN", text: $collection.isin)
                        .onSubmit { collection.isin = ETFPurchase.normalizedISIN(collection.isin) }
                    DatePicker("Acquisition Date", selection: $acquisitionDate, displayedComponents: .date)
                    TextField("Par Value", text: $parValueStr)
                    TextField("Acquisition Price", text: $acquisitionPrice)
                    TextField("Depot Bank", text: $depotBank)
                }

                Section("Automaticly collected") {
                    TextField("Bond Name", text: .constant(collection.details?.name ?? ""))
                        .disabled(true)
                    TextField("Issuer", text: .constant(collection.details?.issuer ?? ""))
                        .disabled(true)
                    TextField("WKN", text: .constant(collection.details?.wkn ?? ""))
                        .disabled(true)
                    DatePicker("Maturity Date", selection: .constant(collection.details?.maturityDate ?? Date()), displayedComponents: .date)
                        .disabled(true)
                    TextField("Coupon Rate (%)", text: .constant(collection.details.map { String($0.couponRate) } ?? ""))
                        .disabled(true)
                }

                if !errorMessage.isEmpty || !collection.errorMessage.isEmpty {
                    Section {
                        Text(errorMessage.isEmpty ? collection.errorMessage : errorMessage)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                Section {
                    HStack {
                        Spacer() // Push buttons to the right

                        Button("Collect Data") {
                            startScrape()
                        }
                        .disabled(collection.isLoading || collection.isin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                        Button("Save") {
                            saveBond()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(
                            isSaving || collection.isLoading || collection.details == nil ||
                            parValueStr.isEmpty || acquisitionPrice.isEmpty || depotBank.isEmpty
                        )
                    }
                }
            }
            .padding()
            Spacer()
        }
        .background(AppTheme.panelBackground) // Set panelBackground for the overall background
        // Remove the explicit frame to fit content
        .overlay(
            Group {
                if collection.isLoading {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView("Scraping…")
                        .padding(20)
                        .background(.ultraThinMaterial)
                        .cornerRadius(8)
                        .shadow(radius: 4)
                }
            }
        )
    }

    private func startScrape() {
        errorMessage = ""
        Task { await collection.collect() }
    }

    private func saveBond() {
        guard !isSaving, let container = portfolioContainer else {
            errorMessage = "Portfolio store is unavailable."
            return
        }
        guard let details = collection.details,
              let nominal = Double(parValueStr), nominal.isFinite, nominal > 0,
              let cost = Double(acquisitionPrice), cost.isFinite, cost > 0,
              details.couponRate.isFinite, details.couponRate >= 0,
              acquisitionDate <= details.maturityDate else {
            errorMessage = "Enter positive nominal and purchase cost, a nonnegative coupon, and valid dates."
            return
        }
        let rate = details.couponRate
        let maturityDate = details.maturityDate
        let years = maturityDate.timeIntervalSince(acquisitionDate) / (365 * 24 * 3600)
        let ytm = years > 0 ? ((nominal * rate / 100 + (nominal - cost) / years) / ((nominal + cost) / 2)) * 100 : 0
        let values = BondCodable(id: UUID(), name: details.name, isin: ETFPurchase.normalizedISIN(collection.isin),
            issuer: details.issuer, depotBank: depotBank, acquisitionDate: acquisitionDate,
            maturityDate: maturityDate, couponRate: rate, parValue: nominal, initialPrice: cost,
            yieldToMaturity: ytm, wkn: details.wkn, cashFlows: [])
        isSaving = true; errorMessage = ""
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await PortfolioTransaction.run(in: container) { context in
                    let entity = BondEntity(context: context)
                    entity.id = values.id; entity.name = values.name; entity.isin = values.isin
                    entity.issuer = values.issuer; entity.depotBank = values.depotBank
                    entity.acquisitionDate = values.acquisitionDate; entity.maturityDate = values.maturityDate
                    entity.couponRate = values.couponRate; entity.parValue = values.parValue
                    entity.initialPrice = values.initialPrice; entity.yieldToMaturity = values.yieldToMaturity
                    entity.wkn = values.wkn
                    try CashFlowGenerator(context: context).regenerateCashFlows(for: entity)
                    try HistoricalDataRecorder.recordBondAcquisition(bond: entity, context: context)
                }
                dismiss()
            } catch { errorMessage = "Could not save bond: \(error.localizedDescription)" }
        }
    }

}

struct AddBondViewAsync_Previews: PreviewProvider {
    static var previews: some View {
        AddBondViewAsync()
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}
