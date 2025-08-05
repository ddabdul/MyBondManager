//
//  AddBondViewAsync.swift
//  MyBondManager
//  Adjusted to CoreData
//  Refactored on 05/08/2025
//

import SwiftUI
import CoreData

@available(macOS 13.0, *)
struct AddBondViewAsync: View {
    @Environment(\.dismiss) private var dismiss: DismissAction
    @Environment(\.managedObjectContext) private var moc
    private let scraper = BondDataScraper()

    // MARK: – Inputs
    @State private var isin               = ""
    @State private var acquisitionDate    = Date()
    @State private var parValueStr        = ""
    @State private var acquisitionPrice   = ""
    @State private var depotBank          = ""

    // MARK: – Scraped or User‐Entered Data
    @State private var name               = ""
    @State private var issuer             = ""
    @State private var wkn                = ""
    @State private var maturityDate       = Date()
    @State private var couponRateStr      = ""

    // MARK: – UI States
    @State private var isLoading          = false
    @State private var errorMessage       = ""
    @State private var allowManualEntry   = false

    var body: some View {
        VStack(spacing: 0) {
            // MARK: – Header Bar
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.white)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Text("Add New Bond")
                    .font(.system(.headline, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer().frame(width: 30)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(AppTheme.tileBackground)

            // MARK: – Main Form
            Form {
                Section("Please enter the required information") {
                    TextField("ISIN", text: $isin)
                        .onSubmit { isin = isin.uppercased() }

                    DatePicker("Acquisition Date", selection: $acquisitionDate, displayedComponents: .date)
                    TextField("Par Value", text: $parValueStr)
                    TextField("Acquisition Price", text: $acquisitionPrice)
                    TextField("Depot Bank", text: $depotBank)
                }

                Section("Automatically collected") {
                    TextField("Bond Name", text: $name)
                        .disabled(!allowManualEntry)
                    TextField("Issuer", text: $issuer)
                        .disabled(!allowManualEntry)
                    TextField("WKN", text: $wkn)
                        .disabled(!allowManualEntry)
                    DatePicker("Maturity Date", selection: $maturityDate, displayedComponents: .date)
                        .disabled(!allowManualEntry)
                    TextField("Coupon Rate (%)", text: $couponRateStr)
                        .disabled(!allowManualEntry)
                }

                if !errorMessage.isEmpty {
                    Section {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                if allowManualEntry {
                    Section {
                        Text("Manual entry enabled. Please complete the bond details manually.")
                            .foregroundColor(.orange)
                    }
                }

                Section {
                    HStack {
                        Spacer()

                        Button("Collect Data") {
                            startScrape()
                        }
                        .disabled(isLoading || isin.isEmpty)

                        Button("Save") {
                            saveBond()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(
                            isLoading ||
                            name.isEmpty || issuer.isEmpty || wkn.isEmpty ||
                            parValueStr.isEmpty || acquisitionPrice.isEmpty || depotBank.isEmpty
                        )
                    }
                }
            }
            .padding()

            Spacer()
        }
        .background(AppTheme.panelBackground)
        .overlay {
            if isLoading {
                Color.black.opacity(0.3).ignoresSafeArea()
                ProgressView("Scraping…")
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .shadow(radius: 4)
            }
        }
    }

    // MARK: – Scraping Logic (unchanged from last version)
    private func startScrape() {
        isLoading = true
        errorMessage = ""
        allowManualEntry = false

        Task {
            do {
                let (scrapedName, scrapedWKN) = try await scraper.fetchNameAndWKN(isin: isin)
                let scrapedIssuer            = try await scraper.fetchIssuer(isin: isin)
                let dates                    = try await scraper.fetchDates(isin: isin)
                let scrapedCoupon            = try await scraper.fetchCouponRate(isin: isin)

                DispatchQueue.main.async {
                    name             = scrapedName
                    wkn              = scrapedWKN
                    issuer           = scrapedIssuer
                    maturityDate     = dates.maturity
                    couponRateStr    = String(format: "%.2f", scrapedCoupon)
                    isLoading        = false
                    allowManualEntry = false
                }
            } catch {
                DispatchQueue.main.async {
                    isLoading        = false
                    allowManualEntry = true

                    if let urlError = error as? URLError, urlError.code == .badServerResponse {
                        errorMessage = "No data found for ISIN \(isin). Please enter the details manually."
                    } else if error.localizedDescription.contains("404") {
                        errorMessage = "404 – Bond data not found. Please enter the fields manually."
                    } else {
                        errorMessage = error.localizedDescription
                    }
                }
            }
        }
    }

    // MARK: – Save Logic (with deferred state mutations)
    private func saveBond() {
        // Parse numeric inputs synchronously
        guard let parValue   = Double(parValueStr),
              let couponRate = Double(couponRateStr),
              let pricePaid  = Double(acquisitionPrice)
        else {
            // Defer setting errorMessage
            DispatchQueue.main.async {
                errorMessage = "Numeric conversion failed."
            }
            return
        }

        // Compute yield‐to‐maturity synchronously
        let years         = maturityDate.timeIntervalSince(acquisitionDate) / (365 * 24 * 3600)
        let couponPayment = parValue * couponRate / 100.0
        let ytmValue: Double = years > 0
            ? ((couponPayment + (parValue - pricePaid) / years) / ((parValue + pricePaid) / 2)) * 100.0
            : 0

        // Create and save Core Data entity
        let entity = BondEntity(context: moc)
        entity.id              = UUID()
        entity.name            = name
        entity.issuer          = issuer
        entity.isin            = isin
        entity.wkn             = wkn
        entity.parValue        = parValue
        entity.initialPrice    = pricePaid
        entity.couponRate      = couponRate
        entity.depotBank       = depotBank
        entity.acquisitionDate = acquisitionDate
        entity.maturityDate    = maturityDate
        entity.yieldToMaturity = ytmValue

        do {
            let generator = CashFlowGenerator(context: moc)
            try generator.regenerateCashFlows(for: entity)

            let recorder = CapitalTransactionRecorder(context: moc)
            recorder.recordBondPurchase(entity)

            try moc.save()

            // Defer the dismiss so SwiftUI finishes layout first
            DispatchQueue.main.async {
                dismiss()
            }
        } catch {
            // Defer showing Core Data or generator errors
            DispatchQueue.main.async {
                errorMessage = "Failed to save bond or generate cash flows: \(error.localizedDescription)"
            }
        }
    }
}
