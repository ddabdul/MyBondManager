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
    private let scraper = BondDataScraper()

    // MARK: – Inputs
    @State private var isin                  = ""
    @State private var acquisitionDate = Date()
    @State private var parValueStr         = ""
    @State private var acquisitionPrice = ""
    @State private var depotBank           = ""

    // MARK: – Scraped Data
    @State private var name                  = ""
    @State private var issuer                = ""
    @State private var wkn                   = ""
    @State private var maturityDate          = Date()
    @State private var couponRateStr       = ""

    @State private var isLoading             = false
    @State private var errorMessage          = ""

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
                    TextField("ISIN", text: $isin)
                        .onSubmit { isin = isin.uppercased() }
                    DatePicker("Acquisition Date", selection: $acquisitionDate, displayedComponents: .date)
                    TextField("Par Value", text: $parValueStr)
                    TextField("Acquisition Price", text: $acquisitionPrice)
                    TextField("Depot Bank", text: $depotBank)
                }

                Section("Automaticly collected") {
                    TextField("Bond Name", text: $name)
                        .disabled(true)
                    TextField("Issuer", text: $issuer)
                        .disabled(true)
                    TextField("WKN", text: $wkn)
                        .disabled(true)
                    DatePicker("Maturity Date", selection: $maturityDate, displayedComponents: .date)
                        .disabled(true)
                    TextField("Coupon Rate (%)", text: $couponRateStr)
                        .disabled(true)
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
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
                        .disabled(isLoading || isin.isEmpty)

                        Button("Save") {
                            saveBond()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(
                            isSaving || isLoading || name.isEmpty || issuer.isEmpty || wkn.isEmpty ||
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
 //       .disabled(isLoading)
        .overlay(
            Group {
                if isLoading {
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
        DispatchQueue.main.async {
            isLoading = true
            errorMessage = ""
        }

        Task {
            do {
                let (scrapedName, scrapedWKN) = try await scraper.fetchNameAndWKN(isin: isin)
                let scrapedIssuer                  = try await scraper.fetchIssuer(isin: isin)
                let dates                          = try await scraper.fetchDates(isin: isin)
                let scrapedCoupon                  = try await scraper.fetchCouponRate(isin: isin)

                DispatchQueue.main.async {
                    name            = scrapedName
                    wkn             = scrapedWKN
                    issuer          = scrapedIssuer
                    maturityDate    = dates.maturity
                    couponRateStr   = String(format: "%.2f", scrapedCoupon)
                    isLoading       = false
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                    isLoading    = false
                }
            }
        }
    }

    private func saveBond() {
        guard !isSaving, let container = portfolioContainer else {
            errorMessage = "Portfolio store is unavailable."
            return
        }
        guard let nominal = Double(parValueStr), nominal.isFinite, nominal > 0,
              let cost = Double(acquisitionPrice), cost.isFinite, cost > 0,
              let rate = Double(couponRateStr), rate.isFinite, rate >= 0,
              acquisitionDate <= maturityDate else {
            errorMessage = "Enter positive nominal and purchase cost, a nonnegative coupon, and valid dates."
            return
        }
        let years = maturityDate.timeIntervalSince(acquisitionDate) / (365 * 24 * 3600)
        let ytm = years > 0 ? ((nominal * rate / 100 + (nominal - cost) / years) / ((nominal + cost) / 2)) * 100 : 0
        let values = BondCodable(id: UUID(), name: name, isin: isin,
            issuer: issuer, depotBank: depotBank, acquisitionDate: acquisitionDate,
            maturityDate: maturityDate, couponRate: rate, parValue: nominal, initialPrice: cost,
            yieldToMaturity: ytm, wkn: wkn, cashFlows: [])
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
