import Foundation

struct MarketDataClient {
    private let session: URLSession
    private let sources: MarketDataSources
    private static let maximumBytes = 10 * 1024 * 1024
    private static let requiredYears = [1, 2, 3, 5, 7, 10, 15, 30]

    init(session: URLSession = .shared, sources: MarketDataSources) {
        self.session = session
        self.sources = sources
    }

    static func parseRates(_ bytes: Data) throws -> ParsedPublicRates {
        try checkSize(bytes)
        let root = try object(bytes)
        try keys(root, allowed: ["Rates", "CurrentDate", "PreviousDayDate", "PreviousMonthDate", "PreviousYearDate", "Updated"], field: "public rates")
        guard let rawDay = root["PreviousDayDate"] as? String,
              let rows = root["Rates"] as? [[String: Any]], !rows.isEmpty else {
            throw MarketDataError("Public rates require PreviousDayDate and a nonempty Rates list.")
        }
        let day = try MarketDay(rawDay)
        var rates: [Int: Double] = [:]
        for (position, row) in rows.enumerated() {
            guard let months = integer(row["LengthInMonths"]), months > 0,
                  let raw = row["PreviousDay"] as? String, let percent = Double(raw), percent.isFinite else {
                throw MarketDataError("Rates[\(position)] requires integer LengthInMonths and finite PreviousDay percent string.")
            }
            if let rowDay = row["PreviousDayDate"] {
                guard let value = rowDay as? String, try MarketDay(value) == day else {
                    throw MarketDataError("Rates[\(position)] PreviousDayDate differs from the feed quote date.")
                }
            }
            guard rates[months] == nil else { throw MarketDataError("Duplicate public quote pillar \(months) months.") }
            rates[months] = percent / 100
        }
        return ParsedPublicRates(quoteDay: day, decimalRatesByMonths: rates)
    }

    static func parseFixings(_ bytes: Data, pricingDay: MarketDay) throws -> [PublishedFixing] {
        try checkSize(bytes)
        // Reject DTDs entirely, in addition to disabling external entity resolution.
        guard let xml = String(data: bytes, encoding: .utf8), !xml.contains("\u{0}") else {
            throw MarketDataError("Historical XML must use UTF-8 encoding without a DTD.")
        }
        guard !xml.localizedCaseInsensitiveContains("<!DOCTYPE"), !xml.localizedCaseInsensitiveContains("<!ENTITY") else {
            throw MarketDataError("Historical XML must not contain DTDs or entities.")
        }
        let delegate = FixingParser(pricingDay: pricingDay)
        let parser = XMLParser(data: bytes)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        guard parser.parse(), delegate.failure == nil else {
            throw delegate.failure ?? MarketDataError("Malformed historical XML: \(parser.parserError?.localizedDescription ?? "invalid document").")
        }
        guard !delegate.rates.isEmpty else { throw MarketDataError("Historical XML contains no published observations.") }
        return delegate.rates.sorted { $0.key < $1.key }.map { PublishedFixing(day: $0.key, rate: $0.value) }
    }

    static func decodeImport(_ bytes: Data, pricingDay: MarketDay) throws -> MarketDataPayload {
        try checkSize(bytes)
        let root = try object(bytes)
        try keys(root, allowed: ["formatVersion", "method", "sourceName", "quotes", "historicalFixings"], field: "payload")
        guard let quotes = root["quotes"] as? [String: Any],
              let swaps = quotes["swaps"] as? [[String: Any]],
              let fixings = root["historicalFixings"] as? [[String: Any]] else {
            throw MarketDataError("Import requires quotes, swaps and historicalFixings objects.")
        }
        try keys(quotes, allowed: ["indexTenorMonths", "quoteDay", "depositRate", "swaps"], field: "quotes")
        for row in swaps { try keys(row, allowed: ["years", "rate"], field: "quotes.swaps") }
        for row in fixings { try keys(row, allowed: ["day", "rate"], field: "historicalFixings") }
        let payload: MarketDataPayload
        do { payload = try JSONDecoder().decode(MarketDataPayload.self, from: bytes) }
        catch let error as DecodingError {
            let context: DecodingError.Context
            switch error {
            case .typeMismatch(_, let value), .valueNotFound(_, let value), .keyNotFound(_, let value), .dataCorrupted(let value): context = value
            @unknown default: throw error
            }
            let field = context.codingPath.map(\.stringValue).joined(separator: ".")
            throw MarketDataError("Invalid decimal market input at \(field.isEmpty ? "payload" : field): \(context.debugDescription)")
        } catch { throw MarketDataError("Malformed decimal market input: \(error.localizedDescription)") }
        return try validated(payload, pricingDay: pricingDay)
    }

