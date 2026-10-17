//
//  MyBondManager
//  AddETFView.swift
//  A SwiftUI form view for adding a new ETF position
//  Created by Olivier on 30/04/2025.

import SwiftUI
import CoreData

@available(macOS 13.0, *)
struct AddHoldingView: View {
    // MARK: – Core Data
    @Environment(\.portfolioContainer) private var portfolioContainer
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss)           private var dismiss: DismissAction // Explicitly specify DismissAction

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ETFEntity.etfName, ascending: true)],
        animation: .default)
    private var allETFs: FetchedResults<ETFEntity>

    // MARK: – UI State
    enum Mode { case existing, new }
    @State private var mode: Mode = .existing

    // existing ETF selection
    @State private var selectedETF: ETFEntity?

    // new ETF fields
    @State private var newISIN: String = ""
    @State private var fetchedHeader: InstrumentHeaderScraper.ETFInstrumentHeader?
    @State private var isFetching = false
    @State private var fetchedISIN: String?
    @State private var activeRequest: UUID?
    @State private var isSaving = false
    @State private var errorMessage: String?
    @State private var fetchError: Error?

    // holding fields (shared)
    @State private var acquisitionDate: Date = Date()
    @State private var acquisitionPrice: String = ""
    @State private var numberOfShares: String = ""

    // success state
    @State private var showSuccess = false

    private let scraper = InstrumentHeaderScraper()

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

                Text("Add an ETF Holding")
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
                if let errorMessage { Text(errorMessage).foregroundColor(.red) }
                // Mode picker
                Picker("", selection: $mode) {
                    Text("Add to an existing ETF").tag(Mode.existing)
                    Text("Add a new ETF").tag(Mode.new)
                }
                .pickerStyle(.segmented)
                .padding(.bottom)

                // Existing ETF selection
                if mode == .existing {
                    Section(header: Text("Select an ETF")) {
                        Picker("Existing ETF", selection: $selectedETF) {
                            Text("(none)").tag(Optional<ETFEntity>(nil))
                            ForEach(allETFs) { etf in
                                Text(etf.etfName).tag(Optional(etf))
                            }
                        }
                        .labelsHidden()
                    }
                }

                // New ETF fetch
                if mode == .new {
                    Section(header: Text("Enter the ISIN to collect the ETF Data")) {
                        HStack {
                            TextField("ISIN", text: $newISIN)
                                .textFieldStyle(.roundedBorder)
                            Button {
                                Task { await fetchHeader() }
                            } label: {
                                if isFetching {
                                    ProgressView()
                                } else {
                                    Text("ADD")
                                }
                            }
                            .disabled(newISIN.isEmpty || isFetching)
                        }

                        if let header = fetchedHeader {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(header.name).font(.headline)
                                Text("WKN: \(header.wkn)")
                                Text("Price: \(header.price, specifier: "%.2f") \(header.currency ?? "")")
                            }
                        }

                        if let err = fetchError {
                            Text(err.localizedDescription)
                                .foregroundColor(.red)
                        }
                    }
                }

                // Holding inputs
                if (mode == .existing && selectedETF != nil)
                    || (mode == .new && fetchedHeader != nil)
                {
                    Section(header: Text("Holding Details")) {
                        DatePicker(
                            "Acquisition Date",
                            selection: $acquisitionDate,
                            in: ...Date(),
                            displayedComponents: .date
                        )
                        TextField("Acquisition Price", text: $acquisitionPrice)
                        TextField("Number of Shares", text: $numberOfShares)
                    }

                    // Button bar: Save
                    Section {
                        HStack {
                            Spacer()
                            Button("Save Holding") {
                                saveHolding()
                            }
                            .disabled(!canSave)
                            .keyboardShortcut(.defaultAction)
                        }
                    }

                    // Success message
                    if showSuccess {
                        Section {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Holding created successfully!")
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                }
            }
            .padding()
            Spacer()
        }
        .onChange(of: newISIN) { _, _ in invalidateHeader() }
        .onChange(of: mode) { _, _ in invalidateHeader() }
        .background(AppTheme.panelBackground) // Set panelBackground for the overall background
        // Remove the explicit frame to fit content
    }

    private var canSave: Bool {
        guard !isSaving, let price = Double(acquisitionPrice), let shares = Int32(numberOfShares),
              price.isFinite, price > 0, shares > 0 else { return false }
        return mode == .existing ? selectedETF != nil
            : fetchedHeader != nil && fetchedISIN == ETFPurchase.normalizedISIN(newISIN)
    }

    private func invalidateHeader() {
        fetchedHeader = nil; fetchedISIN = nil; activeRequest = nil
        isFetching = false; fetchError = nil; showSuccess = false
    }

    @MainActor private func fetchHeader() async {
        let requestedISIN = ETFPurchase.normalizedISIN(newISIN)
        let request = UUID()
        activeRequest = request; fetchedHeader = nil; fetchedISIN = nil
        isFetching = true; fetchError = nil
        defer { if activeRequest == request { isFetching = false } }
        do {
            let header = try await scraper.fetchInstrumentHeader(isin: requestedISIN)
            guard ETFPurchase.acceptsHeader(requestedISIN: requestedISIN, currentISIN: newISIN,
                isNewMode: mode == .new, requestedID: request, activeID: activeRequest) else { return }
            fetchedHeader = header; fetchedISIN = requestedISIN
        } catch {
            if activeRequest == request { fetchError = error }
        }
    }

    private func saveHolding() {
        guard !isSaving, let container = portfolioContainer else {
            errorMessage = "Portfolio store is unavailable."
            return
        }
        guard canSave, let price = Double(acquisitionPrice), let shares = Int32(numberOfShares) else {
            errorMessage = "Enter valid purchase details and fetch matching instrument data."
            return
        }
        let isin = ETFPurchase.normalizedISIN(newISIN)
        let header = mode == .new ? fetchedHeader : nil
        let existingID = mode == .existing ? selectedETF?.objectID : nil
        let date = acquisitionDate
        isSaving = true; errorMessage = nil; showSuccess = false
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await PortfolioTransaction.run(in: container) { context in
                    try ETFPurchase.stage(isin: isin, header: header, existingID: existingID,
                        date: date, price: price, shares: shares, context: context)
                }
                acquisitionPrice = ""; numberOfShares = ""
                if mode == .new { newISIN = ""; invalidateHeader() }
                showSuccess = true
            } catch { errorMessage = "Could not save holding: \(error.localizedDescription)" }
        }
    }
}
