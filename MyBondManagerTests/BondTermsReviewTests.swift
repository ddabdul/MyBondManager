import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class BondTermsReviewTests: XCTestCase {
    private func review(_ container: NSPersistentContainer, now: @escaping () -> Date = { TestPortfolio.date("2026-02-03T12:00:00Z") }) -> BondTermsReview {
        BondTermsReview(container: container, fetch: { _ in try BondTermsFixtures.details() }, now: now)
    }
    func testDeduplicatesCollectionAndKeepsSuccessfulDraftsAcrossReload() async throws {
        let container = try TestPortfolio.make()
        let first = TestPortfolio.bond(in: container.viewContext)
        let second = TestPortfolio.bond(in: container.viewContext)
        let third = TestPortfolio.bond(in: container.viewContext); third.isin = "DE0000000003"
        try container.viewContext.save()
        var requests: [String] = []
        let service = BondTermsReview(container: container, fetch: { isin in
            requests.append(isin)
            if isin == "DE0000000003" { throw PortfolioError("Fixture unavailable") }
            return try BondTermsFixtures.details()
        }, now: { TestPortfolio.date("2026-02-03T12:00:00Z") })
        await service.collect(ids: [first.id, second.id, third.id])
        XCTAssertEqual(Set(requests), Set(["DE0000000001", "DE0000000003"]))
        XCTAssertEqual(requests.count, 2); XCTAssertEqual(service.drafts.count, 2)
        XCTAssertFalse(service.errors.isEmpty)
        let resumed = review(container); try await resumed.load()
        XCTAssertEqual(Set(resumed.drafts.keys), Set([first.id, second.id]))
    }
    func testApprovalIsAtomicAndRejectsChangedTradeOrDeletedIdentity() async throws {
        let container = try TestPortfolio.make()
        let first = TestPortfolio.bond(in: container.viewContext)
        let second = TestPortfolio.bond(in: container.viewContext)
        try HistoricalDataRecorder.recordBondAcquisition(bond: first, context: container.viewContext)
        try container.viewContext.save()
        let service = review(container); await service.collect(ids: [first.id, second.id])
        second.initialPrice = 1200; try container.viewContext.save()
        do { try await service.apply(ids: [first.id, second.id]); XCTFail("Expected stale trade") } catch {}
        container.viewContext.refreshAllObjects()
        XCTAssertFalse(BondTermsStore.isReady(first)); XCTAssertEqual(second.initialPrice, 1200)
        XCTAssertEqual(try container.viewContext.count(for: HistoricalValuation.fetchRequest()), 1)
        let deletedID = second.id
        container.viewContext.delete(second); try container.viewContext.save()
        do { try await service.apply(ids: [deletedID]); XCTFail("Expected missing holding") } catch {}
    }
    func testFailedApprovalSaveRollsBackSelectedProfilesAndRetainsUnrelatedDraft() async throws {
        let container = try TestPortfolio.make()
        let first = TestPortfolio.bond(in: container.viewContext)
        let second = TestPortfolio.bond(in: container.viewContext)
        let ids = [first.id, second.id]
        try container.viewContext.save()
        let service = review(container); await service.collect(ids: ids)
        let unrelated = TestPortfolio.holding(in: container.viewContext)
        let coordinator = container.persistentStoreCoordinator
        let token = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextWillSave, object: nil, queue: nil) { note in
            guard let context = note.object as? NSManagedObjectContext,
                  context.persistentStoreCoordinator === coordinator, context.concurrencyType == .privateQueueConcurrencyType else { return }
            for case let bond as BondEntity in context.updatedObjects where bond.id == ids[1] {
                bond.setValue(nil, forKey: "name")
            }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        do { try await service.apply(ids: ids); XCTFail("Expected save failure") } catch {}
        let reader = container.newBackgroundContext()
        let state = try await reader.perform {
            (try reader.fetch(BondEntity.fetchRequest()).allSatisfy { !$0.termsReady },
             try reader.count(for: CashFlowEntity.fetchRequest()))
        }
        XCTAssertTrue(state.0); XCTAssertEqual(state.1, 0)
        XCTAssertEqual(service.drafts.count, 2)
        XCTAssertTrue(container.viewContext.hasChanges); XCTAssertFalse(unrelated.isDeleted)
    }
    func testNewUnapprovedHoldingHasDraftAndAcquisitionButNoUnverifiedFlows() async throws {
        let source = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: source.viewContext)
        let values = try XCTUnwrap(ExportManager.snapshot(from: source.viewContext).bonds.first)
        let target = try TestPortfolio.make()
        let service = review(target)
        _ = try await service.saveNew(values: values, terms: BondTermsFixtures.fixed(), legacyDateZone: "Europe/Berlin")
        let reader = target.newBackgroundContext()
        try await reader.perform {
            let stored = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first)
            XCTAssertFalse(BondTermsStore.isReady(stored)); XCTAssertNotNil(try BondTermsStore.readDraft(stored))
            XCTAssertEqual(try reader.count(for: CashFlowEntity.fetchRequest()), 0)
            XCTAssertEqual(try reader.count(for: HistoricalValuation.fetchRequest()), 1)
            XCTAssertEqual(stored.id, bond.id)
        }
    }
    func testMidnightRequiresNewPreviewAndConfirmedOverridesSurviveRefresh() async throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext); try container.viewContext.save()
        var now = TestPortfolio.date("2026-02-03T12:00:00Z")
        let service = review(container, now: { now }); await service.collect(ids: [bond.id])
        var draft = try XCTUnwrap(service.drafts[bond.id])
        draft.proposed.redemptionPercent = 105; draft.proposed.confirmedFields.insert("redemptionPercent")
        try await service.edit(draft)
        now = TestPortfolio.date("2026-02-04T12:00:00Z")
        do { try await service.apply(ids: [bond.id]); XCTFail("Expected new preview required") } catch {}
        draft.previewDay = MarketDay(date: now); try await service.edit(draft)
        try await service.apply(ids: [bond.id]); await service.collect(ids: [bond.id])
        XCTAssertEqual(service.drafts[bond.id]?.proposed.redemptionPercent, 105)
        XCTAssertTrue(service.drafts[bond.id]?.proposed.confirmedFields.contains("redemptionPercent") == true)
    }
    func testEditingCannotEraseDiscoveredUnsupportedRestrictions() async throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext); try container.viewContext.save()
        let service = BondTermsReview(container: container, fetch: { _ in
            var terms = try BondTermsFixtures.fixed(); terms.restrictions = ["floating"]
            return BondDetails(name: "Floating", wkn: "TEST01", issuer: "Issuer", maturityDate: terms.maturity?.instant, couponRate: terms.couponRate, terms: terms)
        }, now: { TestPortfolio.date("2026-02-03T12:00:00Z") })
        await service.collect(ids: [bond.id])
        var draft = try XCTUnwrap(service.drafts[bond.id]); draft.proposed.restrictions = []; draft.proposed.structure = .fixed
        try await service.edit(draft)
        XCTAssertFalse(try service.preview(XCTUnwrap(service.drafts[bond.id])).assessment.supported)
        do { try await service.apply(ids: [bond.id]); XCTFail("Expected unsupported") } catch {}
    }
