import CoreData

// Purchase staging runs on the operation context; the caller saves once.
enum ETFPurchase {
    static func normalizedISIN(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let tokens = trimmed.split(whereSeparator: { $0.isWhitespace })
        if let first = tokens.first, first.count == 12, tokens.count > 1,
           tokens.allSatisfy({ $0 == first }), first.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) {
            return String(first)
        }
        return trimmed
    }
    static func validate(price: Double, shares: Int32) throws {
        guard price.isFinite, price > 0, shares > 0 else {
            throw PortfolioError("Enter a positive purchase price and number of shares.")
        }
    }
    static func acceptsHeader(requestedISIN: String, currentISIN: String,
                              isNewMode: Bool, requestedID: UUID, activeID: UUID?) -> Bool {
        isNewMode && requestedID == activeID
            && normalizedISIN(requestedISIN) == normalizedISIN(currentISIN)
    }
    static func stage(isin: String, header: InstrumentHeaderScraper.ETFInstrumentHeader?,
                      existingID: NSManagedObjectID?, date: Date, price: Double,
                      shares: Int32, context: NSManagedObjectContext) throws {
        try validate(price: price, shares: shares)
        let etf: ETFEntity
        if let existingID {
            guard let existing = try context.existingObject(with: existingID) as? ETFEntity else {
                throw PortfolioError("The selected ETF no longer exists.")
            }
            try HistoricalDataRecorder.validateETFTransactionDate(isin: existing.isin, date: date, context: context)
            etf = existing
        } else {
            let normalized = normalizedISIN(isin)
            guard !normalized.isEmpty, let header, header.price.isFinite, header.price > 0 else {
                throw PortfolioError("Fetch valid instrument data before saving.")
            }
            try HistoricalDataRecorder.validateETFTransactionDate(isin: normalized, date: date, context: context)
            let matches = try context.fetch(ETFEntity.fetchRequest()).filter {
                normalizedISIN($0.isin) == normalized
            }
            guard matches.count <= 1 else {
                throw PortfolioError("Multiple ETFs match this ISIN. Select the intended existing ETF.")
            }
            if let existing = matches.first {
                etf = existing
            } else {
                etf = ETFEntity(context: context)
                etf.id = UUID(); etf.isin = normalized; etf.etfName = header.name
                etf.wkn = header.wkn; etf.issuer = ""; etf.lastPrice = header.price
            }
        }
        let holding = ETFHoldings(context: context)
        holding.holdingtoetf = etf; holding.acquisitionDate = date
        holding.acquisitionPrice = price; holding.numberOfShares = shares
        try HistoricalDataRecorder.recordETFAcquisition(holding: holding, context: context)
    }
}
