import XCTest
@testable import MyBondManager

@MainActor
final class PastPaymentReviewTests: XCTestCase {
    func testHistoricalReviewFlagsOpeningCouponDespiteCurrentReadinessAndCorrectionClearsReport() async throws {
        let store = try TestPortfolio.make()
        let bond = try TestPortfolio.historicalOpeningBond(in: store.viewContext)
        try store.viewContext.save()
        let saved = bond.termsData
        let group = try XCTUnwrap(BondTermsReviewInstrument.grouped([bond]).first)
        XCTAssertFalse(group.needsReview)
        let from = try MarketDay("2025-06-01")
        XCTAssertTrue(group.reviewIssues(from: from).contains { $0.contains("opening coupon") })
        let service = BondTermsReview(container: store, now: { TestPortfolio.date("2026-10-18T12:00:00Z") })
        do { _ = try await service.reuseApproved(ids: [bond.id], reportFrom: from); XCTFail("Historical failure must remain unresolved") }
        catch { XCTAssertTrue(error.localizedDescription.contains("opening coupon")) }
        try await service.beginManualReview(ids: [bond.id])
        do { _ = try await service.apply(ids: [bond.id], reportFrom: from); XCTFail("Uncorrected opening terms must not apply") }
        catch { XCTAssertTrue(error.localizedDescription.contains("opening coupon")) }
        XCTAssertEqual(bond.termsData, saved)
        var draft = try XCTUnwrap(service.drafts[bond.id])
        draft.proposed.firstCoupon = try MarketDay("2025-07-15")
        draft.proposed.confirmedFields.insert("firstCoupon")
        try await service.edit(draft)
        _ = try await service.apply(ids: [bond.id], reportFrom: from)
        store.viewContext.refreshAllObjects()
        XCTAssertTrue(group.reviewIssues(from: from).isEmpty)
        let report = try PastPaymentReport.build(bonds: [bond], from: from, through: MarketDay("2026-01-15"),
            now: TestPortfolio.date("2026-10-18T12:00:00Z"))
        XCTAssertTrue(report.isComplete)
        XCTAssertEqual(report.payments.count, 2)
        XCTAssertEqual(try store.viewContext.count(for: HistoricalValuation.fetchRequest()), 0)
    }

