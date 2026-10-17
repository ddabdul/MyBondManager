import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class FloatingBondTransferTests: XCTestCase {
    private let approvedAt = TestPortfolio.date("2026-10-16T12:00:00Z")
    private let importedAt = TestPortfolio.date("2026-10-17T12:00:00Z")

    private func addFloating(to container: NSPersistentContainer, mixed: Bool = false,
                             nominal: Double = 1000000) throws -> BondEntity {
        var terms = try FloatingMathFixtures.singlePeriodTerms(start: "2026-10-15", end: "2027-01-15")
        if mixed {
            terms = try FloatingMathFixtures.singlePeriodTerms(start: "2026-01-15", end: "2028-01-15")
            terms.structure = .fixedToFloating; terms.frequency = 1; terms.couponRate = 3
            terms.firstCoupon = try MarketDay("2027-01-15"); terms.floatingStart = terms.firstCoupon
            terms.nextCoupon = terms.firstCoupon; terms.isin = "DE0000000002"
            terms.floatingTerms?.firstFloatingCoupon = try MarketDay("2027-04-15")
        }
        terms.approvedAt = approvedAt
        let market = try FloatingMathFixtures.context(valuation: "2026-10-16",
            fixings: [PublishedFixing(day: MarketDay("2026-10-13"), rate: 0.025)])
        let bond = TestPortfolio.bond(in: container.viewContext, cost: nominal, par: nominal)
        bond.isin = terms.isin
        bond.acquisitionDate = TestPortfolio.date("2026-10-15T00:00:00Z")
        let trade = try BondTermsStore.trade(bond)
        let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay(date: approvedAt), context: market)
        XCTAssertTrue(preview.assessment.supported, preview.assessment.reasons.joined(separator: "; "))
        try BondTermsStore.replaceProjections(for: bond, terms: terms, preview: preview, now: approvedAt,
            acquisitionDay: trade.acquisitionDay, legacyDateZone: "UTC", context: container.viewContext, projectionContext: market)
        return bond
    }

    func testTwoPurchaseFloatingAndMixedOfflineRoundTripDeduplicatesSnapshot() async throws {
        let source = try TestPortfolio.make()
        _ = try addFloating(to: source)
        _ = try addFloating(to: source, nominal: 500000)
        _ = try addFloating(to: source, mixed: true)
        try source.viewContext.save()
        let files = try BondTransfer.encode(BondTransfer.snapshot(from: source.viewContext))
        let prepared = try BondTransfer.prepare(bonds: files.bonds, sidecar: files.sidecar)
        let envelope = try XCTUnwrap(prepared.native)
        XCTAssertEqual(envelope.version, 2)
        XCTAssertEqual(envelope.snapshots?.count, 1)
        XCTAssertEqual(Set(envelope.bonds.compactMap(\.snapshotID)).count, 1)
        XCTAssertTrue(envelope.bonds.allSatisfy { $0.valuationDay?.rawValue == "2026-10-16" })
        XCTAssertTrue(prepared.bonds.allSatisfy { $0.yieldToMaturity == 0 })
        let mixed = try XCTUnwrap(prepared.bonds.first { $0.isin == "DE0000000002" })
        XCTAssertEqual(try XCTUnwrap(mixed.cashFlows.first { $0.nature == "interest" }).amount, 30000, accuracy: 1e-8)
        let plain = prepared.bonds.filter { MarketDay(date: $0.maturityDate).rawValue == "2027-01-15" }
        XCTAssertEqual(try XCTUnwrap(plain.first { $0.parValue == 1000000 }?.cashFlows.first { $0.nature == "interest" }).amount,
            6772.222222222222, accuracy: 1e-8)
        XCTAssertEqual(try XCTUnwrap(plain.first { $0.parValue == 500000 }?.cashFlows.first { $0.nature == "interest" }).amount,
            3386.111111111111, accuracy: 1e-8)
        let target = try TestPortfolio.make()
        let retained = TestPortfolio.bond(in: target.viewContext)
        try HistoricalDataRecorder.recordBondAcquisition(bond: retained, context: target.viewContext)
        try target.viewContext.save()
        try await ImportManager().applyBonds(prepared, into: target, now: importedAt)
        let reader = target.newBackgroundContext()
        try await reader.perform {
            let bonds = try reader.fetch(BondEntity.fetchRequest())
            XCTAssertEqual(bonds.count, 3)
            for bond in bonds {
                XCTAssertTrue(BondTermsStore.isReady(bond))
                XCTAssertNil(try BondTermsStore.estimatedYTM(bond))
                XCTAssertEqual(bond.eventsActivateAfter, self.importedAt)
                let context = try XCTUnwrap(BondTermsStore.projectionContext(bond))
                XCTAssertEqual(context.valuationDay.rawValue, "2026-10-16")
                XCTAssertEqual(context.marketData.id, envelope.bonds.first?.snapshotID)
                let preview = try XCTUnwrap(BondTermsStore.validatedPreview(bond, from: MarketDay("2026-10-17")))
                XCTAssertTrue(preview.assessment.supported)
            }
            XCTAssertEqual(try reader.count(for: HistoricalValuation.fetchRequest()), 1)
            XCTAssertTrue(try LaunchEventProcessor.stage(context: reader, since: self.approvedAt, until: self.importedAt).isEmpty)
        }
        let rows = try XCTUnwrap(JSONSerialization.jsonObject(with: files.bonds) as? [[String: Any]])
        XCTAssertEqual(Set(rows[0].keys), Set(["id", "name", "isin", "issuer", "depotBank", "acquisitionDate", "maturityDate", "couponRate", "parValue", "initialPrice", "yieldToMaturity", "wkn", "cashFlows"]))
        for row in rows {
            for flow in try XCTUnwrap(row["cashFlows"] as? [[String: Any]]) {
                XCTAssertEqual(Set(flow.keys), Set(["date", "amount", "nature"]))
            }
        }
    }


    func testDraftUsesItsOwnFrozenContextAndRemainsUnapprovedAfterImport() async throws {
        let source = try TestPortfolio.make()
        let bond = try addFloating(to: source)
        var proposed = try XCTUnwrap(BondTermsStore.read(bond)); proposed.approvedAt = nil
        proposed.floatingTerms?.spreadBps = 25
        let market = try FloatingMathFixtures.context(valuation: "2026-10-17",
            fixings: [PublishedFixing(day: MarketDay("2026-10-13"), rate: 0.026)])
        try BondTermsStore.stageDraft(BondTermsDraft(baseline: BondBaseline.capture(bond), trade: BondTermsStore.trade(bond),
            legacyDateZone: "UTC", proposed: proposed, previewDay: MarketDay("2026-10-18"), projectionContext: market), for: bond)
        try source.viewContext.save()
        let files = try BondTransfer.encode(BondTransfer.snapshot(from: source.viewContext))
        let prepared = try BondTransfer.prepare(bonds: files.bonds, sidecar: files.sidecar)
        XCTAssertEqual(prepared.native?.snapshots?.count, 2)
        let target = try TestPortfolio.make()
        try await ImportManager().applyBonds(prepared, into: target, now: importedAt)
        let reader = target.newBackgroundContext()
        try await reader.perform {
            let imported = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first)
            XCTAssertEqual(try BondTermsStore.projectionContext(imported)?.valuationDay.rawValue, "2026-10-16")
            let draft = try XCTUnwrap(BondTermsStore.readDraft(imported))
            XCTAssertNil(draft.proposed.approvedAt)
            XCTAssertEqual(draft.proposed.floatingTerms?.spreadBps, 25)
            XCTAssertEqual(draft.projectionContext, market)
            XCTAssertEqual(draft.previewDay.rawValue, "2026-10-18")
            XCTAssertEqual(try BondTermsStore.read(imported)?.floatingTerms?.spreadBps, 15)
        }
    }

    func testDraftWithoutSelectedMarketDataDoesNotBorrowStaleProfileContext() throws {
        let source = try TestPortfolio.make()
        let bond = try addFloating(to: source)
        bond.initialPrice -= 1
        var proposed = try XCTUnwrap(BondTermsStore.read(bond)); proposed.approvedAt = nil
        try BondTermsStore.stageDraft(BondTermsDraft(baseline: BondBaseline.capture(bond), trade: BondTermsStore.trade(bond),
            legacyDateZone: "UTC", proposed: proposed, previewDay: MarketDay("2026-10-17")), for: bond)
        try source.viewContext.save()
        XCTAssertFalse(BondTermsStore.isReady(bond))
        let files = try BondTransfer.encode(BondTransfer.snapshot(from: source.viewContext))
        let transfer = try BondTransfer.prepare(bonds: files.bonds, sidecar: files.sidecar)
        XCTAssertEqual(transfer.native?.version, 1)
        XCTAssertNil(transfer.native?.snapshots)
        XCTAssertNil(transfer.native?.bonds.first?.draftSnapshotID)
        XCTAssertTrue(try XCTUnwrap(transfer.bonds.first).cashFlows.isEmpty)
    }

    func testDestinationActivationNeverBackfillsAnAlreadyPaidFloatingCoupon() async throws {
        let source = try TestPortfolio.make(); _ = try addFloating(to: source); try source.viewContext.save()
        let files = try BondTransfer.encode(BondTransfer.snapshot(from: source.viewContext))
        let target = try TestPortfolio.make()
        let activation = TestPortfolio.date("2027-01-15T12:00:00Z")
        try await ImportManager().applyBonds(BondTransfer.prepare(bonds: files.bonds, sidecar: files.sidecar),
            into: target, now: activation)
        let reader = target.newBackgroundContext()
        try await reader.perform {
            let imported = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first)
            XCTAssertEqual(imported.eventsActivateAfter, activation)
            XCTAssertTrue(try LaunchEventProcessor.stage(context: reader, since: self.approvedAt,
                until: TestPortfolio.date("2027-01-16T12:00:00Z")).isEmpty)
            XCTAssertEqual(try reader.count(for: HistoricalValuation.fetchRequest()), 0)
        }
    }

    func testFixedOnlyNativeExportRetainsVersionOne() async throws {
        let source = try TestPortfolio.make()
        _ = try TestPortfolio.readyBond(in: source.viewContext, terms: BondTermsFixtures.fixed(), now: approvedAt)
        try source.viewContext.save()
        let files = try BondTransfer.encode(BondTransfer.snapshot(from: source.viewContext))
        let prepared = try BondTransfer.prepare(bonds: files.bonds, sidecar: files.sidecar)
        XCTAssertEqual(prepared.native?.version, 1)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: files.sidecar) as? [String: Any])
        XCTAssertNil(object["snapshots"])
        let target = try TestPortfolio.make()
        try await ImportManager().applyBonds(prepared, into: target, now: importedAt)
        let reader = target.newBackgroundContext()
        try await reader.perform {
            let bond = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first)
            XCTAssertTrue(BondTermsStore.isReady(bond))
            XCTAssertNil(try BondTermsStore.projectionContext(bond))
        }
    }

    func testInvalidVersionTwoSnapshotReferencesRejectBeforeAnyMutation() async throws {
        let source = try TestPortfolio.make(); _ = try addFloating(to: source); try source.viewContext.save()
        let files = try BondTransfer.encode(BondTransfer.snapshot(from: source.viewContext))
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: files.sidecar) as? [String: Any])
        let target = try TestPortfolio.make()
        let retained = TestPortfolio.bond(in: target.viewContext)
        let retainedID = retained.id
        try HistoricalDataRecorder.recordBondAcquisition(bond: retained, context: target.viewContext)
        try target.viewContext.save()
        for mode in ["missing", "extra", "conflicting", "tampered", "valuation", "unknown", "money", "digest", "tenor", "incomplete", "reference", "calibration", "fixing"] {
            var object = original
            var bondsBytes = files.bonds
            var entries = try XCTUnwrap(object["bonds"] as? [[String: Any]])
            var snapshots = try XCTUnwrap(object["snapshots"] as? [String: Any])
            let key = try XCTUnwrap(snapshots.keys.first)
            var market = try XCTUnwrap(snapshots[key] as? [String: Any])
            switch mode {
            case "missing": snapshots = [:]
            case "extra": snapshots["unreferenced"] = market
            case "conflicting": market["id"] = "conflicting"; snapshots[key] = market
            case "tampered":
                var payload = try XCTUnwrap(market["payload"] as? [String: Any])
                var quotes = try XCTUnwrap(payload["quotes"] as? [String: Any])
                quotes["depositRate"] = 0.9; payload["quotes"] = quotes; market["payload"] = payload; snapshots[key] = market
            case "valuation": entries[0]["valuationDay"] = "2026-10-07"
            case "unknown": object["version"] = 999
            case "incomplete": entries[0].removeValue(forKey: "valuationDay")
            case "reference": entries[0]["snapshotID"] = "missing"
            case "tenor":
                var terms = try XCTUnwrap(entries[0]["terms"] as? [String: Any])
                var floating = try XCTUnwrap(terms["floatingTerms"] as? [String: Any])
                floating["indexTenorMonths"] = 6; terms["floatingTerms"] = floating; entries[0]["terms"] = terms
            case "fixing":
                var payload = try XCTUnwrap(market["payload"] as? [String: Any])
                var fixings = try XCTUnwrap(payload["historicalFixings"] as? [[String: Any]])
                fixings[0]["rate"] = 0.026; payload["historicalFixings"] = fixings
                market["payload"] = payload; snapshots[key] = market
            case "calibration":
                var calibration = try XCTUnwrap(market["calibration"] as? [String: Any])
                calibration["maxSwapResidual"] = 1; market["calibration"] = calibration; snapshots[key] = market
            case "digest": object["bondsSHA256"] = "invalid"
            default:
                var rows = try XCTUnwrap(JSONSerialization.jsonObject(with: files.bonds) as? [[String: Any]])
                var flows = try XCTUnwrap(rows[0]["cashFlows"] as? [[String: Any]])
                flows[0]["amount"] = 123.0; rows[0]["cashFlows"] = flows
                bondsBytes = try JSONSerialization.data(withJSONObject: rows)
                object["bondsSHA256"] = BondTransfer.digest(bondsBytes)
            }
            object["bonds"] = entries; object["snapshots"] = snapshots
            let corrupted = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try BondTransfer.prepare(bonds: bondsBytes, sidecar: corrupted), mode)
            let invalid = PreparedBondTransfer(bonds: try BondTransfer.decoder().decode([BondCodable].self, from: bondsBytes),
                bondsBytes: bondsBytes, native: try BondTransfer.decoder().decode(BondTermsEnvelope.self, from: corrupted))
            do {
                try await ImportManager().applyBonds(invalid, into: target, now: importedAt)
                XCTFail("Accepted \(mode) native transfer")
            } catch { }
            let reader = target.newBackgroundContext()
            try await reader.perform {
                XCTAssertEqual(try reader.fetch(BondEntity.fetchRequest()).map(\.id), [retainedID], mode)
                XCTAssertEqual(try reader.count(for: HistoricalValuation.fetchRequest()), 1, mode)
            }
        }
    }
    func testFixedOverrideDropsFloatingContextAndExportsWithoutMarketMetadata() throws {
        let source = try TestPortfolio.make()
        let bond = try addFloating(to: source)
        let market = try XCTUnwrap(BondTermsStore.projectionContext(bond))
        var fixed = try XCTUnwrap(BondTermsStore.read(bond))
        fixed.structure = .fixed; fixed.couponRate = 3; fixed.frequency = 4
        fixed.confirmedFields.insert("structure")
        let trade = try BondTermsStore.trade(bond)
        try BondTermsStore.stageDraft(BondTermsDraft(baseline: BondBaseline.capture(bond), trade: trade,
            legacyDateZone: "UTC", proposed: fixed, previewDay: MarketDay(date: approvedAt), projectionContext: market), for: bond)
        XCTAssertNil(try BondTermsStore.readDraft(bond)?.projectionContext)
        let preview = try BondSchedule.preview(trade: trade, terms: fixed, from: MarketDay(date: approvedAt), context: market)
        XCTAssertTrue(preview.assessment.supported, preview.assessment.reasons.joined())
        try BondTermsStore.replaceProjections(for: bond, terms: fixed, preview: preview, now: approvedAt,
            acquisitionDay: trade.acquisitionDay, legacyDateZone: "UTC", context: source.viewContext, projectionContext: market)
        try source.viewContext.save()
        XCTAssertNil(try BondTermsStore.projectionContext(bond))
        let encoded = try BondTransfer.encode(BondTransfer.snapshot(from: source.viewContext))
        let prepared = try BondTransfer.prepare(bonds: encoded.bonds, sidecar: encoded.sidecar)
        XCTAssertEqual(prepared.native?.version, 1)
        XCTAssertNil(prepared.native?.snapshots)
    }

    func testFixedOverrideCanBeSavedAndAppliedThroughReviewService() async throws {
        let source = try TestPortfolio.make()
        let bond = try addFloating(to: source)
        try source.viewContext.save()
        let review = BondTermsReview(container: source, now: { self.approvedAt })
        try await review.beginManualReview(ids: [bond.id])
        var draft = try XCTUnwrap(review.drafts[bond.id])
        draft.proposed.structure = .fixed; draft.proposed.couponRate = 3; draft.proposed.frequency = 4
        draft.proposed.confirmedFields.insert("structure")
        try await review.edit(draft)
        XCTAssertNil(review.drafts[bond.id]?.projectionContext)
        let applied = try await review.apply(ids: [bond.id])
        XCTAssertEqual(applied.appliedHoldingIDs, [bond.id], applied.failures.description)
    }

}
