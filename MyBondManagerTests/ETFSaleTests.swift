import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class ETFSaleTests: XCTestCase {
    func testEarlierSaleIsRejectedWithoutChangingRecordedGains() throws {
        let container = try TestPortfolio.make()
        let context = container.viewContext
        let first = TestPortfolio.holding(in: context, shares: 10, price: 80)
        let second = TestPortfolio.holding(in: context, shares: 10, price: 90, etf: first.holdingtoetf)
        second.acquisitionDate = TestPortfolio.date("2025-02-01T00:00:00Z")
        try context.save()
        try ETFSale.stage(etf: first.holdingtoetf, shares: 8, executionPrice: 100,
            date: TestPortfolio.date("2025-04-01T00:00:00Z"), context: context)
        try context.save()
        XCTAssertThrowsError(try ETFSale.stage(etf: first.holdingtoetf, shares: 8, executionPrice: 100,
            date: TestPortfolio.date("2025-03-01T00:00:00Z"), context: context))
        XCTAssertFalse(context.hasChanges)
        XCTAssertEqual(first.numberOfShares, 2)
        XCTAssertEqual(try context.fetch(HistoricalValuation.fetchRequest()).reduce(0) {
            $0 + $1.capitalGains.doubleValue
        }, 160)
    }

    func testAcquisitionBeforeRecordedSaleIsRejected() throws {
        let container = try TestPortfolio.make()
        let context = container.viewContext
        let lot = TestPortfolio.holding(in: context)
        try context.save()
        try ETFSale.stage(etf: lot.holdingtoetf, shares: 1, executionPrice: 100,
            date: TestPortfolio.date("2025-04-01T00:00:00Z"), context: context)
        try context.save()
        XCTAssertThrowsError(try ETFPurchase.stage(isin: "", header: nil,
            existingID: lot.holdingtoetf.objectID, date: TestPortfolio.date("2025-03-01T00:00:00Z"),
            price: 90, shares: 1, context: context))
        XCTAssertFalse(context.hasChanges)
    }

    func testFIFOUsesExecutionPriceAndStagesAllChanges() throws {
        let container = try TestPortfolio.make()
        let context = container.viewContext
        let first = TestPortfolio.holding(in: context, shares: 5, price: 80)
        let second = TestPortfolio.holding(in: context, shares: 10, price: 90, etf: first.holdingtoetf)
        second.acquisitionDate = TestPortfolio.date("2025-02-01T00:00:00Z")
        try context.save()
        let saleDate = TestPortfolio.date("2025-03-01T00:00:00Z")
        try ETFSale.stage(etf: first.holdingtoetf, shares: 8, executionPrice: 110,
                         date: saleDate, context: context)
        XCTAssertTrue(first.isDeleted); XCTAssertEqual(second.numberOfShares, 7)
        let history = try context.fetch(HistoricalValuation.fetchRequest())
        XCTAssertEqual(history.reduce(0) { $0 + $1.investedCapital.doubleValue }, -670)
        XCTAssertEqual(history.reduce(0) { $0 + $1.capitalGains.doubleValue }, 210)
        XCTAssertTrue(history.allSatisfy { $0.date == saleDate })
        XCTAssertTrue(context.hasChanges)
    }
    func testOversellDoesNotChangeLots() throws {
        let container = try TestPortfolio.make()
        let holding = TestPortfolio.holding(in: container.viewContext, shares: 5)
        try container.viewContext.save()
        XCTAssertThrowsError(try ETFSale.stage(etf: holding.holdingtoetf, shares: 6,
            executionPrice: 110, date: Date(), context: container.viewContext))
        XCTAssertEqual(holding.numberOfShares, 5)
        XCTAssertFalse(container.viewContext.hasChanges)
    }
    func testSaleBeforeAcquisitionLeavesHoldingsUnchanged() throws {
        let container = try TestPortfolio.make()
        let holding = TestPortfolio.holding(in: container.viewContext)
        try container.viewContext.save()
        XCTAssertThrowsError(try ETFSale.stage(etf: holding.holdingtoetf, shares: 1,
            executionPrice: 110, date: TestPortfolio.date("2024-12-31T00:00:00Z"),
            context: container.viewContext))
        XCTAssertFalse(container.viewContext.hasChanges)
    }

}
