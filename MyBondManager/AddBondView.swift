//
//  AddBondView.swift
//  BondPortfolioV2
//
//  Created by Olivier on 11/04/2025.
//

import SwiftUI

struct AddBondView: View {
    @Environment(\.dismiss) var dismiss
    @ObservedObject var viewModel: BondPortfolioViewModel

    private let scraper = BondDataScraper()

    // User inputs
    @State private var isin: String = ""
    @State private var acquisitionDate: Date = Date()
    @State private var parValue: String = ""
    @State private var acquisitionPrice: String = ""
    @State private var depotBank: String = ""

    // Scraped fields
    @State private var name: String = ""
    @State private var issuer: String = ""
    @State private var wkn: String = ""
    @State private var maturityDate: Date = Date()
    @State private var couponRate: String = ""

    // Loading / error
    @State private var isLoading = false
    @State private var errorMessage = ""

    var body: some View {
        VStack(alignment: .leading) {
            Text("Add Bond")
                .font(.title)
                .padding(.top)

            Form {
                Section("Required for Scraping") {
                    TextField("ISIN", text: $isin)
                        // Keep uppercase on macOS 14+
                        .onChange(of: isin) { _, new in
                            isin = new.uppercased()
                        }

                    DatePicker("Acquisition Date", selection: $acquisitionDate, displayedComponents: .date)
                }

                Section("Manual Inputs") {
                    TextField("Par Value", text: $parValue)
                    TextField("Acquisition Price", text: $acquisitionPrice)
                    TextField("Depot Bank", text: $depotBank)
                }

                Section("Scraped Data") {
                    TextField("Bond Name", text: $name)
                        .disabled(true)
                    TextField("Issuer", text: $issuer)
                        .disabled(true)
                    TextField("WKN", text: $wkn)
                        .disabled(true)
                    DatePicker("Maturity Date", selection: $maturityDate, displayedComponents: .date)
                        .disabled(true)
                    TextField("Coupon Rate (%)", text: $couponRate)
                        .disabled(true)
                }

                if !errorMessage.isEmpty {
                    Text(errorMessage)
                        .foregroundColor(.red)
                }

                if isLoading {
                    HStack {
                        Spacer()
                        ProgressView("Scraping…")
                        Spacer()
                    }
                }
            }
            .padding([.leading, .trailing])

            HStack {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Spacer()

                Button("Scrape Data") {
                    scrapeAll()
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
            .padding()
        }
        .frame(minWidth: 600, minHeight: 500)
    }

    private func scrapeAll() {
        isLoading = true
        errorMessage = ""

        scraper.fetchNameAndWKN(fromINGFor: isin) { result in
            switch result {
            case .success(let pair):
                self.name = pair.name
                self.wkn  = pair.wkn

                scraper.fetchIssuer(fromINGFor: isin) { issuerResult in
                    if case .success(let emittent) = issuerResult {
                        self.issuer = emittent
                    } else if case .failure(let err) = issuerResult {
                        self.errorMessage = err.localizedDescription
                    }

                    scraper.fetchDates(fromINGFor: isin) { dateResult in
                        if case .success(let tup) = dateResult {
                            self.maturityDate = tup.maturity
                        } else if case .failure(let err) = dateResult {
                            self.errorMessage = err.localizedDescription
                        }

                        scraper.fetchCouponRate(fromINGFor: isin) { couponResult in
                            DispatchQueue.main.async {
                                switch couponResult {
                                case .success(let rate):
                                    self.couponRate = String(format: "%.2f", rate)
                                case .failure(let err):
                                    self.errorMessage = err.localizedDescription
                                }
                                self.isLoading = false
                            }
                        }
                    }
                }

            case .failure(let err):
                self.errorMessage = err.localizedDescription
                self.isLoading = false
            }
        }
    }

    private func saveBond() {
        guard let par    = Double(parValue),
              let coupon = Double(couponRate),
              let price  = Double(acquisitionPrice)
        else {
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

struct AddBondView_Previews: PreviewProvider {
    static var previews: some View {
        AddBondView(viewModel: BondPortfolioViewModel())
    }
}
