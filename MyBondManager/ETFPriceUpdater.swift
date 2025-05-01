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

/// A small service that will iterate over every ETFEntity in the given
/// context, scrape its current price, update lastPrice, and append
/// a new ETFPrice record with timestamp (date+time).
@MainActor
public class ETFPriceUpdater {
    private let context: NSManagedObjectContext
    private let scraper: InstrumentHeaderScraper

    /// - Parameters:
    ///   - context: the NSManagedObjectContext you want to update (viewContext, backgroundContext, etc.)
    ///   - scraper: your async/await scraper; defaults to a new instance.
    public init(context: NSManagedObjectContext,
                scraper: InstrumentHeaderScraper = InstrumentHeaderScraper()) {
        self.context = context
        self.scraper = scraper
    }

    /// Scrape and record the latest price for every ETF in Core Data.
    /// Safe to call multiple times; existing history is never overwritten.
    /// Throws an error if refreshing prices fails for one or more ETFs.
    public func refreshAllPrices() async throws {
        // 1) Fetch all ETFs
        let request: NSFetchRequest<ETFEntity> = ETFEntity.fetchRequest()
        let etfs = try context.fetch(request)

        var individualErrors: [String: Error] = [:]

        for etf in etfs {
            do {
                // 2) Scrape price
                let price = try await scraper.fetchPrice(isin: etf.isin)
                let now   = Date() // full date + time

                // 3) Update model
                etf.lastPrice = price

                let historyEntry = ETFPrice(context: context)
                historyEntry.datePrice     = now
                historyEntry.price         = price
                historyEntry.etfPriceHistory = etf

            } catch {
                // Collect errors for each ETF failure
                individualErrors[etf.isin] = error
                print("⚠️ ETFPriceUpdater: failed for \(etf.isin): \(error)")
            }
        }

        // 4) Save once at the end
        if context.hasChanges {
            try context.save()
        }

        // 5) Throw an error if any individual refresh failed
        if !individualErrors.isEmpty {
            throw ETFPriceUpdaterError.failedToRefreshOneOrMore(errors: individualErrors)
        }
    }
}
