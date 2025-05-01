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
    @Environment(\.dismiss)        private var dismiss

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
        Form {
            // Mode picker
            Picker("Mode", selection: $mode) {
                Text("Add to Existing ETF").tag(Mode.existing)
                Text("Add New ETF + Holding").tag(Mode.new)
            }
            .pickerStyle(.segmented)
            .padding(.bottom)
            
            // Existing ETF selection
            if mode == .existing {
                Section(header: Text("Select ETF")) {
                    Picker("ETF", selection: $selectedETF) {
                        ForEach(allETFs) { etf in
                            Text(etf.etfName).tag(Optional(etf))
                        }
                    }
                    .labelsHidden()
                }
            }
            
            // New ETF fetch
            if mode == .new {
                Section(header: Text("Fetch ETF Header")) {
                    HStack {
                        TextField("ISIN", text: $newISIN)
                            .textFieldStyle(.roundedBorder)
                        Button {
                            Task { await fetchHeader() }
                        } label: {
                            if isFetching {
                                ProgressView()
                            } else {
                                Text("Fetch")
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
                        in: ...Date(),                  // limit to today or earlier
                        displayedComponents: .date
                    )
                    TextField("Acquisition Price", text: $acquisitionPrice)
                    TextField("Number of Shares", text: $numberOfShares)
                }
                
                // Button bar: Close + Save
                Section {
                    HStack {
                        Button("Close") {
                            dismiss()
                        }
                        .keyboardShortcut(.cancelAction)
                        
                        Spacer()
                        
                        Button("Save Holding") {
                            saveHolding()
                        }
                        .disabled(!canSave)
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
