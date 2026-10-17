import Foundation
import CoreData
import Combine

public enum ETFPriceUpdaterError: LocalizedError {
    case failedToRefreshOneOrMore(errors: [String: Error])
    case genericError(Error)
    public var errorDescription: String? {
        switch self {
        case .failedToRefreshOneOrMore(let errors):
            return errors.keys.sorted().map { "\($0): \(errors[$0]!.localizedDescription)" }.joined(separator: "\n")
        case .genericError(let error): return "Could not save refreshed prices: \(error.localizedDescription)"
        }
    }
}

@MainActor
public class ETFPriceUpdater: ObservableObject {
    @Published public private(set) var isRefreshing = false
    private let container: NSPersistentContainer
    private let fetchPrice: (String) async throws -> Double
    private let now: () -> Date
    private let calendar = Calendar.current

    public init(container: NSPersistentContainer,
                scraper: InstrumentHeaderScraper = InstrumentHeaderScraper(),
                fetchPrice: ((String) async throws -> Double)? = nil,
                now: @escaping () -> Date = Date.init) {
        self.container = container
        self.fetchPrice = fetchPrice ?? { try await scraper.fetchPrice(isin: $0) }
        self.now = now
    }

    private struct Observation {
        let id: NSManagedObjectID
        let isin: String
        let price: Double
        let date: Date
    }

    public func refreshAllPrices() async throws {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let viewContext = container.viewContext
        let instruments = try await viewContext.perform {
            try viewContext.fetch(ETFEntity.fetchRequest()).map {
                ($0.objectID, ETFPurchase.normalizedISIN($0.isin))
            }
        }
        var observations: [Observation] = []
        var errors: [String: Error] = [:]
        for (id, isin) in instruments {
            do {
                let price = try await fetchPrice(isin)
                guard price.isFinite, price > 0 else { throw PortfolioError("Invalid quote returned.") }
                observations.append(Observation(id: id, isin: isin, price: price, date: now()))
            } catch { errors[isin] = error }
        }
        let collected = observations
        let calendar = self.calendar
        do {
            let changed = try await PortfolioTransaction.run(in: container) { context in
                var changed: [String: Error] = [:]
                for quote in collected {
                    let request = ETFEntity.fetchRequest()
                    request.predicate = NSPredicate(format: "SELF == %@", quote.id)
                    guard let etf = try context.fetch(request).first,
                          ETFPurchase.normalizedISIN(etf.isin) == quote.isin else {
                        changed[quote.isin] = PortfolioError("Instrument changed during refresh; refresh again.")
                        continue
                    }
                    let start = calendar.startOfDay(for: quote.date)
                    guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                        throw PortfolioError("Could not determine quote day.")
                    }
                    let historyRequest = ETFPrice.fetchRequest()
                    historyRequest.predicate = NSPredicate(format:
                        "etfPriceHistory == %@ AND datePrice >= %@ AND datePrice < %@",
                        etf, start as NSDate, end as NSDate)
                    let existing = try context.fetch(historyRequest)
                    let keeper = existing.first ?? ETFPrice(context: context)
                    keeper.etfPriceHistory = etf
                    keeper.datePrice = quote.date; keeper.price = quote.price
                    existing.dropFirst().forEach(context.delete)
                    etf.lastPrice = quote.price
                }
                return changed
            }
            errors.merge(changed) { _, new in new }
        } catch { throw ETFPriceUpdaterError.genericError(error) }
        if !errors.isEmpty { throw ETFPriceUpdaterError.failedToRefreshOneOrMore(errors: errors) }
    }
}