    /// Shared normalized contract for fetched data, imports and catalogue publication.
    static func validated(_ payload: MarketDataPayload, pricingDay: MarketDay) throws -> MarketDataPayload {
        guard payload.formatVersion == 1 else { throw MarketDataError("Unsupported market formatVersion \(payload.formatVersion).") }
        guard payload.method == "euribor-singlecurve-v1" else { throw MarketDataError("Unknown market bootstrap method: \(payload.method).") }
        guard !payload.sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MarketDataError("sourceName must not be empty.")
        }
        let quotes = payload.quotes
        guard [1, 3, 6, 12].contains(quotes.indexTenorMonths) else { throw MarketDataError("Unknown indexTenorMonths \(quotes.indexTenorMonths).") }
        guard quotes.quoteDay <= pricingDay else { throw MarketDataError("Future quote date \(quotes.quoteDay.rawValue) is after pricing day \(pricingDay.rawValue).") }
        try decimal(quotes.depositRate, field: "quotes.depositRate")
        var seen = Set<Int>()
        for swap in quotes.swaps {
            guard requiredYears.contains(swap.years), seen.insert(swap.years).inserted else {
                throw MarketDataError("Invalid or duplicate swap pillar \(swap.years) years.")
            }
            try decimal(swap.rate, field: "quotes.swaps[\(swap.years)].rate")
        }
        guard seen == Set(requiredYears) else { throw MarketDataError("Missing required swap years: \(requiredYears.filter { !seen.contains($0) }).") }
        var days = Set<MarketDay>()
        for fixing in payload.historicalFixings {
            guard fixing.day <= pricingDay else { throw MarketDataError("Future historical fixing date \(fixing.day.rawValue).") }
            guard days.insert(fixing.day).inserted else { throw MarketDataError("Duplicate historical fixing date \(fixing.day.rawValue).") }
            try decimal(fixing.rate, field: "historicalFixings[\(fixing.day.rawValue)].rate")
        }
        return MarketDataPayload(formatVersion: payload.formatVersion, method: payload.method, sourceName: payload.sourceName,
            quotes: CurveMarketQuotes(indexTenorMonths: quotes.indexTenorMonths, quoteDay: quotes.quoteDay,
                depositRate: quotes.depositRate, swaps: quotes.swaps.sorted { $0.years < $1.years }),
            historicalFixings: payload.historicalFixings.sorted { $0.day < $1.day })
    }

    func fetch(indexTenorMonths: Int, pricingDay: MarketDay) async throws -> MarketDataPayload {
        guard [3, 6].contains(indexTenorMonths) else {
            throw MarketDataError("No automatic quote source for \(indexTenorMonths)M; import matching quotes.")
        }
        guard let swapURL = sources.swapQuotesURLs[indexTenorMonths],
              let historyURL = sources.historicalFixingURLs[indexTenorMonths] else {
            throw MarketDataError("Missing source endpoints for \(indexTenorMonths)M.")
        }
        let deposit = try Self.parseRates(await download(sources.fixingQuotesURL, historical: false))
        let swaps = try Self.parseRates(await download(swapURL, historical: false))
        guard deposit.quoteDay == swaps.quoteDay else {
            throw MarketDataError("Quote date mismatch: deposits \(deposit.quoteDay.rawValue), swaps \(swaps.quoteDay.rawValue).")
        }
        guard let depositRate = deposit.decimalRatesByMonths[indexTenorMonths] else {
            throw MarketDataError("Missing deposit quote for \(indexTenorMonths)M.")
        }
        let swapQuotes = try Self.requiredYears.map { years -> SwapMarketQuote in
            guard let rate = swaps.decimalRatesByMonths[years * 12] else { throw MarketDataError("Missing required \(years)Y swap quote.") }
            return SwapMarketQuote(years: years, rate: rate)
        }
        let fixings = try Self.parseFixings(await download(historyURL, historical: true), pricingDay: pricingDay)
        return try Self.validated(MarketDataPayload(formatVersion: 1, method: "euribor-singlecurve-v1", sourceName: sources.sourceName,
            quotes: CurveMarketQuotes(indexTenorMonths: indexTenorMonths, quoteDay: deposit.quoteDay,
                depositRate: depositRate, swaps: swapQuotes), historicalFixings: fixings), pricingDay: pricingDay)
    }

    private func download(_ url: URL, historical: Bool) async throws -> Data {
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/137.0.0.0 Safari/537.36", forHTTPHeaderField: "User-Agent")
        request.setValue("en-US,en;q=0.9", forHTTPHeaderField: "Accept-Language")
        request.setValue(historical ? "application/vnd.sdmx.genericdata+xml;version=2.1" : "application/json", forHTTPHeaderField: "Accept")
        var origin = URLComponents(url: url, resolvingAgainstBaseURL: false)!
        origin.path = ""; origin.query = nil
        request.setValue(origin.string, forHTTPHeaderField: "Origin")
        request.setValue(origin.string! + "/", forHTTPHeaderField: "Referer")
        do {
            let (stream, response) = try await session.bytes(for: request, delegate: NoRedirects())
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                throw MarketDataError("Market source \(url.host ?? "") returned HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0); expected 200 without redirect.")
            }
            guard response.expectedContentLength <= Int64(Self.maximumBytes) else { throw MarketDataError("Market source response exceeds 10 MB.") }
            var bytes = Data()
            for try await byte in stream {
                guard bytes.count < Self.maximumBytes else { throw MarketDataError("Market source response exceeds 10 MB.") }
                bytes.append(byte)
            }
            return bytes
        } catch let error as URLError {
            if error.code == .timedOut { throw MarketDataError("Market source \(url.host ?? "") timed out after 15 seconds; retry or import dated inputs.") }
            throw MarketDataError("Market source \(url.host ?? "") network error: \(error.localizedDescription)")
        }
    }

    private static func checkSize(_ bytes: Data) throws {
        guard bytes.count <= maximumBytes else { throw MarketDataError("Market input exceeds 10 MB.") }
    }
    private static func object(_ bytes: Data) throws -> [String: Any] {
        do {
            guard let value = try JSONSerialization.jsonObject(with: bytes) as? [String: Any] else {
                throw MarketDataError("Market JSON must be an object.")
            }
            return value
        } catch let error as MarketDataError { throw error }
        catch { throw MarketDataError("Malformed market JSON: \(error.localizedDescription)") }
    }
    private static func integer(_ value: Any?) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              number.doubleValue.isFinite, number.doubleValue.rounded() == number.doubleValue,
              number.doubleValue > 0, number.doubleValue < Double(Int.max) else { return nil }
        return number.intValue
    }
    private static func decimal(_ rate: Double, field: String) throws {
        guard rate.isFinite, abs(rate) < 1 else {
            throw MarketDataError("\(field) must be a finite decimal rate with absolute value below 1; convert percent inputs before import.")
        }
    }
    private static func keys(_ value: [String: Any], allowed: Set<String>, field: String) throws {
        if let key = value.keys.sorted().first(where: { !allowed.contains($0) }) {
            throw MarketDataError("Unexpected field \(field).\(key); normalized rates use decimals.")
        }
    }
}

