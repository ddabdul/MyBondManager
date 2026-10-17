import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class BondTermsReviewTests: XCTestCase {
    private func review(_ container: NSPersistentContainer, now: @escaping () -> Date = { TestPortfolio.date("2026-02-03T12:00:00Z") }) -> BondTermsReview {
        BondTermsReview(container: container, fetch: { _ in try BondTermsFixtures.details() }, now: now)
    }
    func testLongFirstCouponAppliesPerISINSurvivesNativeTransferAndRecordsProratedReceiptOnce() async throws {
        let container = try TestPortfolio.make()
        let now = TestPortfolio.date("2026-10-16T12:00:00Z")
        var terms = try BondTermsFixtures.fixed(frequency: 2, maturity: "2031-05-31", next: "2026-11-30")
        terms.isin = "XS3350943018"; terms.couponRate = 6.875
        terms.accrualStart = try MarketDay("2026-05-13"); terms.checkpointObservedOn = MarketDay(date: now)
        let confirmed = terms
        var ids: [UUID] = []
        for _ in 0..<2 {
            let bond = TestPortfolio.bond(in: container.viewContext, cost: 99000, par: 100000)
            bond.isin = terms.isin; bond.acquisitionDate = TestPortfolio.date("2026-05-13T12:00:00Z")
            ids.append(bond.id)
        }
        try container.viewContext.save()
        let service = BondTermsReview(container: container, fetch: { _ in
            BondDetails(name: "Monnet", wkn: "Fixture", issuer: "Fixture", maturityDate: confirmed.maturity?.instant,
                couponRate: confirmed.couponRate, terms: confirmed)
        }, now: { now })
        await service.collect(ids: [ids[0]])
        var edited = try XCTUnwrap(service.drafts[ids[0]])
        XCTAssertNil(edited.proposed.firstCoupon)
        edited.proposed.firstCoupon = try MarketDay("2026-11-30")
        edited.proposed.confirmedFields.insert("firstCoupon")
        try await service.edit(edited)
        await service.collect(ids: [ids[0]])
        XCTAssertEqual(service.drafts[ids[1]]?.proposed.firstCoupon?.rawValue, "2026-11-30")
        let report = try await service.apply(ids: [ids[0]])
        XCTAssertEqual(report.appliedHoldingIDs, Set(ids))
        XCTAssertTrue(report.failures.isEmpty)
        let reader = container.newBackgroundContext()
        let snapshot = try await reader.perform { try BondTransfer.snapshot(from: reader) }
        let files = try BondTransfer.encode(snapshot)
        let transfer = try BondTransfer.prepare(bonds: files.bonds, sidecar: files.sidecar)
        let target = try TestPortfolio.make()
        let importedAt = TestPortfolio.date("2026-10-17T12:00:00Z")
        try await ImportManager().applyBonds(transfer, into: target, now: importedAt)
        let targetReader = target.newBackgroundContext()
        try await targetReader.perform {
            for bond in try targetReader.fetch(BondEntity.fetchRequest()) {
                XCTAssertTrue(BondTermsStore.isReady(bond))
                XCTAssertEqual(try BondTermsStore.read(bond)?.firstCoupon?.rawValue, "2026-11-30")
            }
            let until = TestPortfolio.date("2026-12-01T12:00:00Z")
            XCTAssertEqual(try LaunchEventProcessor.stage(context: targetReader, since: importedAt, until: until).count, 2)
            let rows = try targetReader.fetch(HistoricalValuation.fetchRequest())
            XCTAssertEqual(rows.count, 2)
            XCTAssertEqual(rows.reduce(0) { $0 + ($1.interestReceived?.doubleValue ?? 0) }, 7554.945054945055, accuracy: 0.0000001)
            XCTAssertTrue(try LaunchEventProcessor.stage(context: targetReader, since: importedAt, until: until).isEmpty)
        }
    }
    func testConfirmedFixedOverrideSurvivesRefreshAndApprovesEveryPurchaseWithWarning() async throws {
        let container = try TestPortfolio.make()
        let first = TestPortfolio.bond(in: container.viewContext)
        let second = TestPortfolio.bond(in: container.viewContext)
        try container.viewContext.save()
        let service = BondTermsReview(container: container, fetch: { _ in
            var terms = try BondTermsFixtures.fixed(); terms.structure = .floating
            terms.rawStructure = "Variabel"; terms.restrictions = ["floating"]
            return BondDetails(name: "Fixture", wkn: "TEST01", issuer: "Issuer", maturityDate: terms.maturity?.instant, couponRate: terms.couponRate, terms: terms)
        }, now: { TestPortfolio.date("2026-02-03T12:00:00Z") })
        await service.collect(ids: [first.id])
        var draft = try XCTUnwrap(service.drafts[first.id])
        draft.proposed.structure = .fixed; draft.proposed.confirmedFields.insert("structure")
        try await service.edit(draft)
        await service.collect(ids: [first.id])
        let preview = try service.preview(XCTUnwrap(service.drafts[second.id]))
        XCTAssertTrue(preview.assessment.supported, preview.assessment.reasons.joined())
        XCTAssertTrue(preview.assessment.warnings.contains { $0.contains("constant") })
        let report = try await service.apply(ids: [first.id])
        XCTAssertEqual(report.appliedHoldingIDs, [first.id, second.id])
        XCTAssertTrue(report.failures.isEmpty)
        let reader = container.newBackgroundContext()
        try await reader.perform {
            for bond in try reader.fetch(BondEntity.fetchRequest()) {
                XCTAssertTrue(BondTermsStore.isReady(bond))
                let terms = try XCTUnwrap(BondTermsStore.read(bond))
                XCTAssertEqual(terms.structure, .fixed)
                XCTAssertEqual(terms.rawStructure, "Variabel")
                XCTAssertTrue(terms.restrictions.contains("floating"))
                XCTAssertTrue(terms.confirmedFields.contains("structure"))
            }
        }
    }
    func testRefreshPreservesConfirmedDeferralAndFloatingStart() async throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext)
        try container.viewContext.save()
        let service = review(container)
        await service.collect(ids: [bond.id])
        var draft = try XCTUnwrap(service.drafts[bond.id])
        draft.proposed.interestDeferral = false
        draft.proposed.floatingStart = try MarketDay("2028-01-15")
        draft.proposed.confirmedFields.formUnion(["interestDeferral", "floatingStart"])
        try await service.edit(draft)
        await service.collect(ids: [bond.id])
        XCTAssertEqual(service.drafts[bond.id]?.proposed.interestDeferral, false)
        XCTAssertEqual(service.drafts[bond.id]?.proposed.floatingStart?.rawValue, "2028-01-15")
    }
    func testHistoricalOpeningPeriodsApproveTransferAndRecordOnlyFutureRegularCoupons() async throws {
        let source = try TestPortfolio.make()
        var supplied: [String: BondTerms] = [:]
        var ids: [UUID] = []
        for (isin, start, issue, maturity, next) in [
            ("BE6350792089", "2024-04-03", "2024-04-03", "2031-10-03", "2027-10-03"),
            ("DE0001135325", "2007-01-26", "2023-03-03", "2039-07-04", "2027-07-04"),
            ("EU000A1G30R0", "2012-04-24", "2012-04-24", "2038-04-04", "2027-04-04")
        ] {
            let bond = TestPortfolio.bond(in: source.viewContext, cost: 1000, par: 1000)
            bond.isin = isin; ids.append(bond.id)
            try HistoricalDataRecorder.recordBondAcquisition(bond: bond, context: source.viewContext)
            var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: maturity, next: next)
            terms.isin = isin; terms.accrualStart = try MarketDay(start); terms.issueDay = try MarketDay(issue)
            terms.checkpointObservedOn = try MarketDay("2026-10-16")
            supplied[isin] = terms
        }
        try source.viewContext.save()
        let fixtures = supplied
        let approvedAt = TestPortfolio.date("2026-10-16T12:00:00Z")
        let service = BondTermsReview(container: source, fetch: { isin in
            let terms = try XCTUnwrap(fixtures[isin])
            return BondDetails(name: "Fixture", wkn: "TEST01", issuer: "Fixture", maturityDate: terms.maturity?.instant,
                couponRate: terms.couponRate, terms: terms)
        }, now: { approvedAt })
        await service.collect(ids: ids)
        let report = try await service.apply(ids: ids)
        XCTAssertEqual(report.appliedISINs, Set(["BE6350792089", "DE0001135325", "EU000A1G30R0"]))
        XCTAssertTrue(report.failures.isEmpty)
        let reader = source.newBackgroundContext()
        let snapshot = try await reader.perform {
            XCTAssertEqual(try reader.count(for: HistoricalValuation.fetchRequest()), 3)
            for bond in try reader.fetch(BondEntity.fetchRequest()) {
                XCTAssertEqual(try BondTermsStore.read(bond)?.accrualStart, fixtures[bond.isin]?.accrualStart)
                XCTAssertEqual(try BondTermsStore.read(bond)?.issueDay, fixtures[bond.isin]?.issueDay)
                XCTAssertTrue(BondTermsStore.isReady(bond))
            }
            return try BondTransfer.snapshot(from: reader)
        }
        let files = try BondTransfer.encode(snapshot)
        let transfer = try BondTransfer.prepare(bonds: files.bonds, sidecar: files.sidecar)
        let target = try TestPortfolio.make()
        let importedAt = TestPortfolio.date("2026-10-17T12:00:00Z")
        try await ImportManager().applyBonds(transfer, into: target, now: importedAt)
        let targetReader = target.newBackgroundContext()
        try await targetReader.perform {
            XCTAssertTrue(try targetReader.fetch(BondEntity.fetchRequest()).allSatisfy(BondTermsStore.isReady))
            XCTAssertEqual(try targetReader.count(for: HistoricalValuation.fetchRequest()), 0)
            let until = TestPortfolio.date("2027-10-05T12:00:00Z")
            XCTAssertEqual(try LaunchEventProcessor.stage(context: targetReader, since: importedAt, until: until).count, 3)
            let rows = try targetReader.fetch(HistoricalValuation.fetchRequest())
            XCTAssertEqual(rows.count, 3)
            XCTAssertEqual(rows.reduce(0) { $0 + ($1.interestReceived?.doubleValue ?? 0) }, 101.25, accuracy: 0.00001)
            XCTAssertTrue(rows.allSatisfy { $0.date > importedAt })
            XCTAssertTrue(try LaunchEventProcessor.stage(context: targetReader, since: importedAt, until: until).isEmpty)
        }
    }
    func testRepeatedClipboardISINCollectsAndApprovesWithoutChangingStoredIdentityOrHistory() async throws {
        for isin in ["EU000A2SCAK5", "FR001400P1Y4"] {
            let container = try TestPortfolio.make()
            let bond = TestPortfolio.bond(in: container.viewContext)
            let original = isin + "\n" + isin; bond.isin = original
            try HistoricalDataRecorder.recordBondAcquisition(bond: bond, context: container.viewContext)
            try container.viewContext.save()
            let id = bond.id
            let service = BondTermsReview(container: container, fetch: { requested in
                guard requested == isin else { throw PortfolioError("Expected a single clean ISIN") }
                var terms = try BondTermsFixtures.fixed(); terms.isin = isin
                return BondDetails(name: "Fixture", wkn: "TEST01", issuer: "Fixture", maturityDate: terms.maturity?.instant, couponRate: terms.couponRate, terms: terms)
            }, now: { TestPortfolio.date("2026-02-03T12:00:00Z") })
            await service.collect(ids: [id])
            XCTAssertNotNil(service.drafts[id])
            let report = try await service.apply(ids: [id])
            XCTAssertEqual(report.appliedISINs, [isin])
            let reader = container.newBackgroundContext()
            try await reader.perform {
                let stored = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first)
                XCTAssertEqual(stored.isin, original)
                XCTAssertTrue(BondTermsStore.isReady(stored))
                XCTAssertEqual(try reader.count(for: HistoricalValuation.fetchRequest()), 1)
            }
        }
    }
    func testApplyingAnISINUsesItsSavedSiblingDraftWhenSelectedPurchaseHasNone() async throws {
        let container = try TestPortfolio.make()
        let first = TestPortfolio.bond(in: container.viewContext)
        let second = TestPortfolio.bond(in: container.viewContext)
        let draft = try BondTermsDraft(baseline: BondBaseline.capture(second), trade: BondTermsStore.trade(second),
            legacyDateZone: "Europe/Berlin", proposed: BondTermsFixtures.fixed(), previewDay: MarketDay("2026-02-03"))
        try BondTermsStore.stageDraft(draft, for: second); try container.viewContext.save()
        let service = review(container); try await service.load()
        let report = try await service.apply(ids: [first.id])
        XCTAssertEqual(report.appliedHoldingIDs, [first.id, second.id])
    }
    func testMissingDraftReportsTheActualCollectionFailure() async throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext); try container.viewContext.save()
        let service = BondTermsReview(container: container, fetch: { _ in throw PortfolioError("ING HTTP 503") })
        await service.collect(ids: [bond.id])
        do { try await service.apply(ids: [bond.id]); XCTFail("Expected collection failure") }
        catch { XCTAssertTrue(error.localizedDescription.contains("ING HTTP 503")) }
    }
    func testReuseAndNewPurchaseCannotSpreadAnApprovalThatOmitsCollectedSafeguards() async throws {
        for safety in ["deferral", "floating"] {
            let container = try TestPortfolio.make()
            let old = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: TestPortfolio.date("2026-02-02T12:00:00Z"))
            let sibling = TestPortfolio.bond(in: container.viewContext)
            let oldID = old.id, siblingID = sibling.id
            try container.viewContext.save()
            let service = BondTermsReview(container: container, fetch: { _ in
                var terms = try BondTermsFixtures.fixed()
                if safety == "deferral" { terms.interestDeferral = true }
                else { terms.structure = .fixedToFloating; terms.restrictions = ["fixed-to-floating"] }
                return BondDetails(name: "Fixture", wkn: "TEST01", issuer: "Fixture", maturityDate: terms.maturity?.instant, couponRate: terms.couponRate, terms: terms)
            }, now: { TestPortfolio.date("2026-02-03T12:00:00Z") })
            await service.collect(ids: [oldID])
            do { try await service.reuseApproved(ids: [siblingID]); XCTFail("A stale approval cannot waive newly collected safeguards") } catch {}
            XCTAssertNotNil(service.drafts[oldID]); XCTAssertNotNil(service.drafts[siblingID])
            let incoming = try TestPortfolio.make()
            _ = TestPortfolio.bond(in: incoming.viewContext, cost: 990)
            let newValues = try XCTUnwrap(ExportManager.snapshot(from: incoming.viewContext).bonds.first)
            _ = try await service.saveNew(values: newValues, terms: BondTerms(), legacyDateZone: "Europe/Berlin")
            let reader = container.newBackgroundContext()
            try await reader.perform {
                let bonds = try reader.fetch(BondEntity.fetchRequest())
                let existingSibling = try XCTUnwrap(bonds.first { $0.id == siblingID })
                let newPurchase = try XCTUnwrap(bonds.first { $0.id == newValues.id })
                XCTAssertFalse(BondTermsStore.isReady(existingSibling)); XCTAssertFalse(BondTermsStore.isReady(newPurchase))
                let draft = try XCTUnwrap(BondTermsStore.readDraft(existingSibling))
                if safety == "deferral" { XCTAssertEqual(draft.proposed.interestDeferral, true) }
                else { XCTAssertEqual(draft.proposed.structure, .fixedToFloating) }
            }
        }
    }
    func testManualEntryCannotEraseCollectedFirstCouponOrDeferralSafeguards() async throws {
        let container = try TestPortfolio.make()
        let first = TestPortfolio.bond(in: container.viewContext)
        let second = TestPortfolio.bond(in: container.viewContext)
        var terms = try BondTermsFixtures.fixed()
        terms.firstCoupon = try MarketDay("2026-07-15"); terms.interestDeferral = true
        terms.verifiedTermsSource = "https://example.com/issuer-terms"
        let prior = try BondTermsDraft(baseline: BondBaseline.capture(first), trade: BondTermsStore.trade(first),
            legacyDateZone: "Europe/Berlin", proposed: terms, previewDay: MarketDay("2026-02-03"))
        try BondTermsStore.stageDraft(prior, for: first); try container.viewContext.save()
        let service = review(container)
        try await service.beginManualReview(ids: [second.id])
        XCTAssertEqual(service.drafts[first.id]?.proposed.interestDeferral, true)
        XCTAssertEqual(service.drafts[first.id]?.proposed.firstCoupon?.rawValue, "2026-07-15")
        var manual = try XCTUnwrap(service.drafts[second.id]); manual.proposed = try BondTermsFixtures.fixed()
        try await service.edit(manual)
        for id in [first.id, second.id] {
            XCTAssertEqual(service.drafts[id]?.proposed.interestDeferral, true)
            XCTAssertEqual(service.drafts[id]?.proposed.firstCoupon?.rawValue, "2026-07-15")
        }
    }
    func testApprovalOncePerISINUpdatesEveryPurchaseWithItsOwnYieldAndPayments() async throws {
        let container = try TestPortfolio.make()
        let first = TestPortfolio.bond(in: container.viewContext, cost: 900, par: 1000)
        let second = TestPortfolio.bond(in: container.viewContext, cost: 1950, par: 2000)
        second.acquisitionDate = TestPortfolio.date("2025-03-18T00:00:00Z")
        let unrelated = TestPortfolio.bond(in: container.viewContext); unrelated.isin = "DE0000000003"
        try container.viewContext.save()
        let ids = [first.id, second.id]
        let service = review(container)
        await service.collect(ids: [first.id])
        XCTAssertNotNil(service.drafts[second.id], "Collect once for the whole instrument")
        try await service.apply(ids: [first.id])
        let reader = container.newBackgroundContext()
        try await reader.perform {
            let bonds = try reader.fetch(BondEntity.fetchRequest())
            let purchases = bonds.filter { ids.contains($0.id) }
            XCTAssertTrue(purchases.allSatisfy(BondTermsStore.isReady))
            XCTAssertNotEqual(purchases[0].yieldToMaturity, purchases[1].yieldToMaturity)
            XCTAssertEqual(purchases.first { $0.id == ids[1] }?.initialPrice, 1950)
            XCTAssertEqual(purchases.first { $0.id == ids[1] }?.acquisitionDate, TestPortfolio.date("2025-03-18T00:00:00Z"))
            for bond in purchases {
                let payments = try BondTermsStore.projectedPayments(bond, from: MarketDay("2026-02-03"))
                XCTAssertEqual(payments.first { $0.kind == .interest }?.amount, bond.parValue * 3.375 / 200)
            }
            XCTAssertFalse(bonds.first { $0.isin == "DE0000000003" }!.termsReady)
            XCTAssertEqual(try reader.count(for: HistoricalValuation.fetchRequest()), 0)
        }
        XCTAssertTrue(service.drafts.isEmpty)
    }
    func testExistingInstrumentApprovalIsExplicitlyReusedWithoutFetchingOrRewritingHistory() async throws {
        let container = try TestPortfolio.make()
        _ = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: TestPortfolio.date("2026-02-02T12:00:00Z"))
        let second = TestPortfolio.bond(in: container.viewContext, cost: 990)
        let id = second.id
        try HistoricalDataRecorder.recordBondAcquisition(bond: second, context: container.viewContext)
        try container.viewContext.save()
        let service = BondTermsReview(container: container, fetch: { _ in throw PortfolioError("Must not fetch") }, now: { TestPortfolio.date("2026-02-03T12:00:00Z") })
        try await service.load()
        let before = container.newBackgroundContext()
        let wasReady = try await before.perform { try before.fetch(BondEntity.fetchRequest()).first { $0.id == id }?.termsReady }
        XCTAssertEqual(wasReady, false, "Opening review alone must not apply approvals")
        try await service.reuseApproved(ids: [id])
        let reader = container.newBackgroundContext()
        try await reader.perform {
            let second = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first { $0.id == id })
            XCTAssertTrue(BondTermsStore.isReady(second))
            XCTAssertEqual(second.initialPrice, 990)
            XCTAssertEqual(second.eventsActivateAfter, TestPortfolio.date("2026-02-03T12:00:00Z"))
            XCTAssertEqual(try reader.count(for: HistoricalValuation.fetchRequest()), 1)
        }
    }
    func testSoleInstrumentApprovalSurvivesTradeEditForExplicitReuse() async throws {
        for nominal in [1000.0, 2000.0] {
            let container = try TestPortfolio.make()
            let approvedAt = TestPortfolio.date("2026-02-02T12:00:00Z")
            let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: approvedAt)
            try container.viewContext.save()
            let id = bond.id
            let values = BondCodable(id: id, name: bond.name, isin: bond.isin, issuer: bond.issuer,
                depotBank: bond.depotBank, acquisitionDate: bond.acquisitionDate, maturityDate: bond.maturityDate,
                couponRate: bond.couponRate, parValue: nominal, initialPrice: 950,
                yieldToMaturity: bond.yieldToMaturity, wkn: bond.wkn, cashFlows: [])
            try await EditBondView.persistChanges(bondID: bond.objectID, values: values, in: container)
            let before = container.newBackgroundContext()
            try await before.perform {
                let stored = try XCTUnwrap(before.fetch(BondEntity.fetchRequest()).first)
                XCTAssertFalse(BondTermsStore.isReady(stored))
                XCTAssertEqual(try BondTermsStore.read(stored)?.approvedAt, approvedAt)
            }
            try await review(container).reuseApproved(ids: [id])
            let reader = container.newBackgroundContext()
            try await reader.perform {
                let stored = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first)
                XCTAssertTrue(BondTermsStore.isReady(stored))
                XCTAssertEqual(stored.initialPrice, 950); XCTAssertEqual(stored.parValue, nominal)
                XCTAssertEqual(try BondTermsStore.read(stored)?.approvedAt, approvedAt)
                XCTAssertEqual(try reader.count(for: HistoricalValuation.fetchRequest()), 0)
            }
        }
    }
    func testInstrumentChangeCannotReuseTheOldApproval() async throws {
        for field in ["isin", "coupon", "maturity"] {
            let container = try TestPortfolio.make()
            let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: TestPortfolio.date("2026-02-02T12:00:00Z"))
            try container.viewContext.save()
            let id = bond.id
            let values = BondCodable(id: id, name: bond.name, isin: field == "isin" ? "DE0000000003" : bond.isin,
                issuer: bond.issuer, depotBank: bond.depotBank, acquisitionDate: bond.acquisitionDate,
                maturityDate: field == "maturity" ? TestPortfolio.date("2028-01-15T00:00:00Z") : bond.maturityDate,
                couponRate: field == "coupon" ? 7 : bond.couponRate, parValue: bond.parValue,
                initialPrice: bond.initialPrice, yieldToMaturity: bond.yieldToMaturity, wkn: bond.wkn, cashFlows: [])
            try await EditBondView.persistChanges(bondID: bond.objectID, values: values, in: container)
            do { try await review(container).reuseApproved(ids: [id]); XCTFail("Changed instrument terms need a fresh approval") } catch {}
            let reader = container.newBackgroundContext()
            try await reader.perform {
                let stored = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first)
                XCTAssertNil(try BondTermsStore.read(stored)); XCTAssertFalse(BondTermsStore.isReady(stored))
            }
        }
    }
    func testNewPurchaseReusesApprovalAfterSoleSourceTradeEdit() async throws {
        let container = try TestPortfolio.make()
        let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: TestPortfolio.date("2026-02-02T12:00:00Z"))
        try container.viewContext.save()
        let sourceID = bond.id
        let values = BondCodable(id: bond.id, name: bond.name, isin: bond.isin, issuer: bond.issuer,
            depotBank: bond.depotBank, acquisitionDate: bond.acquisitionDate, maturityDate: bond.maturityDate,
            couponRate: bond.couponRate, parValue: bond.parValue, initialPrice: 950,
            yieldToMaturity: bond.yieldToMaturity, wkn: bond.wkn, cashFlows: [])
        try await EditBondView.persistChanges(bondID: bond.objectID, values: values, in: container)
        let incoming = try TestPortfolio.make()
        _ = TestPortfolio.bond(in: incoming.viewContext, cost: 990)
        let newValues = try XCTUnwrap(ExportManager.snapshot(from: incoming.viewContext).bonds.first)
        _ = try await review(container).saveNew(values: newValues, terms: BondTerms(), legacyDateZone: "Europe/Berlin")
        let reader = container.newBackgroundContext()
        try await reader.perform {
            let bonds = try reader.fetch(BondEntity.fetchRequest())
            XCTAssertTrue(BondTermsStore.isReady(try XCTUnwrap(bonds.first { $0.id == newValues.id })))
            XCTAssertFalse(BondTermsStore.isReady(try XCTUnwrap(bonds.first { $0.id == sourceID })), "Saving a new purchase must not rebuild another purchase implicitly")
        }
    }
    func testNewPurchaseReusesAnAlreadyApprovedISIN() async throws {
        let container = try TestPortfolio.make()
        _ = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: TestPortfolio.date("2026-02-02T12:00:00Z"))
        try container.viewContext.save()
        let incoming = try TestPortfolio.make()
        _ = TestPortfolio.bond(in: incoming.viewContext, cost: 990)
        let values = try XCTUnwrap(ExportManager.snapshot(from: incoming.viewContext).bonds.first)
        _ = try await review(container).saveNew(values: values, terms: BondTerms(), legacyDateZone: "Europe/Berlin")
        let reader = container.newBackgroundContext()
        try await reader.perform {
            let bond = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first { $0.id == values.id })
            XCTAssertTrue(BondTermsStore.isReady(bond))
            XCTAssertEqual(bond.initialPrice, 990)
            XCTAssertEqual(try reader.count(for: HistoricalValuation.fetchRequest()), 1)
        }
    }
    func testBulkApprovalKeepsSuccessfulISINWhenAnotherInstrumentIsIncomplete() async throws {
        let container = try TestPortfolio.make()
        let good = TestPortfolio.bond(in: container.viewContext)
        let bad = TestPortfolio.bond(in: container.viewContext); bad.isin = "DE0000000003"
        let goodID = good.id, badID = bad.id
        try container.viewContext.save()
        let service = BondTermsReview(container: container, fetch: { isin in
            var terms = try BondTermsFixtures.fixed(); terms.isin = isin
            if isin == "DE0000000003" { terms.frequency = nil }
            return BondDetails(name: "Fixture", wkn: "TEST01", issuer: "Issuer", maturityDate: terms.maturity?.instant, couponRate: terms.couponRate, terms: terms)
        }, now: { TestPortfolio.date("2026-02-03T12:00:00Z") })
        await service.collect(ids: [goodID, badID])
        do { try await service.apply(ids: [goodID, badID]) } catch { XCTFail("An incomplete ISIN must not roll back successful instruments: \(error)") }
        let reader = container.newBackgroundContext()
        try await reader.perform {
            let bonds = try reader.fetch(BondEntity.fetchRequest())
            XCTAssertTrue(BondTermsStore.isReady(try XCTUnwrap(bonds.first { $0.id == goodID })))
            XCTAssertFalse(BondTermsStore.isReady(try XCTUnwrap(bonds.first { $0.id == badID })))
        }
        XCTAssertNil(service.drafts[goodID]); XCTAssertNotNil(service.drafts[badID])
        XCTAssertNotNil(service.errors["DE0000000003"])
    }
    func testConflictingSiblingDraftRequiresExplicitSharedEditBeforeApproval() async throws {
        let container = try TestPortfolio.make()
        let first = TestPortfolio.bond(in: container.viewContext)
        let second = TestPortfolio.bond(in: container.viewContext)
        try container.viewContext.save()
        let service = review(container)
        await service.collect(ids: [first.id])
        var sibling = try XCTUnwrap(service.drafts[second.id])
        sibling.proposed.couponRate = 7
        sibling.proposed.confirmedFields.insert("couponRate")
        try BondTermsStore.stageDraft(sibling, for: second)
        try container.viewContext.save()
        try await service.load()
        do { try await service.apply(ids: [first.id]); XCTFail("Conflicting sibling draft must remain for review") } catch {}
        XCTAssertEqual(service.drafts[second.id]?.proposed.couponRate, 7)
        XCTAssertNotNil(service.lastApplyReport?.failures[first.isin])
        let chosen = try XCTUnwrap(service.drafts[first.id])
        try await service.edit(chosen)
        try await service.apply(ids: [first.id])
        XCTAssertTrue(service.drafts.isEmpty)
    }
    func testSharedDraftEditsApplyToAllPurchases() async throws {
        let container = try TestPortfolio.make()
        let first = TestPortfolio.bond(in: container.viewContext)
        let second = TestPortfolio.bond(in: container.viewContext)
        let ids = [first.id, second.id]
        try container.viewContext.save()
        let service = review(container); await service.collect(ids: [first.id])
        var draft = try XCTUnwrap(service.drafts[first.id]); draft.proposed.couponRate = 4.5
        draft.proposed.confirmedFields.insert("couponRate")
        try await service.edit(draft)
        XCTAssertEqual(service.drafts[second.id]?.proposed.couponRate, 4.5)
        try await service.apply(ids: [first.id])
        let reader = container.newBackgroundContext()
        try await reader.perform {
            for bond in try reader.fetch(BondEntity.fetchRequest()) where ids.contains(bond.id) {
                XCTAssertTrue(BondTermsStore.isReady(bond)); XCTAssertEqual(bond.couponRate, 4.5)
            }
        }
    }
    func testFailedInstrumentSaveDoesNotPreventLaterISINSuccess() async throws {
        let container = try TestPortfolio.make()
        let good = TestPortfolio.bond(in: container.viewContext)
        let bad = TestPortfolio.bond(in: container.viewContext); bad.isin = "DE0000000000"
        let goodID = good.id, badID = bad.id
        try HistoricalDataRecorder.recordBondAcquisition(bond: good, context: container.viewContext)
        try container.viewContext.save()
        let service = BondTermsReview(container: container, fetch: { isin in
            var terms = try BondTermsFixtures.fixed(); terms.isin = isin
            return BondDetails(name: "Fixture", wkn: "TEST01", issuer: "Issuer", maturityDate: terms.maturity?.instant, couponRate: terms.couponRate, terms: terms)
        }, now: { TestPortfolio.date("2026-02-03T12:00:00Z") })
        await service.collect(ids: [badID, goodID])
        let coordinator = container.persistentStoreCoordinator
        let token = NotificationCenter.default.addObserver(forName: .NSManagedObjectContextWillSave, object: nil, queue: nil) { note in
            guard let context = note.object as? NSManagedObjectContext,
                  context.persistentStoreCoordinator === coordinator, context.concurrencyType == .privateQueueConcurrencyType else { return }
            for case let bond as BondEntity in context.updatedObjects where bond.id == badID { bond.setValue(nil, forKey: "name") }
        }
        defer { NotificationCenter.default.removeObserver(token) }
        let report = try await service.apply(ids: [badID, goodID])
        XCTAssertEqual(report.appliedISINs, ["DE0000000001"])
        XCTAssertNotNil(report.failures["DE0000000000"])
        XCTAssertTrue(report.appliedHoldingIDs.contains(goodID)); XCTAssertFalse(report.appliedHoldingIDs.contains(badID))
        let reader = container.newBackgroundContext()
        try await reader.perform {
            let bonds = try reader.fetch(BondEntity.fetchRequest())
            XCTAssertTrue(BondTermsStore.isReady(try XCTUnwrap(bonds.first { $0.id == goodID })))
            XCTAssertFalse(BondTermsStore.isReady(try XCTUnwrap(bonds.first { $0.id == badID })))
            XCTAssertEqual(try reader.count(for: HistoricalValuation.fetchRequest()), 1)
        }
    }
    func testMissingDraftDoesNotBlockOtherISINApproval() async throws {
        let container = try TestPortfolio.make()
        let good = TestPortfolio.bond(in: container.viewContext)
        let bad = TestPortfolio.bond(in: container.viewContext); bad.isin = "DE0000000003"
        let ids = [good.id, bad.id]; try container.viewContext.save()
        let service = review(container); await service.collect(ids: [good.id])
        let report = try await service.apply(ids: ids)
        XCTAssertEqual(report.appliedISINs, ["DE0000000001"])
        XCTAssertNotNil(report.failures["DE0000000003"])
    }
    func testMissingSelectionDoesNotBlockReusingAnotherISINApproval() async throws {
        let container = try TestPortfolio.make()
        let first = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: TestPortfolio.date("2026-02-02T12:00:00Z"))
        let second = TestPortfolio.bond(in: container.viewContext)
        let secondID = second.id; try container.viewContext.save()
        let service = review(container)
        do { try await service.reuseApproved(ids: [first.id, UUID()]) }
        catch { XCTFail("A missing selection must not block valid ISIN reuse: \(error)") }
        let reader = container.newBackgroundContext()
        try await reader.perform {
            XCTAssertTrue(BondTermsStore.isReady(try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first { $0.id == secondID })))
        }
    }
    func testReusePreservesSavedManualChangesWithoutApprovingThem() async throws {
        let container = try TestPortfolio.make()
        _ = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: TestPortfolio.date("2026-02-02T12:00:00Z"))
        let second = TestPortfolio.bond(in: container.viewContext)
        var proposed = try BondTermsFixtures.fixed(); proposed.couponRate = 7; proposed.confirmedFields.insert("couponRate")
        let draft = try BondTermsDraft(baseline: BondBaseline.capture(second), trade: BondTermsStore.trade(second), legacyDateZone: "Europe/Berlin", proposed: proposed, previewDay: MarketDay("2026-02-03"))
        try BondTermsStore.stageDraft(draft, for: second); try container.viewContext.save()
        let id = second.id
        let service = review(container)
        try await service.load()
        try await service.reuseApproved(ids: [id])
        XCTAssertEqual(service.drafts[id]?.proposed.couponRate, 7, "Retained manual changes must remain accessible in the open review")
        let reader = container.newBackgroundContext()
        try await reader.perform {
            let stored = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first { $0.id == id })
            XCTAssertTrue(BondTermsStore.isReady(stored)); XCTAssertEqual(stored.couponRate, 3.375)
            XCTAssertEqual(try BondTermsStore.readDraft(stored)?.proposed.couponRate, 7)
        }
    }
    func testReusePreservesConventionOnlyManualDrafts() async throws {
        for (key, value) in [("dayCount", "actual360"), ("calendar", "weekendsOnly"), ("adjustment", "following")] {
            let container = try TestPortfolio.make()
            _ = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: TestPortfolio.date("2026-02-02T12:00:00Z"))
            let second = TestPortfolio.bond(in: container.viewContext)
            var proposed = try BondTermsFixtures.fixed()
            switch key {
            case "dayCount": proposed.conventions.dayCount = value
            case "calendar": proposed.conventions.calendar = value
            default: proposed.conventions.adjustment = value
            }
            proposed.conventions.sources[key] = .confirmed
            let draft = try BondTermsDraft(baseline: BondBaseline.capture(second), trade: BondTermsStore.trade(second),
                legacyDateZone: "Europe/Berlin", proposed: proposed, previewDay: MarketDay("2026-02-03"))
            try BondTermsStore.stageDraft(draft, for: second); try container.viewContext.save()
            let id = second.id, service = review(container)
            try await service.load(); try await service.reuseApproved(ids: [id])
            XCTAssertEqual(service.drafts[id]?.proposed.conventions, proposed.conventions)
            let reader = container.newBackgroundContext()
            try await reader.perform {
                let stored = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first { $0.id == id })
                XCTAssertEqual(try BondTermsStore.readDraft(stored)?.proposed.conventions, proposed.conventions)
                XCTAssertTrue(BondTermsStore.isReady(stored))
                XCTAssertEqual(try BondTermsStore.read(stored)?.conventions.sources[key], .assumed)
            }
        }
    }
    func testRefreshRetainsRestrictionsAndConfirmedValuesFromEveryPurchase() async throws {
        let container = try TestPortfolio.make()
        let first = TestPortfolio.bond(in: container.viewContext)
        let second = TestPortfolio.bond(in: container.viewContext)
        var proposed = try BondTermsFixtures.fixed()
        proposed.restrictions = ["floating"]
        proposed.couponRate = 7; proposed.confirmedFields.insert("couponRate")
        let draft = try BondTermsDraft(baseline: BondBaseline.capture(second), trade: BondTermsStore.trade(second),
            legacyDateZone: "Europe/Berlin", proposed: proposed, previewDay: MarketDay("2026-02-03"))
        try BondTermsStore.stageDraft(draft, for: second); try container.viewContext.save()
        let service = review(container); try await service.load()
        await service.collect(ids: [first.id])
        for id in [first.id, second.id] {
            XCTAssertEqual(service.drafts[id]?.proposed.restrictions, ["floating"])
            XCTAssertEqual(service.drafts[id]?.proposed.couponRate, 7)
        }
        do { try await service.apply(ids: [first.id]); XCTFail("Known unsupported restriction must survive refresh") } catch {}
    }
    func testRefreshKeepsConflictingConfirmedDraftsUntilExplicitSharedSave() async throws {
        for field in ["couponRate", "calendar"] {
            let container = try TestPortfolio.make()
            let first = TestPortfolio.bond(in: container.viewContext)
            let second = TestPortfolio.bond(in: container.viewContext)
            for (bond, alternate) in [(first, false), (second, true)] {
                var proposed = try BondTermsFixtures.fixed()
                if field == "couponRate" {
                    proposed.couponRate = alternate ? 7 : 4; proposed.confirmedFields.insert(field)
                } else {
                    proposed.conventions.calendar = alternate ? "weekendsOnly" : "TARGET"
                    proposed.conventions.sources[field] = .confirmed
                }
                let draft = try BondTermsDraft(baseline: BondBaseline.capture(bond), trade: BondTermsStore.trade(bond),
                    legacyDateZone: "Europe/Berlin", proposed: proposed, previewDay: MarketDay("2026-02-03"))
                try BondTermsStore.stageDraft(draft, for: bond)
            }
            try container.viewContext.save()
            let before = [first.id: first.termsDraftData!, second.id: second.termsDraftData!]
            let service = review(container); try await service.load()
            await service.collect(ids: [first.id])
            XCTAssertNotNil(service.errors[first.isin])
            let reader = container.newBackgroundContext()
            try await reader.perform {
                for bond in try reader.fetch(BondEntity.fetchRequest()) {
                    XCTAssertEqual(bond.termsDraftData, before[bond.id])
                }
            }
        }
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
