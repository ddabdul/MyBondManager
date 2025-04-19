//
//  BondPortfolioViewModel.swift
//  BondPortfolioV2
//
//  Created by Olivier on 11/04/2025.
//

import Foundation

/// All the ways the user can sort their bonds.
enum BondSortOption: String, CaseIterable, Identifiable {
    case name              = "Bond Name"
    case issuer            = "Issuer"
    case acquisitionDate   = "Acquisition Date"
    case acquisitionPrice  = "Acquisition Price"
    case nominal           = "Nominal"           // Par Value
    case coupon            = "Coupon"
    case maturityDate      = "Maturity Date"
    case depotBank         = "Depot Bank"

    var id: Self { self }
}

class BondPortfolioViewModel: ObservableObject {
    @Published var bonds: [Bond] = []
    
    /// The currently selected sort order; whenever it changes we re‑sort.
    @Published var sortOption: BondSortOption = .maturityDate {
        didSet { sortBonds() }
    }
    
    // File persistence
    private let fileURL: URL = {
        let docs = FileManager.default.urls(
            for: .documentDirectory,
               in: .userDomainMask
        )[0]
        return docs.appendingPathComponent("bonds.json")
    }()
    
    init() {
        loadBonds()
    }
    
    func saveBonds() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            let data = try encoder.encode(bonds)
            try data.write(to: fileURL)
        } catch {
            print("Failed to save bonds:", error)
        }
    }
    
    func loadBonds() {
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            bonds = try decoder.decode([Bond].self, from: data)
            sortBonds()
        } catch {
            print("Failed to load bonds:", error)
        }
    }
    
    func addBond(name: String,
                 issuer: String,
                 isin: String,
                 wkn: String,
                 parValue: Double,
                 couponRate: Double,
                 initialPrice: Double,
                 maturityDate: Date,
                 acquisitionDate: Date,
                 depotBank: String) {
        let newBond = Bond(
            id: UUID(),
            name: name,
            issuer: issuer,
            isin: isin,
            wkn: wkn,
            parValue: parValue,
            couponRate: couponRate,
            initialPrice: initialPrice,
            maturityDate: maturityDate,
            acquisitionDate: acquisitionDate,
            depotBank: depotBank
        )
        bonds.append(newBond)
        sortBonds()
        saveBonds()
    }
    
    func removeBond(at offsets: IndexSet) {
        bonds.remove(atOffsets: offsets)
        saveBonds()
    }
    
    /// Sorts `bonds` in place according to the current `sortOption`.
    func sortBonds() {
        switch sortOption {
        case .name:
            bonds.sort { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        case .issuer:
            bonds.sort { $0.issuer.localizedCaseInsensitiveCompare($1.issuer) == .orderedAscending }
        case .acquisitionDate:
            bonds.sort { $0.acquisitionDate < $1.acquisitionDate }
        case .acquisitionPrice:
            bonds.sort { $0.initialPrice < $1.initialPrice }
        case .nominal:
            bonds.sort { $0.parValue < $1.parValue }
        case .coupon:
            bonds.sort { $0.couponRate > $1.couponRate }  // highest first
        case .maturityDate:
            bonds.sort { $0.maturityDate < $1.maturityDate }
        case .depotBank:
            bonds.sort { $0.depotBank.localizedCaseInsensitiveCompare($1.depotBank) == .orderedAscending }
        }
    }
}
