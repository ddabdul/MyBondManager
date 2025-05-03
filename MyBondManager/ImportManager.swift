
//
//  ImportManager.swift
//  MyBondManager
//  Created by Olivier on 10/05/2025.
//  Updated 10/05/2025 – re-import JSON & merge into Core Data
//

import Foundation
import CoreData

// MARK: – Codable mirrors (same as your ExportManager)

//Moved in CoreDataCodable

// MARK: – ImportManager

public class ImportManager {
    public init() {}

    /// Read `bonds.json` & `etfs.json` from `folderURL`, then insert/update your Core Data store.
    /// - Parameters:
    ///   - folderURL: directory where you previously wrote your JSONs
    ///   - context: an NSManagedObjectContext (call on a background context if you like)
    /// - Throws: any file‐I/O, decoding, or Core Data error
    public func importAll(
        from folderURL: URL,
        into context: NSManagedObjectContext
    ) throws {
        // 1) Acquire security‐scoped access (if using fileImporter)
        let granted = folderURL.startAccessingSecurityScopedResource()
        defer {
            if granted {
                folderURL.stopAccessingSecurityScopedResource()
            }
        }

        // 2) Perform everything inside the context’s queue
        var caught: Error?
        context.performAndWait {
            do {
                try importBonds(from: folderURL, into: context)
                try importETFs(from: folderURL, into: context)
                if context.hasChanges {
                    try context.save()
                }
            }
            catch {
                caught = error
            }
        }
        if let error = caught {
            throw error
        }
    }

    // MARK: • Bonds

    private func importBonds(
        from folderURL: URL,
        into context: NSManagedObjectContext
    ) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let url = folderURL.appendingPathComponent("bonds.json")
        let data = try Data(contentsOf: url)
        let jsonBonds = try decoder.decode([BondCodable].self, from: data)

        // Fetch existing or insert new
        for jb in jsonBonds {
            let req: NSFetchRequest<BondEntity> = BondEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", jb.id as CVarArg)
            let matches = try context.fetch(req)
            let bond: BondEntity = matches.first ?? BondEntity(context: context)

            // Always overwrite scalar properties
            bond.id               = jb.id
            bond.name             = jb.name
            bond.isin             = jb.isin
            bond.issuer           = jb.issuer
            bond.depotBank        = jb.depotBank
            bond.acquisitionDate  = jb.acquisitionDate
            bond.maturityDate     = jb.maturityDate
            bond.couponRate       = jb.couponRate
            bond.parValue         = jb.parValue
            bond.initialPrice     = jb.initialPrice
            bond.yieldToMaturity  = jb.yieldToMaturity

            // Remove old cash flows
            for cf in bond.cashFlowsArray {
                context.delete(cf)
            }

            // Add new cash flows
            for cfj in jb.cashFlows {
                let cf = CashFlowEntity(context: context)
                cf.date      = cfj.date
                cf.amount    = cfj.amount
                cf.nature    = cfj.nature
                bond.addToCashFlows(cf)
            }
        }
    }

    // MARK: • ETFs

    private func importETFs(
        from folderURL: URL,
        into context: NSManagedObjectContext
    ) throws {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let url = folderURL.appendingPathComponent("etfs.json")
        let data = try Data(contentsOf: url)
        let jsonETFs = try decoder.decode([ETFEntityCodable].self, from: data)

        for je in jsonETFs {
            let req: NSFetchRequest<ETFEntity> = ETFEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", je.id as CVarArg)
            let matches = try context.fetch(req)
            let etf: ETFEntity = matches.first ?? ETFEntity(context: context)

            // Overwrite scalar props
            etf.id        = je.id
            etf.etfName   = je.etfName
            etf.isin      = je.isin
            etf.issuer    = je.issuer
            etf.wkn       = je.wkn
            etf.lastPrice = je.lastPrice

            // Remove old price history
            if let oldPrices = etf.etfPriceMany as? Set<ETFPrice> {
                for p in oldPrices {
                    context.delete(p)
                }
            }
            // Add new prices
            for pj in je.priceHistory {
                let p = ETFPrice(context: context)
                p.datePrice = pj.datePrice
                p.price     = pj.price
                etf.addToEtfPriceMany(p)
            }

            // Remove old holdings
            if let oldH = etf.etftoholding as? Set<ETFHoldings> {
                for h in oldH {
                    context.delete(h)
                }
            }
            // Add new holdings
            for hj in je.holdings {
                let h = ETFHoldings(context: context)
                h.acquisitionDate  = hj.acquisitionDate
                h.acquisitionPrice = hj.acquisitionPrice
                h.numberOfShares   = hj.numberOfShares
                etf.addToEtftoholding(h)
            }
        }
    }
}
