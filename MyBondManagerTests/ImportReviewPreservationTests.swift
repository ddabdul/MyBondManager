import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class ImportReviewPreservationTests: XCTestCase {
    private let now = TestPortfolio.date("2026-10-17T12:00:00Z")

    private func replacing(_ row: BondCodable, _ values: [String: Any]) throws -> BondCodable {
        let data = try BondTransfer.encoder().encode(row)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for (key, value) in values { object[key] = value }
        return try BondTransfer.decoder().decode(BondCodable.self, from: JSONSerialization.data(withJSONObject: object))
    }

    func testFullLegacyImportPreservesApprovedProfileAndGeneratedPayments() async throws {
        let container = try TestPortfolio.make()
        let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: now)
        try container.viewContext.save()
        let profile = bond.termsData
        let activation = bond.eventsActivateAfter
        let flowIDs = Set(bond.cashFlowsArray.map(\.objectID))
        let yield = bond.yieldToMaturity
        var incoming = try ExportManager.snapshotBonds(from: container.viewContext)
        incoming[0] = try replacing(incoming[0], ["name": "Updated description", "yieldToMaturity": 0])
        try await ImportManager().apply(PositionsPayload(bonds: incoming, etfs: []), into: container)
        let reader = container.newBackgroundContext()
        try await reader.perform {
            let stored = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first)
            XCTAssertEqual(stored.name, "Updated description")
            XCTAssertEqual(stored.termsData, profile)
            XCTAssertEqual(stored.eventsActivateAfter, activation)
            XCTAssertEqual(stored.yieldToMaturity, yield)
            XCTAssertEqual(Set(stored.cashFlowsArray.map(\.objectID)), flowIDs)
            XCTAssertTrue(stored.cashFlowsArray.allSatisfy(\.generatedFromTerms))
            XCTAssertTrue(BondTermsStore.isReady(stored))
        }
    }

    func testUnreviewedNativeEntryDoesNotOverwriteLocalApproval() async throws {
        let container = try TestPortfolio.make()
        let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: now)
        try container.viewContext.save()
        let profile = bond.termsData
        var rows = try ExportManager.snapshotBonds(from: container.viewContext)
        rows[0] = try replacing(rows[0], ["cashFlows": []])
        let bytes = try BondTransfer.encoder().encode(rows)
        let entry = try BondTermsEntry(id: bond.id, isin: bond.isin, terms: nil, draft: nil,
            acquisitionDay: BondTermsStore.trade(bond).acquisitionDay, legacyDateZone: "Europe/Berlin",
            projectionFrom: nil, needsReviewReasons: ["Needs review"])
        let transfer = PreparedBondTransfer(bonds: rows, bondsBytes: bytes,
            native: BondTermsEnvelope(version: 1, bondsSHA256: BondTransfer.digest(bytes), bonds: [entry]))
        let remaining = try await ImportManager().applyBonds(transfer, into: container, now: now)
        XCTAssertEqual(remaining, 0)
        let reader = container.newBackgroundContext()
        try await reader.perform {
            let stored = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first)
            XCTAssertEqual(stored.termsData, profile)
            XCTAssertTrue(BondTermsStore.isReady(stored))
            XCTAssertFalse(stored.cashFlowsArray.isEmpty)
        }
    }

    func testChangedLegacyPositionRejectsWholeImportAndKeepsReview() async throws {
        let container = try TestPortfolio.make()
        let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: now)
        try container.viewContext.save()
        let profile = bond.termsData
        let rate = bond.couponRate
        var rows = try ExportManager.snapshotBonds(from: container.viewContext)
        rows[0] = try replacing(rows[0], ["couponRate": rows[0].couponRate + 1])
        do {
            try await ImportManager().applyBonds(PreparedBondTransfer(bonds: rows, bondsBytes: nil, native: nil),
                                                  into: container, now: now)
            XCTFail("Import must reject a change that would discard saved reviews")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("saved review"), error.localizedDescription)
        }
        let reader = container.newBackgroundContext()
        try await reader.perform {
            let stored = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first)
            XCTAssertEqual(stored.termsData, profile)
            XCTAssertEqual(stored.couponRate, rate)
            XCTAssertTrue(BondTermsStore.isReady(stored))
        }
    }

    func testFullLegacyImportRejectsFinancialChangesAndRollsBackEarlierRows() async throws {
        let container = try TestPortfolio.make()
        let reviewed = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: now)
        let other = TestPortfolio.bond(in: container.viewContext)
        try container.viewContext.save()
        let all = try ExportManager.snapshotBonds(from: container.viewContext)
        let original = try XCTUnwrap(all.first { $0.id == reviewed.id })
        let otherOriginal = try XCTUnwrap(all.first { $0.id == other.id })
        let changedOther = try replacing(otherOriginal, ["name": "Must roll back"])
        let profile = reviewed.termsData
        let mutations: [[String: Any]] = [
            ["parValue": 2000], ["initialPrice": 850], ["couponRate": 4],
            ["depotBank": "Another bank"], ["isin": "DE0000000002"],
            ["acquisitionDate": "2026-02-02T00:00:00Z"], ["maturityDate": "2028-01-15T00:00:00Z"]
        ]
        for values in mutations {
            let changed = try replacing(original, values)
            do {
                try await ImportManager().apply(PositionsPayload(bonds: [changedOther, changed], etfs: []), into: container)
                XCTFail("Destructive import should fail: \(values)")
            } catch {
                XCTAssertTrue(error.localizedDescription.contains("saved review"), error.localizedDescription)
            }
            let reader = container.newBackgroundContext()
            try await reader.perform {
                let stored = try reader.fetch(BondEntity.fetchRequest())
                XCTAssertEqual(stored.first { $0.id == original.id }?.termsData, profile)
                XCTAssertEqual(stored.first { $0.id == otherOriginal.id }?.name, otherOriginal.name)
            }
        }
    }

    func testIdenticalApprovedNativeImportKeepsPendingDraftAndActivation() async throws {
        let container = try TestPortfolio.make()
        let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: now)
        try container.viewContext.save()
        let files = try BondTransfer.encode(BondTransfer.snapshot(from: container.viewContext))
        let originalProfile = bond.termsData
        let originalActivation = bond.eventsActivateAfter
        let review = BondTermsReview(container: container, now: { self.now })
        try await review.beginManualReview(ids: [bond.id])
        let reader = container.newBackgroundContext()
        let draft = try await reader.perform { try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first).termsDraftData }
        try await ImportManager().applyBonds(BondTransfer.prepare(bonds: files.bonds, sidecar: files.sidecar),
            into: container, now: TestPortfolio.date("2026-10-18T12:00:00Z"))
        let check = container.newBackgroundContext()
        try await check.perform {
            let stored = try XCTUnwrap(check.fetch(BondEntity.fetchRequest()).first)
            XCTAssertEqual(stored.termsDraftData, draft)
            XCTAssertEqual(stored.termsData, originalProfile)
            XCTAssertEqual(stored.eventsActivateAfter, originalActivation)
        }
    }

    func testIdenticalNativeApprovalStillImportsDraftWhenLocalDraftIsMissing() async throws {
        let container = try TestPortfolio.make()
        let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: now)
        try container.viewContext.save()
        let originalProfile = bond.termsData
        let originalActivation = bond.eventsActivateAfter
        let review = BondTermsReview(container: container, now: { self.now })
        try await review.beginManualReview(ids: [bond.id])
        container.viewContext.refreshAllObjects()
        let files = try BondTransfer.encode(BondTransfer.snapshot(from: container.viewContext))
        let incoming = try BondTransfer.prepare(bonds: files.bonds, sidecar: files.sidecar)
        XCTAssertNotNil(incoming.native?.bonds.first?.draft)
        try await PortfolioTransaction.run(in: container) { context in
            let stored = try XCTUnwrap(context.fetch(BondEntity.fetchRequest()).first)
            stored.termsDraftData = nil
        }
        try await ImportManager().applyBonds(incoming, into: container, now: now)
        let reader = container.newBackgroundContext()
        try await reader.perform {
            let stored = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first)
            XCTAssertNotNil(try BondTermsStore.readDraft(stored))
            XCTAssertEqual(stored.termsData, originalProfile)
            XCTAssertEqual(stored.eventsActivateAfter, originalActivation)
        }
    }

    func testDescriptionOnlyImportLeavesSavedDraftUsableAfterReopening() async throws {
        let container = try TestPortfolio.make()
        let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: now)
        try container.viewContext.save()
        let id = bond.id
        let review = BondTermsReview(container: container, now: { self.now })
        try await review.beginManualReview(ids: [id])
        var rows = try ExportManager.snapshotBonds(from: container.viewContext)
        rows[0] = try replacing(rows[0], ["name": "Updated description"])
        try await ImportManager().applyBonds(PreparedBondTransfer(bonds: rows, bondsBytes: nil, native: nil), into: container, now: now)
        let reopened = BondTermsReview(container: container, now: { self.now })
        try await reopened.beginManualReview(ids: [id])
        let result = try await reopened.apply(ids: [id])
        XCTAssertTrue(result.failures.isEmpty)
        let check = container.newBackgroundContext()
        try await check.perform {
            let stored = try XCTUnwrap(check.fetch(BondEntity.fetchRequest()).first)
            XCTAssertEqual(stored.name, "Updated description")
            XCTAssertTrue(BondTermsStore.isReady(stored))
            XCTAssertNil(stored.termsDraftData)
        }
    }

    func testLegacyImportKeepsSavedDraft() async throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext)
        let draft = try BondTermsDraft(baseline: BondBaseline.capture(bond), trade: BondTermsStore.trade(bond),
            legacyDateZone: "Europe/Berlin", proposed: BondTermsFixtures.fixed(), previewDay: MarketDay(date: now))
        try BondTermsStore.stageDraft(draft, for: bond)
        try container.viewContext.save()
        let saved = bond.termsDraftData
        let rows = try ExportManager.snapshotBonds(from: container.viewContext)
        try await ImportManager().applyBonds(PreparedBondTransfer(bonds: rows, bondsBytes: nil, native: nil),
                                              into: container, now: now)
        let reader = container.newBackgroundContext()
        try await reader.perform {
            let stored = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first)
            XCTAssertEqual(stored.termsDraftData, saved)
            XCTAssertFalse(stored.termsReady)
        }
    }
}
