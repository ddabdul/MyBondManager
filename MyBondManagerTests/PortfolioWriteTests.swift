import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class PortfolioWriteTests: XCTestCase {
    func testRecorderAndGeneratorDoNotSaveTheirCallerContext() throws {
        let container = try TestPortfolio.make()
        let context = container.viewContext
        let bond = TestPortfolio.bond(in: context)
        try CashFlowGenerator(context: context).regenerateCashFlows(for: bond)
        try HistoricalDataRecorder.recordBondAcquisition(bond: bond, context: context)
        XCTAssertTrue(context.hasChanges)
        let reader = container.newBackgroundContext()
        let count = try reader.performAndWait { try reader.count(for: BondEntity.fetchRequest()) }
        XCTAssertEqual(count, 0)
    }
    func testMaturityGainUsesPurchaseCost() throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext, cost: 900)
        try HistoricalDataRecorder.recordBondMaturity(bond: bond, redemptionAmount: 1000,
                                                      context: container.viewContext)
        let records = try container.viewContext.fetch(HistoricalValuation.fetchRequest())
        XCTAssertEqual(records.first?.capitalGains.doubleValue, 100)
    }
    func testDormantSaveHelperPersistsGeneratedFlows() async throws {
        let persistence = PersistenceController(inMemory: true)
        let context = persistence.container.viewContext
        let entity = try XCTUnwrap(persistence.container.managedObjectModel.entitiesByName["BondEntity"])
        let bond = BondEntity(entity: entity, insertInto: context)
        bond.id = UUID(); bond.name = "Helper"; bond.isin = "DE0000000001"
        bond.issuer = "Issuer"; bond.wkn = "TEST01"; bond.depotBank = "Bank"
        bond.parValue = 1000; bond.initialPrice = 900; bond.couponRate = 5; bond.yieldToMaturity = 0
        bond.acquisitionDate = TestPortfolio.date("2025-01-01T00:00:00Z")
        bond.maturityDate = TestPortfolio.date("2027-01-01T00:00:00Z")
        try await persistence.saveAndGenerateCashFlows(bond: bond)
        await persistence.backgroundContext.perform {}
        let reader = persistence.container.newBackgroundContext()
        let count = try await reader.perform { try reader.count(for: CashFlowEntity.fetchRequest()) }
        XCTAssertGreaterThan(count, 0)
    }

    func testFailedSaleHistorySaveKeepsEveryLot() async throws {
        let container = try TestPortfolio.make()
        let first = TestPortfolio.holding(in: container.viewContext, shares: 5, price: 80)
        _ = TestPortfolio.holding(in: container.viewContext, shares: 10, price: 90, etf: first.holdingtoetf)
        try container.viewContext.save()
        let id = first.holdingtoetf.objectID
        do {
            try await PortfolioTransaction.run(in: container) { context in
                let etf = try XCTUnwrap(context.existingObject(with: id) as? ETFEntity)
                try ETFSale.stage(etf: etf, shares: 8, executionPrice: 110, date: Date(), context: context)
                let history = try XCTUnwrap(context.insertedObjects.first { $0.entity.name == "HistoricalValuation" })
                history.setValue(nil, forKey: "date")
            }
            XCTFail("Expected failed sale transaction")
        } catch {}
        let reader = container.newBackgroundContext()
        let values = try await reader.perform {
            (try reader.fetch(ETFHoldings.fetchRequest()).map { $0.numberOfShares }.sorted(),
             try reader.count(for: HistoricalValuation.fetchRequest()))
        }
        XCTAssertEqual(values.0, [5, 10]); XCTAssertEqual(values.1, 0)
    }

}
