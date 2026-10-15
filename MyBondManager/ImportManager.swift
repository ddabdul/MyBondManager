//
//  ImportManager.swift
//  MyBondManager
//  Created by Olivier on 10/05/2025.
//  Updated 15/05/2025 – now removes deleted items from Core Data
//

import Foundation
import CoreData

// MARK: – ImportManager

public class ImportManager {
    public init() {}

    public func prepare(from folderURL: URL) async throws -> PositionsPayload {
        let granted = folderURL.startAccessingSecurityScopedResource()
        defer { if granted { folderURL.stopAccessingSecurityScopedResource() } }
        return try await Task.detached(priority: .userInitiated) {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let bonds = try decoder.decode([BondCodable].self,
                from: Data(contentsOf: folderURL.appendingPathComponent("bonds.json")))
            let etfs = try decoder.decode([ETFEntityCodable].self,
                from: Data(contentsOf: folderURL.appendingPathComponent("etfs.json")))
            let payload = PositionsPayload(bonds: bonds, etfs: etfs)
            try Self.validate(payload)
            return payload
        }.value
    }

    public func importAll(from folderURL: URL, into container: NSPersistentContainer) async throws {
        let payload = try await prepare(from: folderURL)
        try await apply(payload, into: container)
    }

    public func apply(_ payload: PositionsPayload, into container: NSPersistentContainer) async throws {
        try Self.validate(payload)
        try await PortfolioTransaction.run(in: container) { context in
            try self.importBonds(payload.bonds, into: context)
            try self.importETFs(payload.etfs, into: context)
        }
    }

    static func validate(_ payload: PositionsPayload) throws {
        guard Set(payload.bonds.map(\.id)).count == payload.bonds.count,
              Set(payload.etfs.map(\.id)).count == payload.etfs.count else {
            throw PortfolioError("The positions files contain duplicate identifiers.")
        }
        for bond in payload.bonds {
            guard bond.parValue.isFinite, bond.parValue > 0,
                  bond.initialPrice.isFinite, bond.initialPrice > 0,
                  bond.couponRate.isFinite, bond.couponRate >= 0,
                  bond.yieldToMaturity.isFinite, bond.acquisitionDate <= bond.maturityDate,
                  bond.cashFlows.allSatisfy({ $0.amount.isFinite && CashFlowEntity.Nature(rawValue: $0.nature) != nil }) else {
                throw PortfolioError("Invalid financial values in bond \(bond.name).")
            }
        }
        for etf in payload.etfs {
            guard !ETFPurchase.normalizedISIN(etf.isin).isEmpty,
                  etf.lastPrice.isFinite, etf.lastPrice > 0,
                  Set(etf.holdings.map(\.id)).count == etf.holdings.count,
                  Set(etf.priceHistory.map(\.id)).count == etf.priceHistory.count,
                  etf.holdings.allSatisfy({ $0.etfId == etf.id && $0.numberOfShares > 0
                      && $0.acquisitionPrice.isFinite && $0.acquisitionPrice > 0 }),
                  etf.priceHistory.allSatisfy({ $0.etfId == etf.id && $0.price.isFinite && $0.price > 0 }) else {
                throw PortfolioError("Invalid holdings, prices or identifiers in ETF \(etf.etfName).")
            }
        }
    }

    // MARK: • Bonds

    private func importBonds(
        _ jsonBonds: [BondCodable],
        into context: NSManagedObjectContext
    ) throws {
        // Track existing IDs
        let fetchAll: NSFetchRequest<BondEntity> = BondEntity.fetchRequest()
        let existingBonds = try context.fetch(fetchAll)
        let existingIDs = Set(existingBonds.map(\.id))
        guard existingIDs.count == existingBonds.count else { throw PortfolioError("Stored bonds contain duplicate identifiers.") }
        var jsonIDs = Set<UUID>()

        for jb in jsonBonds {
            jsonIDs.insert(jb.id)

            let req: NSFetchRequest<BondEntity> = BondEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", jb.id as CVarArg)
            let matches = try context.fetch(req)
            let bond: BondEntity = matches.first ?? BondEntity(context: context)

            let retainedAliases: Data?
            if let existing = matches.first, ETFPurchase.normalizedISIN(existing.isin) == ETFPurchase.normalizedISIN(jb.isin) {
                retainedAliases = try BondTermsStore.encode(BondTermsStore.captureLegacyAliases(existing))
            } else { retainedAliases = nil }
            BondTermsStore.clear(bond)
            bond.legacyEventAliasesData = retainedAliases
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
            bond.wkn              = jb.wkn

            // Replace cash flows
            for cf in bond.cashFlowsArray {
                context.delete(cf)
            }
            for cfj in jb.cashFlows {
                let cf = CashFlowEntity(context: context)
                cf.date   = cfj.date
                cf.amount = cfj.amount
                cf.nature = cfj.nature
                bond.addToCashFlows(cf)
            }
        }

        // Delete removed items
        let toDeleteIDs = existingIDs.subtracting(jsonIDs)
        for bond in existingBonds where toDeleteIDs.contains(bond.id) {
            context.delete(bond)
        }
    }

    // MARK: • ETFs

