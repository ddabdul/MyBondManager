import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class CashFlowRecalculationTests: XCTestCase {
    func testArchivedUnreviewedHoldingsDoNotProduceRecalculationWarning() throws {
        let container = try TestPortfolio.make()
        let now = TestPortfolio.date("2026-10-17T12:00:00Z")
        let active = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: now)
        var archived: [BondEntity] = []
        for _ in 0..<40 {
            let bond = TestPortfolio.bond(in: container.viewContext)
            bond.maturityDate = TestPortfolio.date("2025-01-15T12:00:00Z")
            let flow = CashFlowEntity(context: container.viewContext)
            flow.bond = bond; flow.date = bond.maturityDate; flow.amount = 1000; flow.nature = "principal"
            archived.append(bond)
        }
        try container.viewContext.save()
        let count = try CashFlowGenerator(context: container.viewContext).regenerateAllCashFlows(now: now)
        XCTAssertEqual(count, 0)
        XCTAssertNil(BondTermsPresentation.exclusions(count))
        XCTAssertTrue(active.termsReady)
        for bond in archived {
            XCTAssertNil(bond.termsIssue)
            XCTAssertNil(bond.termsData)
            XCTAssertFalse(bond.hasChanges)
            XCTAssertEqual(bond.cashFlowsArray.count, 1)
            XCTAssertEqual(bond.cashFlowsArray.first?.amount, 1000)
        }
    }
    func testRecalculationCountsActiveHoldingThatReallyNeedsReview() throws {
        let container = try TestPortfolio.make()
        let now = TestPortfolio.date("2026-10-17T12:00:00Z")
        _ = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: now)
        let active = TestPortfolio.bond(in: container.viewContext)
        let archived = TestPortfolio.bond(in: container.viewContext)
        archived.maturityDate = TestPortfolio.date("2025-01-15T12:00:00Z")
        try container.viewContext.save()
        let count = try CashFlowGenerator(context: container.viewContext).regenerateAllCashFlows(now: now)
        XCTAssertEqual(count, 1)
        XCTAssertEqual(BondTermsPresentation.exclusions(count), "Forecast excludes 1 holding needing review.")
        XCTAssertEqual(count, BondEligibility.excludedCount([active, archived], on: MarketDay(date: now)))
        XCTAssertFalse(active.termsReady)
        XCTAssertNotNil(active.termsIssue)
        XCTAssertFalse(archived.hasChanges)
    }
}
