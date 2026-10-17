import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class BondTermsStorageTests: XCTestCase {
    func testLegacyRowsSurviveWithoutApproval() throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext)
        let flow = CashFlowEntity(context: container.viewContext)
        flow.date = bond.maturityDate; flow.amount = 1000; flow.nature = "principal"; flow.bond = bond
        try container.viewContext.save()
        XCTAssertNil(try BondTermsStore.read(bond))
        XCTAssertFalse(BondTermsStore.isReady(bond))
        XCTAssertEqual(bond.cashFlowsArray.count, 1)
    }
    func testApprovalPreservesPastHistoryAndAliasesAndUpdatesYield() throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext, cost: 100000, par: 100000)
        bond.acquisitionDate = TestPortfolio.date("2026-02-01T00:00:00Z")
        bond.maturityDate = TestPortfolio.date("2027-01-15T00:00:00Z")
        let old = CashFlowEntity(context: container.viewContext)
        old.date = TestPortfolio.date("2026-07-15T00:00:00Z"); old.amount = 3375; old.nature = "interest"; old.bond = bond
        let hist = try HistoricalDataRecorder.recordChange(assetType: .bond, investedDelta: 0,
            interestDelta: 3375, gainsDelta: 0, date: old.date, context: container.viewContext)
        hist.eventKey = "\(bond.id)|interest|\(Int(old.date.timeIntervalSince1970))"
        var terms = try BondTermsFixtures.fixed(); terms.redemptionPercent = 105
        let now = TestPortfolio.date("2026-10-01T12:00:00Z"); terms.approvedAt = now
        let preview = try BondSchedule.preview(trade: BondTermsStore.trade(bond), terms: terms, from: MarketDay(date: now))
        try BondTermsStore.replaceProjections(for: bond, terms: terms, preview: preview, now: now,
            acquisitionDay: MarketDay("2026-02-01"), legacyDateZone: "Europe/Berlin", context: container.viewContext)
        XCTAssertTrue(BondTermsStore.isReady(bond))
        XCTAssertFalse(old.isDeleted); XCTAssertEqual(old.amount, 3375)
        XCTAssertEqual(hist.interestReceived?.doubleValue, 3375)
        XCTAssertEqual(bond.yieldToMaturity, try XCTUnwrap(preview.estimatedYTM), accuracy: 1e-10)
        let key = "\(bond.id)|interest|2026-07-15"
        XCTAssertEqual(try BondTermsStore.legacyAliases(bond)[key], [hist.eventKey!])
        let activation = bond.eventsActivateAfter
        try BondTermsStore.replaceProjections(for: bond, terms: terms, preview: preview, now: now,
            acquisitionDay: MarketDay("2026-02-01"), legacyDateZone: "Europe/Berlin", context: container.viewContext)
        XCTAssertEqual(bond.eventsActivateAfter, activation)
        XCTAssertEqual(try BondTermsStore.legacyAliases(bond)[key], [hist.eventKey!])
        bond.initialPrice += 1
        XCTAssertFalse(BondTermsStore.isReady(bond))
    }
    func testSubsecondTradeAndApprovalInstantsSurviveProfilePersistence() throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext)
        bond.acquisitionDate = TestPortfolio.date("2026-02-01T00:00:00Z").addingTimeInterval(0.123456)
        var terms = try BondTermsFixtures.fixed()
        let now = TestPortfolio.date("2026-02-03T12:00:00Z").addingTimeInterval(0.654321)
        terms.approvedAt = now
        let preview = try BondSchedule.preview(trade: BondTermsStore.trade(bond), terms: terms, from: MarketDay(date: now))
        try BondTermsStore.replaceProjections(for: bond, terms: terms, preview: preview, now: now,
            acquisitionDay: MarketDay("2026-02-01"), legacyDateZone: "Europe/Berlin", context: container.viewContext)
        XCTAssertTrue(BondTermsStore.isReady(bond))
        XCTAssertEqual(try BondTermsStore.read(bond)?.approvedAt, now)
    }
    func testCorruptProfilesAreErrorsNotApprovedFallbacks() throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext)
        bond.termsData = Data("bad JSON".utf8); bond.termsReady = true
        XCTAssertThrowsError(try BondTermsStore.read(bond))
        XCTAssertFalse(BondTermsStore.isReady(bond))
        BondTermsStore.clear(bond)
        XCTAssertNil(try BondTermsStore.read(bond)); XCTAssertFalse(bond.termsReady)
    }
    func testConcurrentTransactionsObserveCommittedPredecessor() async throws {
        let container = try TestPortfolio.make()
        _ = TestPortfolio.bond(in: container.viewContext, cost: 1000)
        try container.viewContext.save()
        let read = expectation(description: "first read")
        let release = DispatchSemaphore(value: 0)
        let first = Task.detached {
            try await PortfolioTransaction.run(in: container) { context in
                let row = try XCTUnwrap(context.fetch(BondEntity.fetchRequest()).first)
                let cost = row.initialPrice; read.fulfill()
                guard release.wait(timeout: .now() + 5) == .success else { throw PortfolioError("Test timed out.") }
                row.initialPrice = cost + 1
            }
        }
        await fulfillment(of: [read], timeout: 5)
        let second = Task.detached {
            try await PortfolioTransaction.run(in: container) { context in
                let row = try XCTUnwrap(context.fetch(BondEntity.fetchRequest()).first)
                row.initialPrice += 1
            }
        }
        try await Task.sleep(nanoseconds: 100_000_000)
        release.signal()
        try await first.value; try await second.value
        container.viewContext.refreshAllObjects()
        XCTAssertEqual(try XCTUnwrap(container.viewContext.fetch(BondEntity.fetchRequest()).first).initialPrice, 1002)
    }
}
