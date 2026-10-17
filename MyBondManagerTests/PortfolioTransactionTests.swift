import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class PortfolioTransactionTests: XCTestCase {
    enum Failure: Error { case injected }
    func testFailedSavePreservesStoreAndUnrelatedDraft() async throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext)
        try container.viewContext.save()
        bond.name = "Unrelated draft"
        do {
            try await PortfolioTransaction.run(in: container) { context in
                let bonds = try context.fetch(BondEntity.fetchRequest())
                bonds.forEach(context.delete)
                let invalid = HistoricalValuation(context: context)
                invalid.id = UUID(); invalid.assetType = "Bond"
                invalid.investedCapital = 0; invalid.capitalGains = 0
            }
            XCTFail("Expected validation failure")
        } catch {}
        XCTAssertEqual(bond.name, "Unrelated draft")
        let reader = container.newBackgroundContext()
        let counts = try await reader.perform {
            (try reader.count(for: BondEntity.fetchRequest()),
             try reader.count(for: HistoricalValuation.fetchRequest()))
        }
        XCTAssertEqual(counts.0, 1); XCTAssertEqual(counts.1, 0)
    }
    func testAcquisitionPersistsPositionAndHistoryTogether() async throws {
        let container = try TestPortfolio.make()
        try await PortfolioTransaction.run(in: container) { context in
            let bond = TestPortfolio.bond(in: context, cost: 900)
            try CashFlowGenerator(context: context).regenerateCashFlows(for: bond, now: TestPortfolio.date("2026-10-01T12:00:00Z"))
            try HistoricalDataRecorder.recordBondAcquisition(bond: bond, context: context)
        }
        let reader = container.newBackgroundContext()
        let counts = try await reader.perform {
            (try reader.count(for: BondEntity.fetchRequest()),
             try reader.count(for: HistoricalValuation.fetchRequest()))
        }
        XCTAssertEqual(counts.0, 1); XCTAssertEqual(counts.1, 1)
    }
    func testBackgroundSaveMergesIntoLoadedRelationship() async throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext)
        try container.viewContext.save()
        XCTAssertTrue(bond.cashFlowsArray.isEmpty)
        let merged = expectation(description: "loaded relationship updated")
        merged.assertForOverFulfill = false
        let token = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextObjectsDidChange,
            object: container.viewContext, queue: .main) { _ in
                if bond.cashFlowsArray.contains(where: { $0.amount == 55 }) { merged.fulfill() }
            }
        defer { NotificationCenter.default.removeObserver(token) }
        let id = bond.objectID
        try await PortfolioTransaction.run(in: container) { context in
            let stored = try XCTUnwrap(context.existingObject(with: id) as? BondEntity)
            let flow = CashFlowEntity(context: context)
            flow.bond = stored; flow.amount = 55; flow.date = Date(); flow.natureEnum = .interest
        }
        await fulfillment(of: [merged], timeout: 5)
        XCTAssertEqual(bond.cashFlowsArray.count, 1)
    }

    func testRecalculationReplacesLoadedCashFlowRows() async throws {
        let container = try TestPortfolio.make()
        let context = container.viewContext
        let bond = try TestPortfolio.readyBond(in: context,
            terms: BondTermsFixtures.fixed(frequency: 1, next: "2027-01-15"),
            now: TestPortfolio.date("2026-10-01T12:00:00Z"))
        try CashFlowGenerator(context: context).regenerateCashFlows(for: bond, now: TestPortfolio.date("2026-10-01T12:00:00Z"))
        try context.save()
        let oldIDs = Set(bond.cashFlowsArray.map(\.objectID))
        XCTAssertFalse(oldIDs.isEmpty)
        let merged = expectation(description: "Regenerated cash flows merge")
        let token = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextDidMergeChangesObjectIDs,
            object: context, queue: .main) { _ in merged.fulfill() }
        defer { NotificationCenter.default.removeObserver(token) }
        let id = bond.objectID
        try await PortfolioTransaction.run(in: container) { operation in
            let stored = try XCTUnwrap(operation.existingObject(with: id) as? BondEntity)
            try CashFlowGenerator(context: operation).regenerateCashFlows(for: stored, now: TestPortfolio.date("2026-10-01T12:00:00Z"))
        }
        await fulfillment(of: [merged], timeout: 5)
        let rows = bond.cashFlowsArray
        XCTAssertEqual(rows.count, oldIDs.count)
        XCTAssertTrue(oldIDs.isDisjoint(with: Set(rows.map(\.objectID))))
        XCTAssertTrue(rows.filter { $0.natureEnum == .interest }.allSatisfy { $0.amount == 33.75 })
    }
    func testEditFormPersistenceActionUsesInjectedContainer() async throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext, cost: 900)
        try container.viewContext.save()
        let original = try XCTUnwrap(ExportManager.snapshot(from: container.viewContext).bonds.first)
        let changed = BondCodable(id: original.id, name: "Edited in fixture", isin: original.isin,
            issuer: original.issuer, depotBank: original.depotBank, acquisitionDate: original.acquisitionDate,
            maturityDate: original.maturityDate, couponRate: original.couponRate, parValue: original.parValue,
            initialPrice: 950, yieldToMaturity: original.yieldToMaturity, wkn: original.wkn, cashFlows: [])
        try await EditBondView.persistChanges(bondID: bond.objectID, values: changed, in: container)
        let reader = container.newBackgroundContext()
        let result = try await reader.perform {
            let stored = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first)
            return (stored.name, stored.initialPrice, try reader.count(for: CashFlowEntity.fetchRequest()))
        }
        XCTAssertEqual(result.0, "Edited in fixture"); XCTAssertEqual(result.1, 950)
        XCTAssertEqual(result.2, 0) // Unreviewed financial edits cannot invent an annual schedule.
    }

}
