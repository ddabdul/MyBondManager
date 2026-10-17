import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class ETFPurchaseTests: XCTestCase {
    func testRepeatedClipboardISINLinesResolveToOneInstrumentWithoutChoosingBetweenDifferentCodes() {
        XCTAssertEqual(ETFPurchase.normalizedISIN(" eu000a2scak5\r\nEU000A2SCAK5 "), "EU000A2SCAK5")
        XCTAssertEqual(ETFPurchase.normalizedISIN("FR001400P1Y4\nFR001400P1Y4"), "FR001400P1Y4")
        XCTAssertNotEqual(ETFPurchase.normalizedISIN("EU000A2SCAK5\nFR001400P1Y4"), "EU000A2SCAK5")
        XCTAssertNotEqual(ETFPurchase.normalizedISIN("EU000A2SCAK5\nFR001400P1Y4"), "FR001400P1Y4")
    }
    func testRejectsInvalidValuesBeforeInsertion() throws {
        for price in [0.0, -1, Double.nan, Double.infinity] {
            XCTAssertThrowsError(try ETFPurchase.validate(price: price, shares: 1))
        }
        XCTAssertThrowsError(try ETFPurchase.validate(price: 90, shares: 0))
        XCTAssertThrowsError(try ETFPurchase.validate(price: 90, shares: -1))
    }
    func testLegacyISINReuseDoesNotOverwriteExistingQuote() throws {
        let container = try TestPortfolio.make()
        let holding = TestPortfolio.holding(in: container.viewContext)
        let etf = holding.holdingtoetf
        etf.isin = " de0000000002 "; etf.lastPrice = 80
        let header = InstrumentHeaderScraper.ETFInstrumentHeader(name: "A", wkn: "A", price: 500,
            close: nil, changePercent: nil, changeAbsolute: nil, instrumentType: nil, currency: "EUR")
        try ETFPurchase.stage(isin: "DE0000000002", header: header, existingID: nil,
            date: Date(), price: 90, shares: 1, context: container.viewContext)
        XCTAssertEqual(try container.viewContext.count(for: ETFEntity.fetchRequest()), 1)
        XCTAssertEqual(etf.lastPrice, 80)
        XCTAssertEqual(etf.isin, " de0000000002 ")
    }
    func testObsoleteResponseIsRejected() {
        let request = UUID()
        XCTAssertFalse(ETFPurchase.acceptsHeader(requestedISIN: "A", currentISIN: "B",
            isNewMode: true, requestedID: request, activeID: request))
        XCTAssertFalse(ETFPurchase.acceptsHeader(requestedISIN: "A", currentISIN: "A",
            isNewMode: false, requestedID: request, activeID: request))
        XCTAssertFalse(ETFPurchase.acceptsHeader(requestedISIN: "A", currentISIN: "A",
            isNewMode: true, requestedID: request, activeID: UUID()))
    }
    func testAmbiguousLegacyISINLeavesContextUnchanged() throws {
        let container = try TestPortfolio.make()
        let first = TestPortfolio.holding(in: container.viewContext)
        first.holdingtoetf.isin = " de0000000002 "
        _ = TestPortfolio.holding(in: container.viewContext)
        try container.viewContext.save()
        let header = InstrumentHeaderScraper.ETFInstrumentHeader(name: "A", wkn: "A", price: 500,
            close: nil, changePercent: nil, changeAbsolute: nil, instrumentType: nil, currency: "EUR")
        XCTAssertThrowsError(try ETFPurchase.stage(isin: "DE0000000002", header: header,
            existingID: nil, date: Date(), price: 90, shares: 1, context: container.viewContext))
        XCTAssertFalse(container.viewContext.hasChanges)
    }

}
