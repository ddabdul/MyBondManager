import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class FloatingProjectionTests: XCTestCase {
    private func approve(_ bond: BondEntity, terms input: BondTerms, market: ProjectionContext, at: Date) throws {
        var terms = input; terms.isin = bond.isin; terms.approvedAt = at
        let trade = try BondTermsStore.trade(bond)
        let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay(date: at), context: market)
        XCTAssertTrue(preview.assessment.supported, preview.assessment.reasons.joined())
        try BondTermsStore.replaceProjections(for: bond, terms: terms, preview: preview, now: at,
            acquisitionDay: trade.acquisitionDay, legacyDateZone: "Europe/Berlin", context: bond.managedObjectContext!, projectionContext: market)
        try bond.managedObjectContext!.save()
    }
    private func shortOpeningTerms() throws -> BondTerms {
        var terms = try FloatingMathFixtures.singlePeriodTerms(start: "2027-01-15", end: "2027-07-18")
        terms.floatingTerms?.firstFloatingCoupon = try MarketDay("2027-01-18")
        terms.nextCoupon = try MarketDay("2027-01-18")
        terms.checkpointObservedOn = try MarketDay("2027-01-08")
        return terms
    }
    func testGeneralRegenerationPreservesFrozenContextForFloatingAndMixedBonds() throws {
        for mixed in [false, true] {
            let container = try TestPortfolio.make()
            let approvedAt = TestPortfolio.date("2026-10-16T12:00:00Z")
            let regeneratedAt = TestPortfolio.date("2026-10-17T12:00:00Z")
            let bond = TestPortfolio.bond(in: container.viewContext, cost: 1000000, par: 1000000)
            bond.acquisitionDate = TestPortfolio.date("2026-10-15T00:00:00Z")
            var terms = try FloatingMathFixtures.singlePeriodTerms(start: "2026-10-15", end: "2027-01-15")
            if mixed {
                terms = try FloatingMathFixtures.singlePeriodTerms(start: "2026-01-15", end: "2028-01-15")
                terms.structure = .fixedToFloating; terms.frequency = 1; terms.couponRate = 3
                terms.firstCoupon = try MarketDay("2027-01-15"); terms.floatingStart = terms.firstCoupon
                terms.nextCoupon = terms.firstCoupon
                terms.floatingTerms?.firstFloatingCoupon = try MarketDay("2027-04-15")
            }
            let market = try FloatingMathFixtures.context(valuation: "2026-10-16", fixings: [
                PublishedFixing(day: MarketDay("2026-10-13"), rate: 0.025)])
            try approve(bond, terms: terms, market: market, at: approvedAt)
            let before = try ExportManager.snapshotBonds(from: container.viewContext).map(PositionsTransferValidation.normalized)
            let activation = bond.eventsActivateAfter
            try CashFlowGenerator(context: container.viewContext).regenerateCashFlows(for: bond, now: regeneratedAt)
            try container.viewContext.save()
            XCTAssertEqual(try ExportManager.snapshotBonds(from: container.viewContext).map(PositionsTransferValidation.normalized), before)
            XCTAssertEqual(try BondTermsStore.projectionContext(bond), market)
            XCTAssertEqual(try BondTermsStore.read(bond)?.approvedAt, approvedAt)
            XCTAssertEqual(bond.eventsActivateAfter, activation)
            XCTAssertNil(try BondTermsStore.estimatedYTM(bond))
            XCTAssertTrue(bond.termsReady)
            let coupon = try XCTUnwrap(bond.cashFlowsArray.first { $0.natureEnum == .interest && MarketDay(date: $0.date).rawValue == "2027-01-15" })
            XCTAssertEqual(coupon.amount, mixed ? 30000 : 6772.222222222222, accuracy: 1e-8)
            XCTAssertEqual(try container.viewContext.count(for: HistoricalValuation.fetchRequest()), 0)
        }
    }
    func testSharedPreviewRequiresContextAndShowsProjectedRatesWithoutFixedYield() throws {
        let terms = try FloatingMathFixtures.singlePeriodTerms(start: "2027-01-15", end: "2027-04-15")
        let context = try FloatingMathFixtures.context(valuation: "2026-10-16", fixings: [])
        let trade = try BondTermsFixtures.trade()
        let missing = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay("2026-10-16"))
        XCTAssertFalse(missing.assessment.supported)
        let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay("2026-10-16"), context: context)
        XCTAssertTrue(preview.assessment.supported, preview.assessment.reasons.joined())
        XCTAssertNil(preview.estimatedYTM)
        XCTAssertEqual(preview.payments.first?.rateSource, .projected)
    }
    func testSuccessiveLaunchesRecoverLateFixingAfterWatermarkAdvanced() async throws {
        for rate in [0.025, -0.005] {
            let container = try TestPortfolio.make()
            let activation = TestPortfolio.date("2027-01-08T12:00:00Z")
            let tuesday = TestPortfolio.date("2027-01-19T12:00:00Z"), wednesday = TestPortfolio.date("2027-01-20T12:00:00Z")
            let bond = TestPortfolio.bond(in: container.viewContext, cost: 99000, par: 100000)
            bond.acquisitionDate = activation
            let id = bond.id
            let initial = try FloatingMathFixtures.context(valuation: "2027-01-08", fixings: [])
            try approve(bond, terms: shortOpeningTerms(), market: initial, at: activation)
            let suite = "FloatingLaunch-" + UUID().uuidString
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(activation, forKey: "lastLaunchDate")
            let notifier = LaunchNotifier(defaults: defaults)
            await notifier.processLaunch(in: container, now: tuesday)
            XCTAssertEqual(defaults.object(forKey: "lastLaunchDate") as? Date, tuesday)
            let reader = container.newBackgroundContext()
            let beforeCount = try await reader.perform { try reader.count(for: HistoricalValuation.fetchRequest()) }
            XCTAssertEqual(beforeCount, 0)
            let actual = try FloatingMathFixtures.context(valuation: "2027-01-20", fixings: [
                PublishedFixing(day: MarketDay("2027-01-13"), rate: rate), PublishedFixing(day: MarketDay("2027-01-14"), rate: rate)])
            let review = BondTermsReview(container: container, now: { wednesday })
            let report = try await review.refreshForecasts(ids: [id], context: actual)
            XCTAssertEqual(report.appliedHoldingIDs, [id])
            await notifier.processLaunch(in: container, now: wednesday)
            let rows = try await reader.perform { try reader.fetch(HistoricalValuation.fetchRequest()).map { ($0.date, $0.interestReceived?.doubleValue ?? 0) } }
            XCTAssertEqual(rows.count, 1)
            XCTAssertEqual(rows.first?.0, try MarketDay("2027-01-18").instant)
            XCTAssertEqual(try XCTUnwrap(rows.first).1, rate > 0 ? 22.083333333333332 : -2.9166666666666665, accuracy: 1e-8)
            await notifier.processLaunch(in: container, now: TestPortfolio.date("2027-01-21T12:00:00Z"))
            let repeatedCount = try await reader.perform { try reader.count(for: HistoricalValuation.fetchRequest()) }
            XCTAssertEqual(repeatedCount, 1)
            let stored = try await reader.perform { () -> (Date?,Date?,ProjectionContext?) in
                let loaded = try reader.fetch(BondEntity.fetchRequest()).first!
                return (try BondTermsStore.read(loaded)?.approvedAt, loaded.eventsActivateAfter, try BondTermsStore.projectionContext(loaded))
            }
            XCTAssertEqual(stored.0, activation); XCTAssertEqual(stored.1, activation); XCTAssertEqual(stored.2, actual)
        }
    }
    func testSnapshotAdoptionRequiresEarlierUnrecordedReceiptFixing() async throws {
        let container = try TestPortfolio.make()
        let activation = TestPortfolio.date("2027-01-08T12:00:00Z"), now = TestPortfolio.date("2027-01-20T12:00:00Z")
        let bond = TestPortfolio.bond(in: container.viewContext, cost: 99000, par: 100000)
        bond.acquisitionDate = activation; let id = bond.id
        let original = try FloatingMathFixtures.context(valuation: "2027-01-08", fixings: [])
        try approve(bond, terms: shortOpeningTerms(), market: original, at: activation)
        let originalBytes = bond.termsData
        let incomplete = try FloatingMathFixtures.context(valuation: "2027-01-20", fixings: [PublishedFixing(day: MarketDay("2027-01-14"), rate: 0.025)])
        let review = BondTermsReview(container: container, now: { now })
        let report = try await review.refreshForecasts(ids: [id], context: incomplete)
        XCTAssertTrue(report.appliedHoldingIDs.isEmpty); XCTAssertEqual(report.failures.count, 1)
        container.viewContext.refreshAllObjects()
        XCTAssertEqual(bond.termsData, originalBytes)
        XCTAssertEqual(try BondTermsStore.projectionContext(bond), original)
        let suite = "FailedAdoption-" + UUID().uuidString; let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(activation, forKey: "lastLaunchDate")
        let notifier = LaunchNotifier(defaults: defaults)
        await notifier.processLaunch(in: container, now: now)
        XCTAssertEqual(defaults.object(forKey: "lastLaunchDate") as? Date, now)
        XCTAssertNil(notifier.alertMessage)
    }
    func testNewFloatingPurchasePersistsSelectedContext() async throws {
        let container = try TestPortfolio.make()
        let now = TestPortfolio.date("2026-10-16T12:00:00Z")
        var terms = try FloatingMathFixtures.singlePeriodTerms(start: "2026-10-15", end: "2027-01-15")
        terms.approvedAt = now
        let market = try FloatingMathFixtures.context(valuation: "2026-10-16", fixings: [PublishedFixing(day: MarketDay("2026-10-13"), rate: 0.025)])
        let values = BondCodable(id: UUID(), name: "Floating fixture", isin: terms.isin, issuer: "Fixture", depotBank: "Bank",
            acquisitionDate: now, maturityDate: terms.maturity!.instant, couponRate: 0, parValue: 100000, initialPrice: 99000,
            yieldToMaturity: 0, wkn: "Fixture", cashFlows: [])
        let service = BondTermsReview(container: container, now: { now })
        _ = try await service.saveNew(values: values, terms: terms, legacyDateZone: "Europe/Berlin", projectionContext: market)
        let reader = container.newBackgroundContext()
        let loaded = try await reader.perform { () -> ProjectionContext? in
            let bond = try reader.fetch(BondEntity.fetchRequest()).first!
            XCTAssertTrue(BondTermsStore.isReady(bond))
            return try BondTermsStore.projectionContext(bond)
        }
        XCTAssertEqual(loaded, market)
    }
    func testExplicitlyClearedDraftContextSurvivesProviderRefresh() async throws {
        let container = try TestPortfolio.make()
        let now = TestPortfolio.date("2026-10-16T12:00:00Z")
        let bond = TestPortfolio.bond(in: container.viewContext, cost: 99000, par: 100000)
        let terms = try FloatingMathFixtures.singlePeriodTerms(start: "2026-10-15", end: "2027-01-15")
        let market = try FloatingMathFixtures.context(valuation: "2026-10-16", fixings: [PublishedFixing(day: MarketDay("2026-10-13"), rate: 0.025)])
        try approve(bond, terms: terms, market: market, at: now)
        let service = BondTermsReview(container: container, fetch: { _ in
            BondDetails(name: "Fixture", wkn: "Fixture", issuer: "Fixture", maturityDate: terms.maturity?.instant, couponRate: nil, terms: terms)
        }, now: { now })
        try await service.beginManualReview(ids: [bond.id])
        var draft = try XCTUnwrap(service.drafts[bond.id]); draft.projectionContext = nil
        try await service.edit(draft)
        await service.collect(ids: [bond.id])
        XCTAssertTrue(service.errors.isEmpty, service.errors.description)
        XCTAssertNil(service.drafts[bond.id]?.projectionContext)
    }
    func testBulkAdoptionCommitsValidISINWhileKeepingMissingFixingISINUnchanged() async throws {
        let container = try TestPortfolio.make()
        let activation = TestPortfolio.date("2027-01-08T12:00:00Z")
        let now = TestPortfolio.date("2027-01-20T12:00:00Z")
        let original = try FloatingMathFixtures.context(valuation: "2027-01-08", fixings: [])
        let valid = TestPortfolio.bond(in: container.viewContext, cost: 99000, par: 100000)
        valid.isin = "DE0000000002"; valid.acquisitionDate = activation
        let invalid = TestPortfolio.bond(in: container.viewContext, cost: 99000, par: 100000)
        invalid.acquisitionDate = activation
        try approve(valid, terms: FloatingMathFixtures.singlePeriodTerms(start: "2027-01-15", end: "2027-04-15"), market: original, at: activation)
        try approve(invalid, terms: shortOpeningTerms(), market: original, at: activation)
        let previous = invalid.termsData
        let candidate = try FloatingMathFixtures.context(valuation: "2027-01-20", fixings: [PublishedFixing(day: MarketDay("2027-01-13"), rate: 0.025)])
        let review = BondTermsReview(container: container, now: { now })
        let report = try await review.refreshForecasts(ids: [valid.id, invalid.id], context: candidate)
        XCTAssertEqual(report.appliedHoldingIDs, [valid.id])
        XCTAssertEqual(Set(report.failures.keys), [invalid.isin])
        container.viewContext.refreshAllObjects()
        XCTAssertEqual(try BondTermsStore.projectionContext(valid), candidate)
        XCTAssertEqual(invalid.termsData, previous)
    }
    func testCorrectedPublishedFixingCannotRewriteRecordedReceipt() async throws {
        let container = try TestPortfolio.make()
        let activation = TestPortfolio.date("2027-01-08T12:00:00Z")
        let now = TestPortfolio.date("2027-01-20T12:00:00Z")
        let bond = TestPortfolio.bond(in: container.viewContext, cost: 99000, par: 100000)
        bond.acquisitionDate = activation
        let original = try FloatingMathFixtures.context(valuation: "2027-01-08", fixings: [])
        try approve(bond, terms: shortOpeningTerms(), market: original, at: activation)
        let review = BondTermsReview(container: container, now: { now })
        func candidate(_ rate: Double) throws -> ProjectionContext {
            try FloatingMathFixtures.context(valuation: "2027-01-20", fixings: [
                PublishedFixing(day: MarketDay("2027-01-13"), rate: rate),
                PublishedFixing(day: MarketDay("2027-01-14"), rate: 0.025)])
        }
        let first = try candidate(0.025)
        let accepted = try await review.refreshForecasts(ids: [bond.id], context: first)
        XCTAssertEqual(accepted.appliedHoldingIDs, [bond.id])
        let suite = "CorrectedFixing-" + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(activation, forKey: "lastLaunchDate")
        await LaunchNotifier(defaults: defaults).processLaunch(in: container, now: now)
        let rejected = try await review.refreshForecasts(ids: [bond.id], context: candidate(0.03))
        XCTAssertTrue(rejected.appliedHoldingIDs.isEmpty)
        XCTAssertTrue(rejected.failures[bond.isin]?.contains("existing receipt") == true)
        container.viewContext.refreshAllObjects()
        XCTAssertEqual(try BondTermsStore.projectionContext(bond), first)
        let receipts = try container.viewContext.fetch(HistoricalValuation.fetchRequest())
        XCTAssertEqual(receipts.count, 1)
        XCTAssertEqual(try XCTUnwrap(receipts.first?.interestReceived).doubleValue, 22.083333333333332, accuracy: 1e-8)
    }

}
