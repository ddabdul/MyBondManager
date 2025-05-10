//
//  ETFPriceUpdater.swift
//  MyBondManager
//
//  Created by Olivier on 01/05/2025.
//

import Foundation
import CoreData

public enum ETFPriceUpdaterError: Error {
    case failedToRefreshOneOrMore(errors: [String: Error])
    case genericError(Error)
}

@MainActor
public class ETFPriceUpdater {
    private let context: NSManagedObjectContext
    private let scraper: InstrumentHeaderScraper
    private let calendar = Calendar.current

    public init(context: NSManagedObjectContext,
                scraper: InstrumentHeaderScraper = InstrumentHeaderScraper()) {
        self.context = context
        self.scraper = scraper
    }

    public func refreshAllPrices() async throws {
        // 1) Fetch all ETFs
        let request: NSFetchRequest<ETFEntity> = ETFEntity.fetchRequest()
        let etfs = try context.fetch(request)

        var individualErrors: [String: Error] = [:]

        // Precompute today’s boundaries
        let now       = Date()
        let startOfDay = calendar.startOfDay(for: now)
        guard let nextDay = calendar.date(byAdding: .day, value: 1, to: startOfDay)
        else { throw ETFPriceUpdaterError.genericError(NSError()) }

        for etf in etfs {
            do {
                // 2) Scrape the latest price
                let newPrice = try await scraper.fetchPrice(isin: etf.isin)

                // 3) Look for any existing entries for “today”
                let histReq: NSFetchRequest<ETFPrice> = ETFPrice.fetchRequest()
                histReq.predicate = NSPredicate(format:
                    "etfPriceHistory == %@ AND datePrice >= %@ AND datePrice < %@",
                    etf,
                    startOfDay as NSDate,
                    nextDay as NSDate
                )
                let existing = try context.fetch(histReq)

                if existing.isEmpty {
                    // No entry yet: create one
                    let entry = ETFPrice(context: context)
                    entry.etfPriceHistory = etf
                    entry.datePrice        = now
                    entry.price            = newPrice
                } else {
                    // We already have 1+ entries: average them all
                    let totalOld = existing.reduce(0) { $0 + $1.price }
                    let countOld = Double(existing.count)
                    let average  = (totalOld + newPrice) / (countOld + 1)

                    // Keep the first, delete the rest
                    let keeper = existing[0]
                    keeper.price     = average
                    keeper.datePrice = startOfDay    // normalize to day

                    for dup in existing.dropFirst() {
                        context.delete(dup)
                    }
                }

                // Also update the “lastPrice” on the ETF itself
                etf.lastPrice = newPrice

            } catch {
                individualErrors[etf.isin] = error
                print("⚠️ ETFPriceUpdater failed for \(etf.isin): \(error)")
            }
        }

        // 4) Save once
        if context.hasChanges {
            do {
                try context.save()
            } catch {
                throw ETFPriceUpdaterError.genericError(error)
            }
        }

        // 5) Bubble up any per-ETF errors
        if !individualErrors.isEmpty {
            throw ETFPriceUpdaterError.failedToRefreshOneOrMore(errors: individualErrors)
        }
    }
}
