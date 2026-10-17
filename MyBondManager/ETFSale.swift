import CoreData

enum ETFSale {
    static func stage(etf: ETFEntity, shares: Int32, executionPrice: Double,
                      date: Date, context: NSManagedObjectContext) throws {
        guard shares > 0, executionPrice.isFinite, executionPrice > 0, date <= Date() else {
            throw PortfolioError("Enter positive shares, a valid execution price and a sale date no later than today.")
        }
        try HistoricalDataRecorder.validateETFTransactionDate(isin: etf.isin, date: date, context: context)
        let lots = (etf.etftoholding as? Set<ETFHoldings> ?? []).sorted {
            if $0.acquisitionDate != $1.acquisitionDate { return $0.acquisitionDate < $1.acquisitionDate }
            return $0.objectID.uriRepresentation().absoluteString < $1.objectID.uriRepresentation().absoluteString
        }
        guard lots.allSatisfy({ $0.numberOfShares > 0 && $0.acquisitionPrice.isFinite && $0.acquisitionPrice > 0 }) else {
            throw PortfolioError("This ETF has an invalid legacy holding. Correct it before selling.")
        }
        let saleDay = Calendar.current.startOfDay(for: date)
        let eligible = lots.filter { Calendar.current.startOfDay(for: $0.acquisitionDate) <= saleDay }
        guard eligible.reduce(Int64(0), { $0 + Int64($1.numberOfShares) }) >= Int64(shares) else {
            throw PortfolioError("Not enough shares were owned on the sale date.")
        }
        var remaining = shares
        for lot in eligible where remaining > 0 {
            let sold = min(remaining, lot.numberOfShares)
            try HistoricalDataRecorder.recordETFSale(holding: lot, soldShares: Int(sold),
                pricePerShare: executionPrice, date: date, context: context)
            remaining -= sold
            if sold == lot.numberOfShares { context.delete(lot) }
            else { lot.numberOfShares -= sold }
        }
    }
}
