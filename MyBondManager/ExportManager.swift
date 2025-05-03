
//
//  ExportManager.swift
//  MyBondManager
//
//  Created by Olivier on 03/05/2025.
//

import Foundation
import CoreData

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
    let id: String                // use the Core Data objectID URI as a stable string
    let datePrice: Date
    let price: Double
    let etfId: UUID
}

public struct ETFHoldingsCodable: Codable {
    let id: String                // same here
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
    private let containerIdentifier: String

    /// The iCloud Drive Documents folder for your app
    private var documentsURL: URL {
        guard let base = FileManager.default
                .url(forUbiquityContainerIdentifier: containerIdentifier)?
                .appendingPathComponent("Documents")
        else {
            fatalError("iCloud container '\(containerIdentifier)' unavailable")
        }
        if !FileManager.default.fileExists(atPath: base.path) {
            try? FileManager.default.createDirectory(
              at: base,
              withIntermediateDirectories: true
            )
        }
        return base
    }

    public init(containerIdentifier: String) {
        self.containerIdentifier = containerIdentifier
    }

    /// Export *all* entities to JSON files in iCloud Drive
    public func exportAll(from context: NSManagedObjectContext) throws {
        try exportBonds(from: context)
        try exportETFs(from: context)
    }

    // MARK: • Bonds

    private func exportBonds(from context: NSManagedObjectContext) throws {
        let req: NSFetchRequest<BondEntity> = BondEntity.fetchRequest()
        let bonds = try context.fetch(req)

        let codables = bonds.map { bond -> BondCodable in
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
        let fileURL = documentsURL.appendingPathComponent("bonds.json")
        try data.write(to: fileURL, options: .atomic)
    }

    // MARK: • ETFs

    private func exportETFs(from context: NSManagedObjectContext) throws {
        let req: NSFetchRequest<ETFEntity> = ETFEntity.fetchRequest()
        let etfs = try context.fetch(req)

        let codables = etfs.map { etf -> ETFEntityCodable in
            // 1) Price history
            let prices = (etf.etfPriceMany as? Set<ETFPrice>)?.map { price in
                ETFPriceCodable(
                  id: price.objectID.uriRepresentation().absoluteString,
                  datePrice: price.datePrice,
                  price: price.price,
                  etfId: etf.id
                )
            } ?? []

            // 2) Holdings
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
        let fileURL = documentsURL.appendingPathComponent("etfs.json")
        try data.write(to: fileURL, options: .atomic)
    }
}
