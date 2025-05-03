//
//  ExportManager.swift
//  MyBondManager
//
//  Created by Olivier on 03/05/2025.
//  Updated 05/05/2025 – use runModal + security-scoped bookmarks
//

import Foundation
import CoreData
import AppKit    // for NSOpenPanel

// MARK: – Codable mirrors

public struct CashFlowCodable: Codable {
    let date: Date
    let amount: Double
    let nature: String
}

public struct BondCodable: Codable {
    let id: UUID
    let name: String
    let isin: String
    let issuer: String
    let depotBank: String
    let acquisitionDate: Date
    let maturityDate: Date
    let couponRate: Double
    let parValue: Double
    let initialPrice: Double
    let yieldToMaturity: Double
    let cashFlows: [CashFlowCodable]
}

public struct ETFPriceCodable: Codable {
    let id: String
    let datePrice: Date
    let price: Double
    let etfId: UUID
}

public struct ETFHoldingsCodable: Codable {
    let id: String
    let etfId: UUID
    let acquisitionDate: Date
    let acquisitionPrice: Double
    let numberOfShares: Int32
}

public struct ETFEntityCodable: Codable {
    let id: UUID
    let etfName: String
    let isin: String
    let issuer: String
    let wkn: String
    let lastPrice: Double
    let priceHistory: [ETFPriceCodable]
    let holdings: [ETFHoldingsCodable]
}

// MARK: – ExportManager

public class ExportManager {
    public init() {}

    /// Brings up a folder-picker (modal), then writes both JSONs into that folder.
    public func exportAllWithUserChoice(from context: NSManagedObjectContext) {
        let panel = NSOpenPanel()
        panel.title                   = "Choose folder to save JSON export"
        panel.canChooseFiles          = false
        panel.canChooseDirectories    = true
        panel.allowsMultipleSelection = false

        // runModal spins its own event loop and avoids the 500 ms deferral timeout
        DispatchQueue.main.async {
            let result = panel.runModal()
            guard result == .OK, let folderURL = panel.url else { return }

            // Gain permission to write there
            let granted = folderURL.startAccessingSecurityScopedResource()
            defer {
                if granted {
                    folderURL.stopAccessingSecurityScopedResource()
                }
            }

            do {
                try self.exportBonds(from: context, to: folderURL)
                try self.exportETFs(from: context, to: folderURL)
                // Optionally: show a “Success” alert here
            }
            catch {
                // Surface the error however you prefer
                print("Export failed:", error)
            }
        }
    }

    // MARK: • Bonds

    private func exportBonds(from context: NSManagedObjectContext, to folderURL: URL) throws {
        let req: NSFetchRequest<BondEntity> = BondEntity.fetchRequest()
        let bonds = try context.fetch(req)

        let codables = bonds.map { bond in
            let flows = bond.cashFlowsArray.map {
                CashFlowCodable(date: $0.date, amount: $0.amount, nature: $0.nature)
            }
            return BondCodable(
                id: bond.id,
                name: bond.name,
                isin: bond.isin,
                issuer: bond.issuer,
                depotBank: bond.depotBank,
                acquisitionDate: bond.acquisitionDate,
                maturityDate: bond.maturityDate,
                couponRate: bond.couponRate,
                parValue: bond.parValue,
                initialPrice: bond.initialPrice,
                yieldToMaturity: bond.yieldToMaturity,
                cashFlows: flows
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(codables)

        let fileURL = folderURL.appendingPathComponent("bonds.json", isDirectory: false)
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: • ETFs

    private func exportETFs(from context: NSManagedObjectContext, to folderURL: URL) throws {
        let req: NSFetchRequest<ETFEntity> = ETFEntity.fetchRequest()
        let etfs = try context.fetch(req)

        let codables = etfs.map { etf in
            let prices = (etf.etfPriceMany as? Set<ETFPrice>)?.map { price in
                ETFPriceCodable(
                    id: price.objectID.uriRepresentation().absoluteString,
                    datePrice: price.datePrice,
                    price: price.price,
                    etfId: etf.id
                )
            } ?? []

            let holds = (etf.etftoholding as? Set<ETFHoldings>)?.map { h in
                ETFHoldingsCodable(
                    id: h.objectID.uriRepresentation().absoluteString,
                    etfId: etf.id,
                    acquisitionDate: h.acquisitionDate,
                    acquisitionPrice: h.acquisitionPrice,
                    numberOfShares: h.numberOfShares
                )
            } ?? []

            return ETFEntityCodable(
                id: etf.id,
                etfName: etf.etfName,
                isin: etf.isin,
                issuer: etf.issuer,
                wkn: etf.wkn,
                lastPrice: etf.lastPrice,
                priceHistory: prices,
                holdings: holds
            )
        }

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(codables)

        let fileURL = folderURL.appendingPathComponent("etfs.json", isDirectory: false)
        try data.write(to: fileURL, options: .atomic)
    }
}
