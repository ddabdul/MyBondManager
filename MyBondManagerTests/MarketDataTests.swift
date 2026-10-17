import XCTest
@testable import MyBondManager

final class MarketDataTests: XCTestCase {
    func testPublicRateUnitsAndDateArePreserved() throws {
        let parsed = try MarketDataClient.parseRates(Data(#"{"PreviousDayDate":"2026-10-08","Rates":[{"LengthInMonths":3,"PreviousDay":"2.642"}]}"#.utf8))
        XCTAssertEqual(parsed.quoteDay.rawValue, "2026-10-08")
        XCTAssertEqual(try XCTUnwrap(parsed.decimalRatesByMonths[3]), 0.02642, accuracy: 1e-12)
    }
    func testNegativeFixingIsNotFloored() throws {
        XCTAssertEqual(try MarketDataClient.parseRates(Data(#"{"PreviousDayDate":"2026-10-08","Rates":[{"LengthInMonths":3,"PreviousDay":"-0.5"}]}"#.utf8)).decimalRatesByMonths[3], -0.005)
    }
}

extension MarketDataTests {
    private func fixture(_ name: String) throws -> Data {
        let directory = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("Fixtures")
        return try Data(contentsOf: directory.appendingPathComponent(name))
    }
    func testCapturedPublicFixturesParse() throws {
        let rates = try MarketDataClient.parseRates(fixture("cf_eurlibor.json"))
        XCTAssertEqual(rates.decimalRatesByMonths[6], 0.02936)
        let fixings = try MarketDataClient.parseFixings(fixture("bundesbank_euribor3m.xml"), pricingDay: MarketDay("2026-10-08"))
        XCTAssertEqual(fixings.map(\.day.rawValue), ["2024-05-28", "2024-05-29", "2024-05-31", "2024-06-03"])
        XCTAssertEqual(fixings[0].rate, 0.02365, accuracy: 1e-12)
    }
    func testPublicParserRejectsInvalidDateDuplicateNonfiniteAndWrongTypes() {
        for body in [
            #"{"PreviousDayDate":"2026-02-30","Rates":[]}"#,
            #"{"PreviousDayDate":"2026-10-08","Rates":[{"LengthInMonths":3,"PreviousDay":"NaN"}]}"#,
            #"{"PreviousDayDate":"2026-10-08","Rates":[{"LengthInMonths":3,"PreviousDay":true}]}"#,
            #"{"PreviousDayDate":"2026-10-08","Rates":[{"LengthInMonths":3,"PreviousDay":"2"},{"LengthInMonths":3,"PreviousDay":"2"}]}"#,
            #"{"date":"2026-10-08","rates":[]}"#,
            #"{"units":"decimal","PreviousDayDate":"2026-10-08","Rates":[{"LengthInMonths":3,"PreviousDay":"2.642"}]}"#,
            #"{"PreviousDayDate":"2026-10-08","Rates":[{"LengthInMonths":true,"PreviousDay":"2"}]}"#,
            #"{"PreviousDayDate":"2026-10-08","Rates":[{"LengthInMonths":3,"PreviousDay":"2","PreviousDayDate":"2026-10-07"}]}"#
        ] { XCTAssertThrowsError(try MarketDataClient.parseRates(Data(body.utf8)), body) }
    }
    private func xml(_ observations: String) -> Data {
        Data("<GenericData><DataSet><Series>\(observations)</Series></DataSet></GenericData>".utf8)
    }
    func testXMLRejectsMalformedFutureMissingDatesAndConflictingDuplicates() throws {
        let day = try MarketDay("2026-10-08")
        for bytes in [Data("<broken".utf8), xml("<Obs><ObsValue value=\"2\"/></Obs>"),
            xml("<Obs><ObsDimension value=\"2026-10-09\"/><ObsValue value=\"2\"/></Obs>"),
            xml("<Obs><ObsDimension value=\"2026-10-08\"/><ObsValue value=\"NaN\"/></Obs>"),
            xml("<Obs><ObsDimension value=\"2026-10-08\"/><ObsValue value=\"2\"/></Obs><Obs><ObsDimension value=\"2026-10-08\"/><ObsValue value=\"3\"/></Obs>"),
            Data("<!DOCTYPE a [<!ENTITY ext SYSTEM \"file:///etc/passwd\">]><GenericData>&ext;</GenericData>".utf8)
        ] { XCTAssertThrowsError(try MarketDataClient.parseFixings(bytes, pricingDay: day)) }
    }
    func testXMLSortsAndPreservesNegativePublishedRates() throws {
        let values = try MarketDataClient.parseFixings(xml("<Obs><ObsDimension value=\"2026-10-08\"/><ObsValue value=\"2\"/></Obs><Obs><ObsDimension value=\"2026-10-07\"/><ObsValue value=\"-0.5\"/></Obs>"), pricingDay: MarketDay("2026-10-08"))
        XCTAssertEqual(values.first?.day.rawValue, "2026-10-07")
        XCTAssertEqual(values.first?.rate, -0.005)
    }
    func testNormalizedImportRoundTripsAndRejectsIncompleteOrAmbiguousInputs() throws {
        let original = try fixture("euribor3m-import.json")
        let day = try MarketDay("2026-10-08")
        let payload = try MarketDataClient.decodeImport(original, pricingDay: day)
        XCTAssertEqual(payload.quotes.depositRate, 0.02642)
        XCTAssertEqual(payload.quotes.swaps.first?.rate, 0.03037)
        XCTAssertEqual(try MarketDataClient.decodeImport(JSONEncoder().encode(payload), pricingDay: day), payload)
        let raw = try XCTUnwrap(String(data: original, encoding: .utf8))
        for (from, to) in [("\"formatVersion\": 1", "\"formatVersion\": 2"),
            ("\"indexTenorMonths\": 3", "\"indexTenorMonths\": 2"),
            ("\"rate\": 0.03037", "\"rate\": 3.037"),
            ("\"years\": 1,", "\"years\": 2,"),
            ("2026-10-08", "2026-10-09"),
            ("\"sourceName\":", "\"units\": \"percent\", \"sourceName\":")
        ] { XCTAssertThrowsError(try MarketDataClient.decodeImport(Data(raw.replacingOccurrences(of: from, with: to).utf8), pricingDay: day), from) }
    }
    func testConfigurationRejectsHTTPAndCredentials() throws {
        for url in ["http://example.org/rates", "https://user:password@example.org/rates"] {
            XCTAssertThrowsError(try MarketDataSources(fixingQuotesURL: URL(string: url)!, swapQuotesURLs: [:], historicalFixingURLs: [:]))
        }
    }
    func testFetchUsesTenorSpecificSwapAndRejectsMixedDates() async throws {
        for tenor in [3, 6] {
            let payload = try await client(swapBody: fixture(tenor == 3 ? "cf_euriborswap.json" : "cf_euribor6monthswap.json")).fetch(indexTenorMonths: tenor, pricingDay: MarketDay("2026-10-08"))
            XCTAssertEqual(payload.quotes.indexTenorMonths, tenor)
            XCTAssertEqual(payload.quotes.depositRate, tenor == 3 ? 0.02642 : 0.02936)
            XCTAssertEqual(payload.quotes.swaps.map(\.years), [1, 2, 3, 5, 7, 10, 15, 30])
            XCTAssertEqual(try XCTUnwrap(payload.quotes.swaps.first?.rate), tenor == 3 ? 0.03037 : 0.03172, accuracy: 1e-12)
        }
        let mixed = try fixture("cf_euriborswap.json")
        let changed = Data(String(decoding: mixed, as: UTF8.self).replacingOccurrences(of: "2026-10-08", with: "2026-10-07").utf8)
        do { _ = try await client(swapBody: changed).fetch(indexTenorMonths: 3, pricingDay: MarketDay("2026-10-08")); XCTFail("Mixed dates accepted") } catch { XCTAssertTrue(error.localizedDescription.contains("date")) }
    }
    func testFetchRejectsHTTPHTMLTimeoutMissingSwapsFutureAndManualOnly() async throws {
        for failure in ["redirect", "html", "timeout", "missing", "oversize", "xml", "future"] {
            do { _ = try await client(failure: failure).fetch(indexTenorMonths: 3, pricingDay: MarketDay("2026-10-08")); XCTFail("Accepted \(failure)") } catch { XCTAssertFalse(error.localizedDescription.isEmpty) }
        }
        do { _ = try await client().fetch(indexTenorMonths: 1, pricingDay: MarketDay("2026-10-08")); XCTFail("Substituted automatic curve") } catch { XCTAssertTrue(error.localizedDescription.contains("import")) }
    }
    private func client(swapBody: Data? = nil, failure: String = "") throws -> MarketDataClient {
        let deposit = try fixture("cf_eurlibor.json")
        let swaps = try swapBody ?? fixture("cf_euriborswap.json")
        let history = try fixture("bundesbank_euribor3m.xml")
        MarketDataURLProtocol.handler = { request in
            if failure == "timeout" { throw URLError(.timedOut) }
            let path = request.url!.path
            var data = path == "/deposit" ? deposit : (path == "/history" ? history : swaps)
            if failure == "html" { data = Data("<html>Login</html>".utf8) }
            if failure == "missing", path == "/swap" { data = Data(#"{"PreviousDayDate":"2026-10-08","Rates":[]}"#.utf8) }
            if failure == "oversize" { data = Data(repeating: 32, count: 10 * 1024 * 1024 + 1) }
            if failure == "xml", path == "/history" { data = Data("<broken".utf8) }
            if failure == "future" { data = Data(String(decoding: data, as: UTF8.self).replacingOccurrences(of: "2026-10-08", with: "2026-10-09").utf8) }
            return (failure == "redirect" ? 301 : 200, data)
        }
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MarketDataURLProtocol.self]
        let sources = try MarketDataSources(fixingQuotesURL: URL(string: "https://fixture.test/deposit")!, swapQuotesURLs: [3: URL(string: "https://fixture.test/swap")!, 6: URL(string: "https://fixture.test/swap")!], historicalFixingURLs: [3: URL(string: "https://fixture.test/history")!, 6: URL(string: "https://fixture.test/history")!])
        return MarketDataClient(session: URLSession(configuration: configuration), sources: sources)
    }
}

private final class MarketDataURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (Int, Data))?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        do {
            let (status, bytes) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: bytes)
            client?.urlProtocolDidFinishLoading(self)
        } catch { client?.urlProtocol(self, didFailWithError: error) }
    }
    override func stopLoading() {}
}


extension MarketDataTests {
    func testHistoricalParserRejectsUTF16DTDAndDuplicateDimension() throws {
        let day = try MarketDay("2026-10-08")
        let entity = "<?xml version=\"1.0\" encoding=\"UTF-16\"?><!DOCTYPE GenericData [<!ENTITY x \"value\">]><GenericData><Obs><ObsDimension value=\"2026-10-08\"/><ObsValue value=\"2\"/></Obs></GenericData>"
        XCTAssertThrowsError(try MarketDataClient.parseFixings(XCTUnwrap(entity.data(using: .utf16)), pricingDay: day))
        let ambiguous = Data("<GenericData><Obs><ObsDimension value=\"2026-10-07\"/><ObsDimension value=\"2026-10-08\"/><ObsValue value=\"2\"/></Obs></GenericData>".utf8)
        XCTAssertThrowsError(try MarketDataClient.parseFixings(ambiguous, pricingDay: day))
    }
    func testImportRejectsDuplicateHistoricalDaysAndNonDecimalTypes() throws {
        let bytes = try fixture("euribor3m-import.json")
        let day = try MarketDay("2026-10-08")
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        let rows = try XCTUnwrap(root["historicalFixings"] as? [[String: Any]])
        root["historicalFixings"] = rows + rows
        XCTAssertThrowsError(try MarketDataClient.decodeImport(JSONSerialization.data(withJSONObject: root), pricingDay: day))
        root["historicalFixings"] = [["day": "2026-10-08", "rate": "2.642%"]]
        XCTAssertThrowsError(try MarketDataClient.decodeImport(JSONSerialization.data(withJSONObject: root), pricingDay: day))
    }
    func testImportAllowsEmptyHistoricalFixingsForFutureOnlyProjection() throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("euribor3m-import.json")) as? [String: Any])
        root["historicalFixings"] = []
        let payload = try MarketDataClient.decodeImport(JSONSerialization.data(withJSONObject: root), pricingDay: MarketDay("2026-10-08"))
        XCTAssertTrue(payload.historicalFixings.isEmpty)
    }
    func testImportTypeErrorsIdentifyOffendingField() throws {
        var root = try XCTUnwrap(JSONSerialization.jsonObject(with: fixture("euribor3m-import.json")) as? [String: Any])
        root["historicalFixings"] = [["day": "2026-10-08", "rate": "2.642%"]]
        XCTAssertThrowsError(try MarketDataClient.decodeImport(JSONSerialization.data(withJSONObject: root), pricingDay: MarketDay("2026-10-08"))) { error in
            XCTAssertTrue(error.localizedDescription.contains("historicalFixings"))
            XCTAssertTrue(error.localizedDescription.contains("rate"))
        }
    }
    func testBundledSourceConfigurationLoadsHTTPSAndTenorFeeds() throws {
        let sources = try MarketDataSources.bundled()
        XCTAssertEqual(sources.fixingQuotesURL.scheme, "https")
        XCTAssertNotEqual(sources.swapQuotesURLs[3], sources.swapQuotesURLs[6])
        XCTAssertNil(sources.swapQuotesURLs[1])
        XCTAssertEqual(sources.historicalFixingURLs[12]?.lastPathComponent, "D.D0.EUR.MMKT.EURIBOR.M12.BID._Z")
    }
}