func testMissingProviderTermsPersistUntilExplicitCorrection() async throws {
    for missingField in ["couponRate", "maturity"] {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.legacyBond(in: container.viewContext)
        bond.acquisitionDate = TestPortfolio.date("2026-02-01T00:00:00Z")
        bond.maturityDate = TestPortfolio.date("2027-01-15T00:00:00Z")
        bond.couponRate = 3.375
        try container.viewContext.save()
        var partial = try BondTermsFixtures.fixed()
        if missingField == "couponRate" { partial.couponRate = nil }
        else { partial.maturity = nil }
        let response = BondDetails(name: "EUR note", wkn: "TEST01", issuer: "Issuer",
            maturityDate: partial.maturity?.instant, couponRate: partial.couponRate, terms: partial)
        let review = BondTermsReview(container: container, fetch: { _ in response },
            now: { TestPortfolio.date("2026-02-03T12:00:00Z") })
        await review.collect(ids: [bond.id])
        let resumed = BondTermsReview(container: container, fetch: { _ in
            throw PortfolioError("Load must not fetch.")
        }, now: { TestPortfolio.date("2026-02-03T12:00:00Z") })
        try await resumed.load()
        var draft = try XCTUnwrap(resumed.drafts[bond.id])
        XCTAssertFalse(try resumed.preview(draft).assessment.supported)
        if missingField == "couponRate" { XCTAssertNil(draft.proposed.couponRate) }
        else { XCTAssertNil(draft.proposed.maturity) }
        draft.proposed.couponRate = 3.375
        draft.proposed.maturity = try MarketDay("2027-01-15")
        draft.proposed.confirmedFields.insert(missingField)
        try await resumed.edit(draft)
        try await resumed.apply(ids: [bond.id])
        await container.viewContext.perform {
            container.viewContext.refreshAllObjects()
            XCTAssertTrue(BondTermsStore.isReady(bond))
        }
    }
}
}