    func testHistoricalFloatingRebuildFailsWithoutOldFixingAndPreservesApproval() async throws {
        let store = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: store.viewContext, cost: 99000, par: 100000)
        bond.acquisitionDate = TestPortfolio.date("2026-01-15T00:00:00Z")
        let at = TestPortfolio.date("2026-10-18T12:00:00Z")
        var terms = try FloatingMathFixtures.singlePeriodTerms(start: "2026-01-15", end: "2027-01-15")
        terms.floatingTerms?.firstFloatingCoupon = try MarketDay("2026-04-15")
        terms.nextCoupon = try MarketDay("2026-04-15"); terms.approvedAt = at
        let context = try FloatingMathFixtures.context(valuation: "2026-10-16", fixings: [
            PublishedFixing(day: MarketDay("2026-10-13"), rate: 0.025)])
        let trade = try BondTermsStore.trade(bond)
        let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay(date: at), context: context)
        XCTAssertTrue(preview.assessment.supported, preview.assessment.reasons.joined())
        try BondTermsStore.replaceProjections(for: bond, terms: terms, preview: preview, now: at,
            acquisitionDay: trade.acquisitionDay, legacyDateZone: "Europe/Berlin", context: store.viewContext, projectionContext: context)
        try store.viewContext.save()
        let saved = bond.termsData
        let service = BondTermsReview(container: store, now: { at })
        let result = try await service.refreshForecasts(ids: [bond.id], context: context, reportFrom: MarketDay("2026-03-01"))
        XCTAssertTrue(result.appliedISINs.isEmpty)
        XCTAssertEqual(result.failures.count, 1)
        store.viewContext.refreshAllObjects()
        XCTAssertEqual(bond.termsData, saved)
        XCTAssertEqual(try store.viewContext.count(for: HistoricalValuation.fetchRequest()), 0)
    }

    func testScopedReviewIncludesMaturedISINAndAllPurchasesWithoutUnrelatedHoldings() throws {
        let store = try TestPortfolio.make()
        let archived = TestPortfolio.bond(in: store.viewContext)
        archived.maturityDate = TestPortfolio.date("2025-01-15T00:00:00Z")
        let sibling = TestPortfolio.bond(in: store.viewContext)
        sibling.maturityDate = archived.maturityDate
        let active = TestPortfolio.bond(in: store.viewContext); active.isin = "DE0000000002"
        active.maturityDate = TestPortfolio.date("2030-01-15T00:00:00Z")
        let today = try MarketDay("2026-10-18")
        let scoped = BondTermsReviewInstrument.scoped([archived, sibling, active], today: today, requestedIDs: [archived.id])
        XCTAssertEqual(scoped.count, 1)
        XCTAssertEqual(Set(scoped[0].purchases.map(\.id)), [archived.id, sibling.id])
        let normal = BondTermsReviewInstrument.scoped([archived, sibling, active], today: today)
        XCTAssertEqual(normal.map(\.isin), [active.isin])
    }

    func testReportExplainsMissingApprovalAndNamesReusableSibling() throws {
        let store = try TestPortfolio.make()
        let ready = try TestPortfolio.readyBond(in: store.viewContext, terms: BondTermsFixtures.fixed(),
            now: TestPortfolio.date("2026-10-18T12:00:00Z"))
        let missing = TestPortfolio.bond(in: store.viewContext); missing.isin = ready.isin
        missing.maturityDate = ready.maturityDate; missing.depotBank = "Archive"
        let report = try PastPaymentReport.build(bonds: [ready, missing], from: MarketDay("2026-07-15"),
            through: MarketDay("2026-07-15"), bank: "Archive", now: TestPortfolio.date("2026-10-18T12:00:00Z"))
        let reason = try XCTUnwrap(report.excludedHoldings.first).reason
        XCTAssertTrue(reason.contains("No saved approved terms"), reason)
        XCTAssertTrue(reason.contains("Reuse approved terms"), reason)
    }

    func testMaturedReuseAppliesSuccessfulISINAndLeavesMissingApprovalOpenWithoutHistory() async throws {
        let store = try TestPortfolio.make()
        let approvedAt = TestPortfolio.date("2026-10-18T12:00:00Z")
        let now = TestPortfolio.date("2028-01-01T12:00:00Z")
        let ready = try TestPortfolio.readyBond(in: store.viewContext, terms: BondTermsFixtures.fixed(), now: approvedAt)
        let sibling = TestPortfolio.bond(in: store.viewContext)
        sibling.isin = ready.isin; sibling.couponRate = ready.couponRate; sibling.maturityDate = ready.maturityDate
        let failed = TestPortfolio.bond(in: store.viewContext); failed.isin = "DE0000000002"
        failed.maturityDate = ready.maturityDate
        try store.viewContext.save()
        let saved = ready.termsData
        let review = BondTermsReview(container: store, now: { now })
        let result = try await review.reuseApproved(ids: [sibling.id, failed.id])
        XCTAssertEqual(result.appliedISINs, [ready.isin])
        XCTAssertEqual(result.appliedHoldingIDs, [ready.id, sibling.id])
        XCTAssertEqual(result.failures.count, 1)
        store.viewContext.refreshAllObjects()
        XCTAssertEqual(ready.termsData, saved)
        XCTAssertTrue(BondTermsStore.isReady(sibling))
        XCTAssertFalse(BondTermsStore.isReady(failed))
        let report = try PastPaymentReport.build(bonds: [ready, sibling], from: MarketDay("2027-01-15"),
            through: MarketDay("2027-01-15"), now: now)
        XCTAssertTrue(report.excludedHoldings.isEmpty)
        XCTAssertTrue(report.payments.isEmpty)
        XCTAssertEqual(try store.viewContext.count(for: HistoricalValuation.fetchRequest()), 0)
    }

    func testReportIdentifiesChangedFieldsAndCorruptSavedDataWithoutChangingApproval() throws {
        let store = try TestPortfolio.make()
        let bond = try TestPortfolio.readyBond(in: store.viewContext, terms: BondTermsFixtures.fixed(),
            now: TestPortfolio.date("2026-10-18T12:00:00Z"))
        let saved = bond.termsData
        bond.initialPrice += 1
        let day = try MarketDay("2026-07-15")
        let report = try PastPaymentReport.build(bonds: [bond], from: day, through: day,
            now: TestPortfolio.date("2026-10-18T12:00:00Z"))
        XCTAssertTrue(try XCTUnwrap(report.excludedHoldings.first).reason.contains("purchase cost"))
        XCTAssertEqual(bond.termsData, saved)
        bond.termsData = Data([1, 2, 3])
        let corrupt = try PastPaymentReport.build(bonds: [bond], from: day, through: day,
            now: TestPortfolio.date("2026-10-18T12:00:00Z"))
        XCTAssertTrue(try XCTUnwrap(corrupt.excludedHoldings.first).reason.contains("cannot be decoded"))
    }
}
