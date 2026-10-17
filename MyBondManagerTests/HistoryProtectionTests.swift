import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class HistoryProtectionTests: XCTestCase {
    private func values(_ bond: BondEntity, name: String = "Changed", par: Double? = nil) -> BondCodable {
        BondCodable(id: bond.id, name: name, isin: bond.isin, issuer: bond.issuer,
            depotBank: bond.depotBank, acquisitionDate: bond.acquisitionDate,
            maturityDate: bond.maturityDate, couponRate: bond.couponRate,
            parValue: par ?? bond.parValue, initialPrice: bond.initialPrice,
            yieldToMaturity: bond.yieldToMaturity, wkn: bond.wkn, cashFlows: [])
    }

    func testDescriptiveEditPreservesAcquisitionHistory() async throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext)
        try HistoricalDataRecorder.recordBondAcquisition(bond: bond, context: container.viewContext)
        try container.viewContext.save()
        try await EditBondView.persistChanges(bondID: bond.objectID, values: values(bond), in: container)
        let reader = container.newBackgroundContext()
        let result = try await reader.perform {
            (try reader.fetch(BondEntity.fetchRequest()).first?.name,
             try reader.fetch(HistoricalValuation.fetchRequest()).first?.investedCapital.doubleValue)
        }
        XCTAssertEqual(result.0, "Changed"); XCTAssertEqual(result.1, 1000)
    }

    func testIdentifiedHistoryForAnotherBondDoesNotBlockEdit() async throws {
        let container = try TestPortfolio.make()
        let first = TestPortfolio.bond(in: container.viewContext)
        let second = TestPortfolio.bond(in: container.viewContext)
        try HistoricalDataRecorder.recordBondAcquisition(bond: first, context: container.viewContext)
        try container.viewContext.save()
        let id = second.objectID
        try await EditBondView.persistChanges(bondID: id, values: values(second, par: 2000), in: container)
        let reader = container.newBackgroundContext()
        let nominal = try await reader.perform { (try reader.existingObject(with: id) as? BondEntity)?.parValue }
        XCTAssertEqual(nominal, 2000)
    }

    func testUnlinkedLegacyBondHistoryBlocksFinancialChange() async throws {
        let container = try TestPortfolio.make()
        let context = container.viewContext
        let bond = TestPortfolio.bond(in: context)
        try HistoricalDataRecorder.recordChange(assetType: .bond, investedDelta: 1000,
            interestDelta: 0, gainsDelta: 0, context: context)
        try context.save()
        do {
            try await EditBondView.persistChanges(bondID: bond.objectID, values: values(bond, par: 2000), in: container)
            XCTFail("Expected conservative legacy protection")
        } catch {}
        let reader = container.newBackgroundContext()
        let nominal = try await reader.perform { try reader.fetch(BondEntity.fetchRequest()).first?.parValue }
        XCTAssertEqual(nominal, 1000)
    }

    func testLegacyETFSaleBlocksEarlierTransactions() throws {
        let container = try TestPortfolio.make()
        let context = container.viewContext
        let holding = TestPortfolio.holding(in: context)
        try HistoricalDataRecorder.recordChange(assetType: .etf, investedDelta: -90,
            interestDelta: nil, gainsDelta: 10, date: TestPortfolio.date("2025-04-01T00:00:00Z"), context: context)
        try context.save()
        XCTAssertThrowsError(try ETFSale.stage(etf: holding.holdingtoetf, shares: 1, executionPrice: 100,
            date: TestPortfolio.date("2025-03-01T00:00:00Z"), context: context))
        XCTAssertFalse(context.hasChanges)
    }

    func testRecordedSaleCutoffSurvivesInstrumentRecreationAndDoesNotBlockOtherISIN() throws {
        let container = try TestPortfolio.make()
        let context = container.viewContext
        let holding = TestPortfolio.holding(in: context, shares: 1)
        let etf = holding.holdingtoetf
        try context.save()
        try ETFSale.stage(etf: etf, shares: 1, executionPrice: 100,
            date: TestPortfolio.date("2025-04-01T00:00:00Z"), context: context)
        context.delete(etf); try context.save()
        let replacement = TestPortfolio.holding(in: context)
        let other = TestPortfolio.holding(in: context)
        other.holdingtoetf.isin = "DE0000000003"
        try context.save()
        XCTAssertThrowsError(try ETFSale.stage(etf: replacement.holdingtoetf, shares: 1, executionPrice: 100,
            date: TestPortfolio.date("2025-03-01T00:00:00Z"), context: context))
        XCTAssertFalse(context.hasChanges)
        try ETFSale.stage(etf: other.holdingtoetf, shares: 1, executionPrice: 100,
            date: TestPortfolio.date("2025-03-01T00:00:00Z"), context: context)
        XCTAssertEqual(other.numberOfShares, 9)
    }
}
