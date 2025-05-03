//
//  ExportManager.swift
//  MyBondManager
//  Updated 10/05/2025 – full‐folder access via security‐scoped URLs
//

import Foundation
import CoreData

// MARK: – Codable mirrors

//Moved to CoreDataCodable

// MARK: – ExportManager

public class ExportManager {
    public init() {}

    /// Export both JSON files into `folderURL`, handling security-scoped access.
    /// Throws on any error.
    public func exportAll(
        to folderURL: URL,
        from context: NSManagedObjectContext
    ) throws {
        // ① Acquire permission for the entire folder
        let granted = folderURL.startAccessingSecurityScopedResource()
        defer {
            if granted {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        // ② Do the writes
        try exportBonds(from: context, to: folderURL)
        try exportETFs(from: context, to: folderURL)
    }

    // ─── Bonds ──────────────────────────────────────────────────────────

    private func exportBonds(
        from context: NSManagedObjectContext,
        to folderURL: URL
    ) throws {
        let req: NSFetchRequest<BondEntity> = BondEntity.fetchRequest()
        let bonds = try context.fetch(req)

        let codables = bonds.map { bond in
            let flows = bond.cashFlowsArray.map {
                CashFlowCodable(date: $0.date,
                                amount: $0.amount,
                                nature: $0.nature)
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

    // ─── ETFs ───────────────────────────────────────────────────────────

    private func exportETFs(
        from context: NSManagedObjectContext,
        to folderURL: URL
    ) throws {
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
