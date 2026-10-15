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
    private let write: (Data, URL) throws -> Void
    public init(write: @escaping (Data, URL) throws -> Void = { data, url in
        try data.write(to: url, options: .atomic)
    }) { self.write = write }

    public func exportAll(to folderURL: URL, from context: NSManagedObjectContext) async throws -> URL {
        let granted = folderURL.startAccessingSecurityScopedResource()
        defer { if granted { folderURL.stopAccessingSecurityScopedResource() } }
        let snapshot = try await context.perform {
            guard !context.hasChanges else { throw PortfolioError("Save pending portfolio changes before exporting.") }
            return try Self.snapshot(from: context)
        }
        return try await Task.detached(priority: .userInitiated) {
            let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
            return try self.publish(files: [("bonds.json", encoder.encode(snapshot.bonds)),
                ("etfs.json", encoder.encode(snapshot.etfs))], to: folderURL, now: Date())
        }.value
    }
    func exportBonds(to folderURL: URL, from context: NSManagedObjectContext) async throws -> URL {
        let granted = folderURL.startAccessingSecurityScopedResource()
        defer { if granted { folderURL.stopAccessingSecurityScopedResource() } }
        let snapshot = try await context.perform { try BondTransfer.snapshot(from: context) }
        return try await Task.detached(priority: .userInitiated) {
            let files = try BondTransfer.encode(snapshot)
            return try self.publish(files: [("bonds.json", files.bonds), ("bond-terms.json", files.sidecar)], to: folderURL, now: Date())
        }.value
    }
    private func publish(files: [(name: String, data: Data)], to folderURL: URL, now: Date) throws -> URL {
        let staging = folderURL.appendingPathComponent(".positions-" + UUID().uuidString)
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian); formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let name = "positions-" + formatter.string(from: now)
        var published = folderURL.appendingPathComponent(name), suffix = 2
        while FileManager.default.fileExists(atPath: published.path) {
            published = folderURL.appendingPathComponent("\(name)-\(suffix)"); suffix += 1
        }
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: false)
        do {
            for file in files { try write(file.data, staging.appendingPathComponent(file.name)) }
            try FileManager.default.moveItem(at: staging, to: published)
            return published
        } catch {
            do { try FileManager.default.removeItem(at: staging) }
            catch { NSLog("Could not remove failed transfer staging directory: %@", error.localizedDescription) }
            throw error
        }
    }

    static func snapshot(from context: NSManagedObjectContext) throws -> PositionsPayload {
        PositionsPayload(bonds: try snapshotBonds(from: context), etfs: try snapshotETFs(from: context))
    }

    // ─── Bonds ──────────────────────────────────────────────────────────

    static func snapshotBonds(from context: NSManagedObjectContext) throws -> [BondCodable] {
        let req: NSFetchRequest<BondEntity> = BondEntity.fetchRequest()
        let bonds = try context.fetch(req)

        let codables = bonds.map { bond in
            let flows = (BondTermsStore.isReady(bond) ? bond.cashFlowsArray : []).map {
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
                wkn: bond.wkn,
                cashFlows: flows
            )
        }

        return codables
    }

    // ─── ETFs ───────────────────────────────────────────────────────────

    private static func snapshotETFs(from context: NSManagedObjectContext) throws -> [ETFEntityCodable] {
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

        return codables
    }
}
