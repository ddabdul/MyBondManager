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
                                    Text("Collect")
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
        .background(AppTheme.panelBackground) // Set panelBackground for the overall background
        // Remove the explicit frame to fit content
    }

    private var canSave: Bool {
        Double(acquisitionPrice) != nil &&
        Int32(numberOfShares) != nil &&
        ((mode == .existing && selectedETF != nil) ||
         (mode == .new && fetchedHeader != nil))
    }

    // MARK: – Fetch header
    private func fetchHeader() async {
        fetchError = nil
        fetchedHeader = nil
        isFetching = true
        defer { isFetching = false }

        do {
            let header = try await scraper.fetchInstrumentHeader(isin: newISIN)
            await MainActor.run { fetchedHeader = header }
        } catch {
            await MainActor.run { fetchError = error }
        }
    }

    // MARK: – Save holding
    private func saveHolding() {
        let etf: ETFEntity
        if mode == .existing {
            etf = selectedETF!
        } else {
            etf = ETFEntity(context: viewContext)
            etf.id = UUID()
            etf.etfName = fetchedHeader!.name
            etf.isin = newISIN
            etf.wkn = fetchedHeader!.wkn
            etf.lastPrice = fetchedHeader!.price
            etf.issuer = ""
        }

        let holding = ETFHoldings(context: viewContext)
        holding.acquisitionDate = acquisitionDate
        holding.acquisitionPrice = Double(acquisitionPrice)!
        holding.numberOfShares = Int32(Int(numberOfShares)!)
        holding.holdingtoetf = etf

        if let latest = fetchedHeader?.price {
            etf.lastPrice = latest
        }

        do {
            try viewContext.save()
            // Clear inputs
            acquisitionPrice = ""
            numberOfShares = ""
            if mode == .new {
                newISIN = ""
                fetchedHeader = nil
            }
            showSuccess = true
        } catch {
            print("Core Data save error:", error)
        }
    }
}
