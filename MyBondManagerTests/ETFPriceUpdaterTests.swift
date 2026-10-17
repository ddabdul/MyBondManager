import XCTest
import CoreData
@testable import MyBondManager

private final class QuoteScraper: InstrumentHeaderScraper {
    var quotes = [100.0, 110.0, 120.0]
    override func fetchPrice(isin: String) async throws -> Double { quotes.removeFirst() }
}
@MainActor
final class ETFPriceUpdaterTests: XCTestCase {
    func testDailyRecordKeepsLatestQuote() async throws {
        let container = try TestPortfolio.make()
        let holding = TestPortfolio.holding(in: container.viewContext)
        try container.viewContext.save()
        let updater = ETFPriceUpdater(container: container, scraper: QuoteScraper())
        for _ in 0..<3 { try await updater.refreshAllPrices() }
        let reader = container.newBackgroundContext()
        let records = try await reader.perform { try reader.fetch(ETFPrice.fetchRequest()).map { $0.price } }
        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first, 120)
        let etfID = holding.holdingtoetf.objectID
        let last = try await reader.perform { (try reader.existingObject(with: etfID) as! ETFEntity).lastPrice }
        XCTAssertEqual(last, 120)
    }
    func testChangedInstrumentDuringFetchKeepsImportedQuote() async throws {
        let container = try TestPortfolio.make()
        let holding = TestPortfolio.holding(in: container.viewContext)
        try container.viewContext.save()
        let original = try ExportManager.snapshot(from: container.viewContext)
        let old = try XCTUnwrap(original.etfs.first)
        let replacement = ETFEntityCodable(id: old.id, etfName: old.etfName, isin: "DE0000000003",
            issuer: old.issuer, wkn: old.wkn, lastPrice: 80,
            priceHistory: [], holdings: old.holdings)
        let updater = ETFPriceUpdater(container: container, fetchPrice: { _ in
            try await ImportManager().apply(PositionsPayload(bonds: [], etfs: [replacement]), into: container)
            return 500
        })
        do { try await updater.refreshAllPrices(); XCTFail("Expected identity change error") } catch {}
        let reader = container.newBackgroundContext()
        let values = try await reader.perform {
            let etf = try XCTUnwrap(reader.fetch(ETFEntity.fetchRequest()).first)
            return (etf.lastPrice, try reader.count(for: ETFPrice.fetchRequest()))
        }
        XCTAssertEqual(values.0, 80); XCTAssertEqual(values.1, 0)
    }
    func testOverlappingRefreshStartsOnlyOneFetch() async throws {
        let container = try TestPortfolio.make()
        _ = TestPortfolio.holding(in: container.viewContext)
        try container.viewContext.save()
        let started = expectation(description: "fetch suspended")
        var resume: CheckedContinuation<Double, Never>?
        var fetches = 0
        let updater = ETFPriceUpdater(container: container, fetchPrice: { _ in
            fetches += 1
            return await withCheckedContinuation { continuation in
                resume = continuation; started.fulfill()
            }
        })
        let first = Task { try await updater.refreshAllPrices() }
        await fulfillment(of: [started], timeout: 5)
        try await updater.refreshAllPrices()
        XCTAssertTrue(updater.isRefreshing)
        XCTAssertEqual(fetches, 1)
        resume?.resume(returning: 120)
        try await first.value
        XCTAssertFalse(updater.isRefreshing)
    }
    func testInvalidQuoteKeepsLastGoodPriceAndUnrelatedDraft() async throws {
        let container = try TestPortfolio.make()
        let holding = TestPortfolio.holding(in: container.viewContext)
        try container.viewContext.save()
        holding.holdingtoetf.etfName = "Unrelated draft"
        let updater = ETFPriceUpdater(container: container, fetchPrice: { _ in Double.nan })
        do { try await updater.refreshAllPrices(); XCTFail("Expected invalid quote") } catch {}
        XCTAssertEqual(holding.holdingtoetf.etfName, "Unrelated draft")
        let reader = container.newBackgroundContext()
        let result = try await reader.perform {
            let etf = try XCTUnwrap(reader.fetch(ETFEntity.fetchRequest()).first)
            return (etf.etfName, etf.lastPrice)
        }
        XCTAssertEqual(result.0, "ETF fixture"); XCTAssertEqual(result.1, 100)
    }

    func testSuccessfulQuoteMergesIntoLoadedETF() async throws {
        let container = try TestPortfolio.make()
        let holding = TestPortfolio.holding(in: container.viewContext)
        try container.viewContext.save()
        let etf = holding.holdingtoetf
        XCTAssertEqual(etf.lastPrice, 100)
        let merged = expectation(description: "loaded quote updated")
        merged.assertForOverFulfill = false
        let observer = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextObjectsDidChange,
            object: container.viewContext, queue: .main) { _ in
                if etf.lastPrice == 120 { merged.fulfill() }
            }
        defer { NotificationCenter.default.removeObserver(observer) }
        try await ETFPriceUpdater(container: container, fetchPrice: { _ in 120 }).refreshAllPrices()
        await fulfillment(of: [merged], timeout: 5)
        XCTAssertEqual(etf.lastPrice, 120)
    }
    func testDeletedInstrumentIsNotResurrectedAfterFetch() async throws {
        let container = try TestPortfolio.make()
        _ = TestPortfolio.holding(in: container.viewContext)
        try container.viewContext.save()
        let updater = ETFPriceUpdater(container: container, fetchPrice: { _ in
            try await ImportManager().apply(PositionsPayload(bonds: [], etfs: []), into: container)
            return 500
        })
        do { try await updater.refreshAllPrices(); XCTFail("Expected deleted instrument error") } catch {}
        let reader = container.newBackgroundContext()
        let counts = try await reader.perform {
            (try reader.count(for: ETFEntity.fetchRequest()), try reader.count(for: ETFPrice.fetchRequest()))
        }
        XCTAssertEqual(counts.0, 0); XCTAssertEqual(counts.1, 0)
    }
    func testDailyDuplicatesCollapseToLatestQuote() async throws {
        let container = try TestPortfolio.make()
        let holding = TestPortfolio.holding(in: container.viewContext)
        let date = TestPortfolio.date("2026-01-01T12:00:00Z")
        for value in [90.0, 110.0] {
            let entry = ETFPrice(context: container.viewContext)
            entry.etfPriceHistory = holding.holdingtoetf; entry.datePrice = date; entry.price = value
        }
        try container.viewContext.save()
        let updater = ETFPriceUpdater(container: container, fetchPrice: { _ in 120 }, now: { date })
        try await updater.refreshAllPrices()
        let reader = container.newBackgroundContext()
        let prices = try await reader.perform { try reader.fetch(ETFPrice.fetchRequest()).map { $0.price } }
        XCTAssertEqual(prices, [120])
    }
    func testMidnightObservationsUseDifferentLocalDays() async throws {
        let container = try TestPortfolio.make()
        _ = TestPortfolio.holding(in: container.viewContext)
        try container.viewContext.save()
        var dates = [Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 1, hour: 23, minute: 59))!,
                     Calendar.current.date(from: DateComponents(year: 2026, month: 1, day: 2, hour: 0, minute: 1))!]
        var quotes = [110.0, 120.0]
        let updater = ETFPriceUpdater(container: container, fetchPrice: { _ in quotes.removeFirst() },
                                      now: { dates.removeFirst() })
        try await updater.refreshAllPrices(); try await updater.refreshAllPrices()
        let reader = container.newBackgroundContext()
        let prices = try await reader.perform { try reader.fetch(ETFPrice.fetchRequest()).map { $0.price }.sorted() }
        XCTAssertEqual(prices, [110, 120])
    }
    func testFailedPriceSaveRollsBackRefreshWithoutSavingDraft() async throws {
        let container = try TestPortfolio.make()
        let holding = TestPortfolio.holding(in: container.viewContext)
        try container.viewContext.save()
        holding.holdingtoetf.etfName = "Unrelated draft"
        let observer = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextWillSave,
            object: nil, queue: nil) { notification in
                guard let context = notification.object as? NSManagedObjectContext,
                      context !== container.viewContext,
                      context.persistentStoreCoordinator === container.persistentStoreCoordinator else { return }
                for object in context.insertedObjects where object.entity.name == "ETFPrice" {
                    object.setValue(nil, forKey: "datePrice")
                }
            }
        defer { NotificationCenter.default.removeObserver(observer) }
        let updater = ETFPriceUpdater(container: container, fetchPrice: { _ in 120 })
        do { try await updater.refreshAllPrices(); XCTFail("Expected save failure") } catch {}
        XCTAssertEqual(holding.holdingtoetf.etfName, "Unrelated draft")
        let reader = container.newBackgroundContext()
        let result = try await reader.perform {
            let etf = try XCTUnwrap(reader.fetch(ETFEntity.fetchRequest()).first)
            return (etf.etfName, etf.lastPrice, try reader.count(for: ETFPrice.fetchRequest()))
        }
        XCTAssertEqual(result.0, "ETF fixture"); XCTAssertEqual(result.1, 100); XCTAssertEqual(result.2, 0)
    }

}
