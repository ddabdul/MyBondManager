//
//  InstrumentHeaderTestView.swift
//  MyBondManager
//
//  Created by Olivier on 30/04/2025.
//


//  MyBondManager
// ETFTestView.swift
//  A SwiftUI view to test InstrumentHeaderScraper
//  Created by Olivier on 30/04/2025.

import SwiftUI

@available(macOS 13.0, *)
struct ETFTestView: View {
    @State private var isin: String = ""
    @State private var price: Double?
    @State private var isLoading: Bool = false
    @State private var errorMessage: String?

    private let scraper = InstrumentHeaderScraper()

    var body: some View {
        VStack(spacing: 20) {
            Text("ETF Price Scraper")
                .font(.title)

            TextField("Enter ISIN (e.g. LU0290358497)", text: $isin)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            Button(action: fetchPrice) {
                if isLoading {
                    ProgressView()
                } else {
                    Text("Fetch Price")
                }
            }
            .disabled(isLoading || isin.isEmpty)

            if let price = price {
                Text("Price: \(price, specifier: "%.4f") EUR")
                    .font(.headline)
            }

            if let errorMessage = errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
            }

            Spacer()
        }
        .padding()
    }

    private func fetchPrice() {
        errorMessage = nil
        price = nil
        isLoading = true

        Task {
            do {
                let result = try await scraper.fetchPrice(isin: isin.trimmingCharacters(in: .whitespacesAndNewlines))
                DispatchQueue.main.async {
                    self.price = result
                    self.isLoading = false
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }
}

@available(macOS 13.0, *)
struct InstrumentHeaderTestView_Previews: PreviewProvider {
    static var previews: some View {
        ETFTestView()
    }
}
