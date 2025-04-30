//  MyBondManager
//  AddETFView.swift
//  A SwiftUI form view for adding a new ETF position
//  Created by Olivier on 30/04/2025.

import SwiftUI

@available(macOS 13.0, *)
struct AddETFView: View {
    @State private var isin: String = ""
    @State private var shares: String = ""
    @State private var acquisitionPrice: String = ""
    @State private var acquisitionDate: Date = Date()

    @State private var fetchedHeader: InstrumentHeaderScraper.ETFInstrumentHeader?
    @State private var issuer: String?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    private let headerScraper = InstrumentHeaderScraper()
    private let bondScraper = BondDataScraper()

    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("ETF Details")) {
                    TextField("ISIN (e.g. LU0290358497)", text: $isin)
                        .textFieldStyle(DefaultTextFieldStyle())
                    TextField("Number of Shares", text: $shares)
                    TextField("Acquisition Price (EUR)", text: $acquisitionPrice)
                    DatePicker("Acquisition Date", selection: $acquisitionDate, displayedComponents: .date)
                }

                Section(header: Text("Fetched Info")) {
                    if let header = fetchedHeader {
                        Text("Name: \(header.name)")
                        Text("WKN: \(header.wkn)")
                        Text("Issuer: \(issuer ?? "-")")
                        if let type = header.instrumentType {
                            Text("Type: \(type)")
                        }
                        if let currency = header.currency {
                            Text("Currency: \(currency)")
                        }
                    } else if isLoading {
                        HStack { Spacer(); ProgressView(); Spacer() }
                    } else {
                        Text("No data fetched yet")
                            .foregroundColor(.secondary)
                    }
                }

                if let error = errorMessage {
                    Section {
                        Text(error)
                            .foregroundColor(.red)
                    }
                }

                Section {
                    Button("Fetch Info", action: fetchMetadata)
                        .disabled(isLoading || isin.trimmingCharacters(in: .whitespaces).isEmpty)
                    Button("Add ETF", action: saveETF)
                        .disabled(fetchedHeader == nil || shares.isEmpty || acquisitionPrice.isEmpty)
                }
            }
            .navigationTitle("Add New ETF")
        }
    }

    private func fetchMetadata() {
        errorMessage = nil
        fetchedHeader = nil
        issuer = nil
        isLoading = true

        Task {
            do {
                let header = try await headerScraper.fetchInstrumentHeader(isin: isin.trimmingCharacters(in: .whitespaces))
                let iss = try await bondScraper.fetchIssuer(isin: isin.trimmingCharacters(in: .whitespaces))
                DispatchQueue.main.async {
                    fetchedHeader = header
                    issuer = iss
                    isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    errorMessage = error.localizedDescription
                    isLoading = false
                }
            }
        }
    }

    private func saveETF() {
        guard let header = fetchedHeader,
              let shareCount = Double(shares),
              let acqPrice = Double(acquisitionPrice) else { return }
        // TODO: Persist the ETF position (e.g., to Core Data)
        print("Added ETF: \(header.name) (\(header.wkn)), ISIN: \(isin), Shares: \(shareCount), " +
              "Acquire Price: \(acqPrice), Date: \(acquisitionDate), Issuer: \(issuer ?? "N/A")")
    }
}

@available(macOS 13.0, *)
struct AddETFView_Previews: PreviewProvider {
    static var previews: some View {
        AddETFView()
    }
}
