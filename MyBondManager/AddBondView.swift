// AddBondViewAsync.swift
import SwiftUI

@available(macOS 13.0, *)
struct AddBondViewAsync: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var viewModel: BondPortfolioViewModel
    private let scraper = BondDataScraper()

    // MARK: – Inputs
    @State private var isin            = ""
    @State private var acquisitionDate = Date()
    @State private var parValue        = ""
    @State private var acquisitionPrice = ""
    @State private var depotBank       = ""

    // MARK: – Scraped
    @State private var name          = ""
    @State private var issuer        = ""
    @State private var wkn           = ""
    @State private var maturityDate  = Date()
    @State private var couponRate    = ""

    @State private var isLoading     = false
    @State private var errorMessage  = ""

    var body: some View {
        ZStack {
            //–– Main content, disabled when loading
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Text("Add Bond")
                        .font(.title)
                        .padding(.bottom, 8)

                    GroupBox("Required for Scraping") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("ISIN", text: $isin, onCommit: {
                                isin = isin.uppercased()
                            })
                            DatePicker("Acquisition Date",
                                       selection: $acquisitionDate,
                                       displayedComponents: .date)
                        }
                        .padding(.vertical, 4)
                    }

                    GroupBox("Manual Inputs") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Par Value",       text: $parValue)
                            TextField("Acquisition Price", text: $acquisitionPrice)
                            TextField("Depot Bank",      text: $depotBank)
                        }
                        .padding(.vertical, 4)
                    }

                    GroupBox("Scraped Data") {
                        VStack(alignment: .leading, spacing: 8) {
                            TextField("Bond Name",      text: $name).disabled(true)
                            TextField("Issuer",         text: $issuer).disabled(true)
                            TextField("WKN",            text: $wkn).disabled(true)
                            DatePicker("Maturity Date",
                                       selection: $maturityDate,
                                       displayedComponents: .date)
                                .disabled(true)
                            TextField("Coupon Rate (%)", text: $couponRate).disabled(true)
                        }
                        .padding(.vertical, 4)
                    }

                    if !errorMessage.isEmpty {
                        Text(errorMessage)
                            .foregroundColor(.red)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack {
                        Button("Cancel") {
                            dismiss()
                        }
                        .keyboardShortcut(.cancelAction)

                        Spacer()

                        Button("Scrape Data") {
                            startScrape()
                        }
                        .disabled(isLoading || isin.isEmpty)

                        Button("Save") {
                            saveBond()
                        }
                        .keyboardShortcut(.defaultAction)
                        .disabled(isLoading
                                  || name.isEmpty
                                  || issuer.isEmpty
                                  || wkn.isEmpty
                                  || parValue.isEmpty
                                  || acquisitionPrice.isEmpty
                                  || depotBank.isEmpty)
                    }
                }
                .padding(20)
            }
            .disabled(isLoading)

            //–– Overlay spinner
            if isLoading {
                Color.black.opacity(0.3)
                    .ignoresSafeArea()
                ProgressView("Scraping…")
                    .padding(20)
                    .background(.ultraThinMaterial)
                    .cornerRadius(8)
                    .shadow(radius: 4)
            }
        }
        .frame(minWidth: 600, minHeight: 500) // only in Preview; window sizing lives in your App/Scene
    }

    /// Kicks off the scrape but defers every state‐change to the next runloop turn,
    /// so AppKit/SwiftUI has finished any layout before we mutate @State.
    private func startScrape() {
        // 1) defer entering loading state
        DispatchQueue.main.async {
            isLoading = true
            errorMessage = ""
        }

        Task {
            do {
                let (nm, wk)       = try await scraper.fetchNameAndWKN(isin: isin)
                let comp          = try await scraper.fetchIssuer(isin: isin)
                let dts           = try await scraper.fetchDates(isin: isin)
                let cp            = try await scraper.fetchCouponRate(isin: isin)
                let cpStr         = String(format: "%.2f", cp)

                DispatchQueue.main.async {
                    name         = nm
                    wkn          = wk
                    issuer       = comp
                    maturityDate = dts.maturity
                    couponRate   = cpStr

                    isLoading    = false

                }
            } catch {
                print(">>> Scrape ERROR: \(error)")
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                    isLoading    = false
                }
            }
        }
    }

    private func saveBond() {
        guard let par    = Double(parValue),
              let coupon = Double(couponRate),
              let price  = Double(acquisitionPrice) else {
            print(">>> Save failed: numeric conversion error")
            errorMessage = "Numeric conversion failed."
            return
        }

        viewModel.addBond(
            name: name,
            issuer: issuer,
            isin: isin,
            wkn: wkn,
            parValue: par,
            couponRate: coupon,
            initialPrice: price,
            maturityDate: maturityDate,
            acquisitionDate: acquisitionDate,
            depotBank: depotBank
        )
        dismiss()
    }
}

struct AddBondViewAsync_Previews: PreviewProvider {
    static var previews: some View {
        AddBondViewAsync(viewModel: BondPortfolioViewModel())
    }
}
