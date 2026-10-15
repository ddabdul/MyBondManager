import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class BondTransferTests: XCTestCase {
    private let legacy = Data(#"[{"id":"00000000-0000-0000-0000-000000000001","name":"Example EUR","isin":"DE0000000001","issuer":"Example","depotBank":"Bank","acquisitionDate":"2026-02-01T00:00:00Z","maturityDate":"2027-01-15T00:00:00Z","couponRate":3.375,"parValue":100000,"initialPrice":99000,"yieldToMaturity":4.4,"wkn":"ABC123","cashFlows":[{"date":"2026-07-15T00:00:00Z","amount":1687.5,"nature":"interest"}]}]"#.utf8)
    func testLegacyFixtureKeepsExactKeysAndDoesNotRequireETFFile() throws {
        let prepared = try BondTransfer.prepare(bonds: legacy, sidecar: nil)
        XCTAssertEqual(prepared.bonds.count, 1); XCTAssertNil(prepared.native)
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let array = try XCTUnwrap(JSONSerialization.jsonObject(with: encoder.encode(prepared.bonds)) as? [[String: Any]])
        XCTAssertEqual(Set(array[0].keys), Set(["id","name","isin","issuer","depotBank","acquisitionDate","maturityDate","couponRate","parValue","initialPrice","yieldToMaturity","wkn","cashFlows"]))
        let flows = try XCTUnwrap(array[0]["cashFlows"] as? [[String: Any]])
        XCTAssertEqual(Set(flows[0].keys), Set(["date","amount","nature"]))
        XCTAssertEqual(flows[0]["nature"] as? String, "interest")
        XCTAssertEqual(array[0]["acquisitionDate"] as? String, "2026-02-01T00:00:00Z")
    }
    func testDigestRejectsAnotherExportEvenWhenIdentifiersAreUnchanged() throws {
        let container = try TestPortfolio.make()
        _ = TestPortfolio.bond(in: container.viewContext); try container.viewContext.save()
        let files = try BondTransfer.encode(BondTransfer.snapshot(from: container.viewContext))
        XCTAssertNoThrow(try BondTransfer.prepare(bonds: files.bonds, sidecar: files.sidecar))
        XCTAssertThrowsError(try BondTransfer.prepare(bonds: files.bonds + Data("\n".utf8), sidecar: files.sidecar))
        for bytes in [Data("bad".utf8), Data("{}".utf8)] { XCTAssertThrowsError(try BondTransfer.prepare(bonds: files.bonds, sidecar: bytes)) }
    }
    func testNativeRoundTripKeepsApprovedYieldAndUsesDestinationActivation() async throws {
        let source = try TestPortfolio.make()
        var terms = try BondTermsFixtures.fixed(); terms.redemptionPercent = 105
        let bond = try TestPortfolio.readyBond(in: source.viewContext, terms: terms,
            now: TestPortfolio.date("2026-02-03T12:00:00Z"), nominal: 100000, cost: 100000)
        try source.viewContext.save()
        let expected = try XCTUnwrap(BondTermsStore.estimatedYTM(bond))
        let files = try BondTransfer.encode(BondTransfer.snapshot(from: source.viewContext))
        let prepared = try BondTransfer.prepare(bonds: files.bonds, sidecar: files.sidecar)
        XCTAssertEqual(try XCTUnwrap(prepared.bonds.first).yieldToMaturity, expected, accuracy: 1e-10)
        let target = try TestPortfolio.make(); _ = TestPortfolio.holding(in: target.viewContext); try target.viewContext.save()
        let importedAt = TestPortfolio.date("2026-07-15T12:00:00Z")
        try await ImportManager().applyBonds(prepared, into: target, now: importedAt)
        let reader = target.newBackgroundContext()
        try await reader.perform {
            let imported = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first)
            XCTAssertTrue(BondTermsStore.isReady(imported))
            XCTAssertEqual(imported.yieldToMaturity, expected, accuracy: 1e-10)
            XCTAssertEqual(imported.eventsActivateAfter, importedAt)
            XCTAssertEqual(try reader.count(for: ETFEntity.fetchRequest()), 1)
            XCTAssertTrue(try LaunchEventProcessor.stage(context: reader,
                since: TestPortfolio.date("2026-02-01T00:00:00Z"), until: importedAt).isEmpty)
            XCTAssertEqual(try reader.count(for: HistoricalValuation.fetchRequest()), 0)
        }
    }
    func testLegacyReplacementClearsSameUUIDApprovalAndEmptyImportKeepsETFsAndHistory() async throws {
        let target = try TestPortfolio.make()
        let bond = try TestPortfolio.readyBond(in: target.viewContext, terms: BondTermsFixtures.fixed(), now: TestPortfolio.date("2026-02-03T12:00:00Z"))
        _ = TestPortfolio.holding(in: target.viewContext)
        try HistoricalDataRecorder.recordBondAcquisition(bond: bond, context: target.viewContext)
        try target.viewContext.save()
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        let old = try encoder.encode(ExportManager.snapshot(from: target.viewContext).bonds)
        try await ImportManager().applyBonds(BondTransfer.prepare(bonds: old, sidecar: nil), into: target)
        let reader = target.newBackgroundContext()
        try await reader.perform {
            let stored = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first)
            XCTAssertFalse(BondTermsStore.isReady(stored)); XCTAssertNil(try BondTermsStore.read(stored))
        }
        try await ImportManager().applyBonds(BondTransfer.prepare(bonds: Data("[]".utf8), sidecar: nil), into: target)
        let check = target.newBackgroundContext()
        try await check.perform {
            XCTAssertEqual(try check.count(for: BondEntity.fetchRequest()), 0)
            XCTAssertEqual(try check.count(for: ETFEntity.fetchRequest()), 1)
            XCTAssertEqual(try check.count(for: HistoricalValuation.fetchRequest()), 1)
        }
    }
    func testUnresolvedExportSuppressesOldProjectionsAndPublishesExactlyTwoBondFiles() async throws {
        let source = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: source.viewContext)
        let stale = CashFlowEntity(context: source.viewContext)
        stale.bond = bond; stale.date = bond.maturityDate; stale.amount = 123; stale.nature = "interest"
        try source.viewContext.save()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try await ExportManager().exportBonds(to: root, from: source.viewContext)
        XCTAssertEqual(Set(try FileManager.default.contentsOfDirectory(atPath: folder.path)), Set(["bonds.json","bond-terms.json"]))
        let prepared = try await ImportManager().prepareBonds(from: folder)
        XCTAssertTrue(try XCTUnwrap(prepared.bonds.first).cashFlows.isEmpty)
        XCTAssertEqual(prepared.native?.bonds.count, 1)
    }
    func testRejectsInvalidNativeEntriesAndInconsistentApprovedClaims() throws {
        let source = try TestPortfolio.make()
        _ = try TestPortfolio.readyBond(in: source.viewContext, terms: BondTermsFixtures.fixed(), now: TestPortfolio.date("2026-02-03T12:00:00Z"))
        try source.viewContext.save()
        let files = try BondTransfer.encode(BondTransfer.snapshot(from: source.viewContext))
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: files.sidecar) as? [String: Any])
        for mode in ["version", "duplicate", "missing", "extra", "isin", "zone", "redemption", "currency", "day"] {
            var object = original
            var entries = try XCTUnwrap(object["bonds"] as? [[String: Any]])
            switch mode {
            case "version": object["version"] = 2
            case "duplicate": entries.append(entries[0])
            case "missing": entries = []
            case "extra": var extra = entries[0]; extra["id"] = UUID().uuidString; entries.append(extra)
            case "isin": entries[0]["isin"] = "DE0000000009"
            case "zone": entries[0]["legacyDateZone"] = "Unknown/Zone"
            case "day": entries[0]["acquisitionDay"] = "2026-02-31"
            default:
                var terms = try XCTUnwrap(entries[0]["terms"] as? [String: Any])
                terms[mode == "redemption" ? "redemptionPercent" : "currency"] = mode == "redemption" ? -1 : "USD"
                entries[0]["terms"] = terms
            }
            object["bonds"] = entries
            let sidecar = try JSONSerialization.data(withJSONObject: object)
            XCTAssertThrowsError(try BondTransfer.prepare(bonds: files.bonds, sidecar: sidecar), mode)
        }
        for field in ["couponRate", "initialPrice", "yieldToMaturity"] {
            var bonds = try XCTUnwrap(JSONSerialization.jsonObject(with: files.bonds) as? [[String: Any]])
            bonds[0][field] = 12345
            let bytes = try JSONSerialization.data(withJSONObject: bonds)
            var envelope = original; envelope["bondsSHA256"] = BondTransfer.digest(bytes)
            let sidecar = try JSONSerialization.data(withJSONObject: envelope)
            XCTAssertThrowsError(try BondTransfer.prepare(bonds: bytes, sidecar: sidecar), field)
        }
    }
    func testNativeValidationDetectsProvenanceChangesWithIdenticalLegacyFlows() throws {
        let source = try TestPortfolio.make()
        let now = TestPortfolio.date("2026-02-03T12:00:00Z")
        let bond = try TestPortfolio.readyBond(in: source.viewContext, terms: BondTermsFixtures.fixed(), now: now)
        try source.viewContext.save()
        let files = try BondTransfer.encode(BondTransfer.snapshot(from: source.viewContext))
        let frozen = try BondTransfer.prepare(bonds: files.bonds, sidecar: files.sidecar)
        var terms = try XCTUnwrap(BondTermsStore.read(bond)); terms.conventions.sources["calendar"] = .confirmed
        let preview = try BondSchedule.preview(trade: BondTermsStore.trade(bond), terms: terms, from: MarketDay(date: now))
        try BondTermsStore.replaceProjections(for: bond, terms: terms, preview: preview, now: now,
            acquisitionDay: MarketDay("2026-02-01"), legacyDateZone: "Europe/Berlin", context: source.viewContext)
        try source.viewContext.save()
        XCTAssertFalse(try PositionsTransferValidation.bondIssues(frozen, context: source.viewContext).isEmpty)
    }
    func testDestinationLegacyKeysAreCapturedBeforeNativeReplacement() async throws {
        let source = try TestPortfolio.make()
        var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2027-01-01", next: "2027-01-01")
        terms.accrualStart = try MarketDay("2026-01-01")
        let sourceBond = try TestPortfolio.readyBond(in: source.viewContext, terms: terms, now: TestPortfolio.date("2026-12-30T12:00:00Z"))
        try source.viewContext.save()
        let files = try BondTransfer.encode(BondTransfer.snapshot(from: source.viewContext))
        let target = try TestPortfolio.make()
        let old = TestPortfolio.bond(in: target.viewContext, cost: 900); old.id = sourceBond.id
        old.acquisitionDate = TestPortfolio.date("2026-02-01T00:00:00Z")
        let history = try HistoricalDataRecorder.recordChange(assetType: .bond, depotBank: old.depotBank,
            investedDelta: -1000, interestDelta: 0, gainsDelta: 100, date: old.maturityDate, context: target.viewContext)
        history.eventKey = "\(old.id)|maturity|\(Int(old.maturityDate.timeIntervalSince1970))"
        try target.viewContext.save()
        let frozen = try BondTransfer.prepare(bonds: files.bonds, sidecar: files.sidecar)
        try await ImportManager().applyBonds(frozen, into: target, now: TestPortfolio.date("2027-01-02T12:00:00Z"))
        let reader = target.newBackgroundContext()
        try await reader.perform {
            let messages = try LaunchEventProcessor.stage(context: reader,
                since: TestPortfolio.date("2027-01-02T00:00:00Z"), until: TestPortfolio.date("2027-01-05T00:00:00Z"))
            XCTAssertEqual(messages.count, 1) // only the previously unrecorded final coupon
            XCTAssertEqual(try reader.count(for: HistoricalValuation.fetchRequest()), 2)
        }
    }
    func testZeroCallableAndUnsupportedDraftsRoundTripWithoutNetwork() async throws {
        let source = try TestPortfolio.make()
        for zero in [true, false] {
            var terms = try BondTermsFixtures.fixed(); terms.callable = true
            if zero { terms.structure = .zero; terms.couponRate = 0 }
            _ = try TestPortfolio.readyBond(in: source.viewContext, terms: terms, now: TestPortfolio.date("2026-02-03T12:00:00Z"))
        }
        let unresolved = TestPortfolio.bond(in: source.viewContext)
        var terms = try BondTermsFixtures.fixed(); terms.structure = .unknown; terms.restrictions = ["floating"]
        try BondTermsStore.stageDraft(BondTermsDraft(baseline: BondBaseline.capture(unresolved), trade: BondTermsStore.trade(unresolved),
            legacyDateZone: TimeZone.current.identifier, proposed: terms, previewDay: MarketDay("2026-02-03")), for: unresolved)
        try source.viewContext.save()
        let files = try BondTransfer.encode(BondTransfer.snapshot(from: source.viewContext))
        let frozen = try BondTransfer.prepare(bonds: files.bonds, sidecar: files.sidecar)
        let target = try TestPortfolio.make()
        try await ImportManager().applyBonds(frozen, into: target, now: TestPortfolio.date("2026-02-04T12:00:00Z"))
        let reader = target.newBackgroundContext()
        try await reader.perform {
            let bonds = try reader.fetch(BondEntity.fetchRequest())
            XCTAssertEqual(bonds.count, 3); XCTAssertEqual(bonds.filter { BondTermsStore.isReady($0) }.count, 2)
            let draft = try XCTUnwrap(bonds.first { !BondTermsStore.isReady($0) })
            XCTAssertEqual(try BondTermsStore.readDraft(draft)?.proposed.restrictions, ["floating"])
        }
    }
    func testNativeSaveFailureRollsBackBondsTermsAndKeepsDestinationHistoryAndETF() async throws {
        let source = try TestPortfolio.make()
        for _ in 0..<2 { _ = try TestPortfolio.readyBond(in: source.viewContext, terms: BondTermsFixtures.fixed(), now: TestPortfolio.date("2026-02-03T12:00:00Z")) }
        try source.viewContext.save()
        let files = try BondTransfer.encode(BondTransfer.snapshot(from: source.viewContext))
        let frozen = try BondTransfer.prepare(bonds: files.bonds, sidecar: files.sidecar)
        let target = try TestPortfolio.make()
        let old = TestPortfolio.bond(in: target.viewContext)
        try HistoricalDataRecorder.recordBondAcquisition(bond: old, context: target.viewContext)
        _ = TestPortfolio.holding(in: target.viewContext); try target.viewContext.save()
        let coordinator = target.persistentStoreCoordinator, failedID = frozen.bonds[1].id
        let token = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextWillSave, object: nil, queue: nil) { notification in
            guard let context = notification.object as? NSManagedObjectContext,
                  context.persistentStoreCoordinator === coordinator, context.concurrencyType == .privateQueueConcurrencyType else { return }
            for case let bond as BondEntity in context.insertedObjects where bond.id == failedID { bond.setValue(nil, forKey: "name") }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        do { try await ImportManager().applyBonds(frozen, into: target); XCTFail("Expected save failure") } catch {}
        let reader = target.newBackgroundContext()
        try await reader.perform {
            let bonds = try reader.fetch(BondEntity.fetchRequest())
            XCTAssertEqual(bonds.count, 1); XCTAssertNil(try BondTermsStore.read(XCTUnwrap(bonds.first)))
            XCTAssertEqual(try reader.count(for: ETFEntity.fetchRequest()), 1)
            XCTAssertEqual(try reader.count(for: HistoricalValuation.fetchRequest()), 1)
        }
    }
    func testPresentInvalidSidecarCannotFallBackAndPreparedPayloadIsFrozen() async throws {
        let source = try TestPortfolio.make(); _ = TestPortfolio.bond(in: source.viewContext); try source.viewContext.save()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try await ExportManager().exportBonds(to: root, from: source.viewContext)
        let frozen = try await ImportManager().prepareBonds(from: folder)
        try Data("[]".utf8).write(to: folder.appendingPathComponent("bonds.json"))
        try Data("broken sidecar".utf8).write(to: folder.appendingPathComponent("bond-terms.json"))
        do { _ = try await ImportManager().prepareBonds(from: folder); XCTFail("Expected complete rejection") } catch {}
        let target = try TestPortfolio.make()
        try await ImportManager().applyBonds(frozen, into: target)
        let reader = target.newBackgroundContext()
        let count = try await reader.perform { try reader.count(for: BondEntity.fetchRequest()) }
        XCTAssertEqual(count, 1)
    }
    func testFailedSidecarWritePublishesNothingAndKeepsPreviousExport() async throws {
        let source = try TestPortfolio.make()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let previous = try await ExportManager().exportBonds(to: root, from: source.viewContext)
        let original = try Data(contentsOf: previous.appendingPathComponent("bonds.json"))
        let exporter = ExportManager(write: { data, url in
            if url.lastPathComponent == "bond-terms.json" { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: url)
        })
        do { _ = try await exporter.exportBonds(to: root, from: source.viewContext); XCTFail("Expected write failure") } catch {}
        XCTAssertEqual(try Data(contentsOf: previous.appendingPathComponent("bonds.json")), original)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path).count, 1)
    }
}
