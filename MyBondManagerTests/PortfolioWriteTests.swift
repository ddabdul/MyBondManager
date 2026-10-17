import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class PortfolioWriteTests: XCTestCase {
    func testFinancialEditCannotContradictAcquisitionHistory() async throws {
        let container = try TestPortfolio.make()
        let context = container.viewContext
        let bond = TestPortfolio.bond(in: context, cost: 900)
        try HistoricalDataRecorder.recordBondAcquisition(bond: bond, context: context)
        try context.save()
        let original = try XCTUnwrap(ExportManager.snapshot(from: context).bonds.first)
        let changed = BondCodable(id: original.id, name: original.name, isin: original.isin,
            issuer: original.issuer, depotBank: original.depotBank, acquisitionDate: original.acquisitionDate,
            maturityDate: original.maturityDate, couponRate: original.couponRate, parValue: 2000,
            initialPrice: 1800, yieldToMaturity: 0, wkn: original.wkn, cashFlows: [])
        do {
            try await EditBondView.persistChanges(bondID: bond.objectID, values: changed, in: container)
            XCTFail("Expected history protection")
        } catch {}
        let reader = container.newBackgroundContext()
        let nominal = try await reader.perform { try reader.fetch(BondEntity.fetchRequest()).first?.parValue }
        XCTAssertEqual(nominal, 1000)
    }

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
        let bond = try TestPortfolio.readyBond(in: context,
            terms: BondTermsFixtures.fixed(frequency: 1, next: "2027-01-15"),
            now: TestPortfolio.date("2026-10-01T12:00:00Z"))
        for flow in bond.cashFlowsArray { context.delete(flow) }
        try await persistence.saveAndGenerateCashFlows(bond: bond, now: TestPortfolio.date("2026-10-01T12:00:00Z"))
        await persistence.backgroundContext.perform {}
        let reader = persistence.container.newBackgroundContext()
        let count = try await reader.perform { try reader.count(for: CashFlowEntity.fetchRequest()) }
        XCTAssertGreaterThan(count, 0)
    }

    func testInstrumentIdentityCannotChangeBehindRecordedHistory() async throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext)
        try HistoricalDataRecorder.recordBondAcquisition(bond: bond, context: container.viewContext)
        try container.viewContext.save()
        let values = BondCodable(id: bond.id, name: bond.name, isin: "DE0000000009", issuer: bond.issuer,
            depotBank: bond.depotBank, acquisitionDate: bond.acquisitionDate, maturityDate: bond.maturityDate,
            couponRate: bond.couponRate, parValue: bond.parValue, initialPrice: bond.initialPrice,
            yieldToMaturity: bond.yieldToMaturity, wkn: bond.wkn, cashFlows: [])
        do { try await EditBondView.persistChanges(bondID: bond.objectID, values: values, in: container); XCTFail("Expected identity/history protection") } catch {}
        let reader = container.newBackgroundContext()
        let isin = try await reader.perform { try reader.fetch(BondEntity.fetchRequest()).first?.isin }
        XCTAssertEqual(isin, "DE0000000001")
    }
    func testAllowedTradeChangeRetainsInstrumentApprovalButInvalidatesPurchase() async throws {
        let container = try TestPortfolio.make()
        let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: TestPortfolio.date("2026-02-03T12:00:00Z"))
        try container.viewContext.save()
        let values = BondCodable(id: bond.id, name: bond.name, isin: bond.isin, issuer: bond.issuer,
            depotBank: bond.depotBank, acquisitionDate: bond.acquisitionDate, maturityDate: bond.maturityDate,
            couponRate: bond.couponRate, parValue: bond.parValue, initialPrice: 950,
            yieldToMaturity: bond.yieldToMaturity, wkn: bond.wkn, cashFlows: [])
        try await EditBondView.persistChanges(bondID: bond.objectID, values: values, in: container)
        let reader = container.newBackgroundContext()
        try await reader.perform {
            let stored = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first)
            XCTAssertFalse(BondTermsStore.isReady(stored))
            XCTAssertEqual(try BondTermsStore.read(stored)?.approvedAt, TestPortfolio.date("2026-02-03T12:00:00Z"))
            let draft = try XCTUnwrap(BondTermsStore.readDraft(stored))
            XCTAssertEqual(draft.trade.cost, 950); XCTAssertNil(draft.proposed.approvedAt)
            XCTAssertEqual(draft.proposed.frequency, 2)
        }
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