    private func importETFs(
        _ jsonETFs: [ETFEntityCodable],
        into context: NSManagedObjectContext
    ) throws {
        // Track existing IDs
        let fetchAll: NSFetchRequest<ETFEntity> = ETFEntity.fetchRequest()
        let existingETFs = try context.fetch(fetchAll)
        let existingIDs = Set(existingETFs.compactMap { $0.id })
        var jsonIDs = Set<UUID>()

        for je in jsonETFs {
            jsonIDs.insert(je.id)

            let req: NSFetchRequest<ETFEntity> = ETFEntity.fetchRequest()
            req.predicate = NSPredicate(format: "id == %@", je.id as CVarArg)
            let matches = try context.fetch(req)
            let etf: ETFEntity = matches.first ?? ETFEntity(context: context)

            etf.id        = je.id
            etf.etfName   = je.etfName
            etf.isin      = je.isin
            etf.issuer    = je.issuer
            etf.wkn       = je.wkn
            etf.lastPrice = je.lastPrice

            // Replace price history
            if let oldPrices = etf.etfPriceMany as? Set<ETFPrice> {
                for p in oldPrices {
                    context.delete(p)
                }
            }
            for pj in je.priceHistory {
                let p = ETFPrice(context: context)
                p.datePrice = pj.datePrice
                p.price     = pj.price
                etf.addToEtfPriceMany(p)
            }

            // Replace holdings
            if let oldH = etf.etftoholding as? Set<ETFHoldings> {
                for h in oldH {
                    context.delete(h)
                }
            }
            for hj in je.holdings {
                let h = ETFHoldings(context: context)
                h.acquisitionDate  = hj.acquisitionDate
                h.acquisitionPrice = hj.acquisitionPrice
                h.numberOfShares   = hj.numberOfShares
                etf.addToEtftoholding(h)
            }
        }

        // Delete removed items
        let toDeleteIDs = existingIDs.subtracting(jsonIDs)
        for etf in existingETFs where toDeleteIDs.contains(etf.id) {
            context.delete(etf)
        }
    }
}

extension ImportManager {
    func prepareBonds(from folderURL: URL) async throws -> PreparedBondTransfer {
        let granted = folderURL.startAccessingSecurityScopedResource()
        defer { if granted { folderURL.stopAccessingSecurityScopedResource() } }
        return try await Task.detached(priority: .userInitiated) {
            let names = try FileManager.default.contentsOfDirectory(atPath: folderURL.path)
            let bonds = try Data(contentsOf: folderURL.appendingPathComponent("bonds.json"))
            let sidecar = names.contains("bond-terms.json") ? try Data(contentsOf: folderURL.appendingPathComponent("bond-terms.json")) : nil
            return try BondTransfer.prepare(bonds: bonds, sidecar: sidecar)
        }.value
    }
    func applyBonds(_ transfer: PreparedBondTransfer, into container: NSPersistentContainer, now: Date = Date()) async throws {
        try BondTransfer.validate(transfer)
        try await PortfolioTransaction.run(in: container) { context in
            var aliases: [UUID: Data] = [:]
            let existing = try context.fetch(BondEntity.fetchRequest())
            for old in existing {
                guard let incoming = transfer.bonds.first(where: { $0.id == old.id }) else { continue }
                let history = HistoricalValuation.fetchRequest()
                history.predicate = NSPredicate(format: "eventKey BEGINSWITH %@", old.id.uuidString + "|")
                let sameTrade = ETFPurchase.normalizedISIN(old.isin) == ETFPurchase.normalizedISIN(incoming.isin)
                    && old.parValue == incoming.parValue && old.initialPrice == incoming.initialPrice
                    && old.depotBank == incoming.depotBank
                    && Int(old.acquisitionDate.timeIntervalSince1970) == Int(incoming.acquisitionDate.timeIntervalSince1970)
                let hasHistory = try context.count(for: history) > 0
                if transfer.native != nil && !sameTrade && hasHistory {
                    throw PortfolioError("Native import conflicts with local recorded trade history for " + old.name + ".")
                }
                if sameTrade {
                    let incomingTerms = transfer.native?.bonds.first { $0.id == old.id }?.terms
                    aliases[old.id] = try BondTermsStore.encode(BondTermsStore.captureLegacyAliases(old,
                        maturity: incomingTerms?.maturity))
                }
            }
            try self.importBonds(transfer.bonds, into: context)
            guard let native = transfer.native else { return }
            for entry in native.bonds {
                let request = BondEntity.fetchRequest(); request.predicate = NSPredicate(format: "id == %@", entry.id as CVarArg)
                guard let bond = try context.fetch(request).first else { throw PortfolioError("Imported holding is missing.") }
                bond.legacyEventAliasesData = aliases[bond.id]
                bond.termsAcquisitionDay = entry.acquisitionDay.rawValue; bond.termsLegacyDateZone = entry.legacyDateZone
                if let terms = entry.terms, terms.approvedAt != nil {
                    let preview = try BondSchedule.preview(trade: BondTermsStore.trade(bond), terms: terms, from: MarketDay(date: now))
                    try BondTermsStore.replaceProjections(for: bond, terms: terms, preview: preview, now: now,
                        acquisitionDay: entry.acquisitionDay, legacyDateZone: entry.legacyDateZone, context: context)
                    guard bond.termsReady else { throw PortfolioError(bond.termsIssue ?? "Imported terms need review.") }
                    bond.eventsActivateAfter = now
                }
                if let proposed = entry.draft ?? (entry.terms?.approvedAt == nil ? entry.terms : nil) {
                    var terms = proposed; if terms.isin.isEmpty { terms.isin = entry.isin }; terms.approvedAt = nil
                    try BondTermsStore.stageDraft(BondTermsDraft(baseline: BondBaseline.capture(bond), trade: BondTermsStore.trade(bond),
                        legacyDateZone: entry.legacyDateZone, proposed: terms, previewDay: MarketDay(date: now)), for: bond)
                }
                if !bond.termsReady { bond.termsIssue = entry.needsReviewReasons.joined(separator: "\n") }
            }
        }
    }
}