private final class NoRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(_ session: URLSession, task: URLSessionTask, willPerformHTTPRedirection response: HTTPURLResponse,
                    newRequest request: URLRequest, completionHandler: @escaping (URLRequest?) -> Void) {
        completionHandler(nil)
    }
}

private final class FixingParser: NSObject, XMLParserDelegate {
    let pricingDay: MarketDay
    var rates: [MarketDay: Double] = [:]
    var failure: Error?
    private var inObservation = false
    private var rawDay: String?
    private var rawRate: String?
    init(pricingDay: MarketDay) { self.pricingDay = pricingDay }
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?,
                qualifiedName qName: String?, attributes attributeDict: [String: String]) {
        if elementName == "Obs" {
            if inObservation { failure = MarketDataError("Nested historical Obs elements are invalid."); parser.abortParsing(); return }
            inObservation = true; rawDay = nil; rawRate = nil
        } else if inObservation, elementName == "ObsDimension" {
            guard rawDay == nil, let value = attributeDict["value"] else {
                failure = MarketDataError("Historical ObsDimension date is missing or duplicated."); parser.abortParsing(); return
            }
            rawDay = value
        } else if inObservation, elementName == "ObsValue" {
            guard rawRate == nil, let value = attributeDict["value"] else {
                failure = MarketDataError("Historical ObsValue is missing or duplicated."); parser.abortParsing(); return
            }
            rawRate = value
        }
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) {
        guard elementName == "Obs", inObservation else { return }
        inObservation = false
        do {
            guard let rawDay else { throw MarketDataError("Historical observation is missing ObsDimension date.") }
            let day = try MarketDay(rawDay)
            guard let rawRate else { return } // SDMX holidays have a date/status and no published value.
            guard day <= pricingDay else { throw MarketDataError("Future historical fixing date \(rawDay).") }
            guard let rate = Double(rawRate), rate.isFinite else { throw MarketDataError("Invalid historical ObsValue on \(rawDay).") }
            let decimal = rate / 100
            if let existing = rates[day], existing != decimal { throw MarketDataError("Conflicting duplicate historical date \(rawDay).") }
            rates[day] = decimal
        } catch { failure = error; parser.abortParsing() }
    }
}
