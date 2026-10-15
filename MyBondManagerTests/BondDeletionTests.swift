import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class BondDeletionTests: XCTestCase {
    func testFailedDeletionKeepsBondsFlowsAndUnrelatedDraft() async throws {
        let container = try TestPortfolio.make()
        let context = container.viewContext
        let bond = TestPortfolio.bond(in: context)
        try CashFlowGenerator(context: context).regenerateCashFlows(for: bond)
        try context.save()
        let id = bond.objectID
        bond.name = "Unrelated draft"
        do {
            try await PortfolioTransaction.run(in: container) { operation in
                try BondDeletion.stage(ids: [id], context: operation)
                let invalid = HistoricalValuation(context: operation)
                invalid.id = UUID()
            }
            XCTFail("Expected save failure")
        } catch {}
        let reader = container.newBackgroundContext()
        let counts = try await reader.perform {
            (try reader.count(for: BondEntity.fetchRequest()), try reader.count(for: CashFlowEntity.fetchRequest()))
        }
        XCTAssertEqual(counts.0, 1); XCTAssertGreaterThan(counts.1, 0)
        XCTAssertEqual(bond.name, "Unrelated draft")
    }

    func testSuccessfulDeletionCascadesFlowsAndKeepsHistory() async throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext)
        try CashFlowGenerator(context: container.viewContext).regenerateCashFlows(for: bond)
        try HistoricalDataRecorder.recordBondAcquisition(bond: bond, context: container.viewContext)
        try container.viewContext.save()
        let id = bond.objectID
        try await PortfolioTransaction.run(in: container) { try BondDeletion.stage(ids: [id], context: $0) }
        let reader = container.newBackgroundContext()
        let counts = try await reader.perform {
            (try reader.count(for: BondEntity.fetchRequest()), try reader.count(for: CashFlowEntity.fetchRequest()),
             try reader.count(for: HistoricalValuation.fetchRequest()))
        }
        XCTAssertEqual(counts.0, 0); XCTAssertEqual(counts.1, 0); XCTAssertEqual(counts.2, 1)
    }
}
