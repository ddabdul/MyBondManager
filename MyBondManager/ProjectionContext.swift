import Foundation

struct FloatingCalculationWindow: Equatable, Sendable {
    let acquisitionDay: MarketDay
    let paymentFrom: MarketDay
}

struct ProjectionContext: Codable, Equatable, Sendable {
    let valuationDay: MarketDay
    let marketData: MarketDataSnapshot

    func validate() throws {
        try MarketDataStore.validate(marketData)
        guard marketData.payload.quotes.quoteDay <= valuationDay,
              marketData.payload.historicalFixings.allSatisfy({ $0.day <= valuationDay }) else {
            throw MarketDataError("Market quotes and published fixings must not be after the frozen valuation day.")
        }
    }
}
