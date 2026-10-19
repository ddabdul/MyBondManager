import XCTest
@testable import MyBondManager

@MainActor
final class PortfolioReportTests: XCTestCase {
    private let now = TestPortfolio.date("2026-10-19T12:00:00Z")

    func testExposureGroupsPurchasesByIssuerAndContractualMaturityAndWeightsYieldByNominal() throws {
        let store = try TestPortfolio.make()
        let first = try TestPortfolio.readyBond(in: store.viewContext, terms: BondTermsFixtures.fixed(), now: now, nominal: 100000, cost: 99000)
        let second = try TestPortfolio.readyBond(in: store.viewContext, terms: BondTermsFixtures.fixed(), now: now, nominal: 200000, cost: 196000)
        first.issuer = "Shared issuer"; second.issuer = "Shared issuer"
        let other = TestPortfolio.bond(in: store.viewContext, par: 100000)
        other.issuer = "Other issuer"; other.maturityDate = TestPortfolio.date("2030-01-15T00:00:00Z")
        let report = PortfolioReportData.build(bonds: [first, second, other], bank: "All", today: MarketDay(date: now))
        XCTAssertEqual(report.principal, 400000)
        XCTAssertEqual(report.issuers.map(\.name), ["Shared issuer", "Other issuer"])
        XCTAssertEqual(report.issuers[0].principal, 300000)
        XCTAssertEqual(report.issuers[0].share, 0.75, accuracy: 1e-12)
        let year = try XCTUnwrap(report.maturities.first { $0.year == 2027 })
        let firstYield = try XCTUnwrap(BondTermsStore.estimatedYTM(first))
        let secondYield = try XCTUnwrap(BondTermsStore.estimatedYTM(second))
        XCTAssertEqual(try XCTUnwrap(year.purchaseYTM), (firstYield + 2 * secondYield) / 3, accuracy: 1e-10)
        XCTAssertEqual(year.yieldCoveredPrincipal, 300000)
        XCTAssertEqual(report.exclusions.count, 1)
        XCTAssertEqual(report.maturities.first { $0.year == 2030 }?.purchaseYTM, nil)
    }

    func testBankFilterAndMaturedScopeApplyToEveryReport() throws {
        let store = try TestPortfolio.make()
        let first = try TestPortfolio.readyBond(in: store.viewContext, terms: BondTermsFixtures.fixed(), now: now)
        let other = TestPortfolio.bond(in: store.viewContext); other.depotBank = "Other"
        let matured = TestPortfolio.bond(in: store.viewContext); matured.depotBank = "Bank"
        matured.maturityDate = TestPortfolio.date("2025-01-01T00:00:00Z")
        let report = PortfolioReportData.build(bonds: [first, other, matured], bank: "Bank", today: MarketDay(date: now))
        XCTAssertEqual(report.principal, first.parValue)
        XCTAssertEqual(report.holdingCount, 1)
        XCTAssertTrue(report.exclusions.isEmpty)
        XCTAssertEqual(report.issuers.count, 1)
        let canonical = CashFlowCalendarData.build(bonds: [first], from: MarketDay(date: now), through: try MarketDay("2199-12-31"), kind: .interest)
        XCTAssertEqual(report.interest.reduce(0) { $0 + $1.amount }, canonical.totals.coupons, accuracy: 1e-10)
    }

    func testInterestUsesAdjustedPaymentYearAndIncludesZeroYears() throws {
        let store = try TestPortfolio.make()
        var terms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2028-12-31", next: "2026-12-31")
        terms.accrualStart = try MarketDay("2025-12-31")
        let bond = try TestPortfolio.readyBond(in: store.viewContext, terms: terms, now: now)
        let report = PortfolioReportData.build(bonds: [bond], bank: "All", today: MarketDay(date: now))
        XCTAssertEqual(report.maturities.map(\.year), [2028])
        XCTAssertEqual(report.interest.map(\.year), [2026, 2027, 2028, 2029])
        XCTAssertEqual(report.interest.first { $0.year == 2028 }?.amount, 0)
        XCTAssertGreaterThan(try XCTUnwrap(report.interest.last?.amount), 0)
    }

    func testUnreviewedExposureIsIncludedAndPartialYieldCoverageIsExplicit() throws {
        let store = try TestPortfolio.make()
        let approved = try TestPortfolio.readyBond(in: store.viewContext, terms: BondTermsFixtures.fixed(), now: now)
        let unresolved = TestPortfolio.bond(in: store.viewContext)
        unresolved.maturityDate = approved.maturityDate
        let report = PortfolioReportData.build(bonds: [approved, unresolved], bank: "All", today: MarketDay(date: now))
        let row = try XCTUnwrap(report.maturities.first)
        XCTAssertEqual(row.principal, approved.parValue + unresolved.parValue)
        XCTAssertEqual(row.yieldCoveredPrincipal, approved.parValue)
        XCTAssertEqual(report.missingYieldCount, 1)
        XCTAssertEqual(report.exclusions.count, 1)
        XCTAssertEqual(report.interestReceipts.count, 1)
    }

    func testIssuerMaturityWeightsRemainingCalendarDaysByNominalAndRespectsBankScope() throws {
        let store = try TestPortfolio.make()
        let first = TestPortfolio.bond(in: store.viewContext, par: 100000)
        first.issuer = "Weighted issuer"; first.termsLegacyDateZone = "Europe/Berlin"
        first.maturityDate = try MarketDay("2027-01-19").instant
        let second = TestPortfolio.bond(in: store.viewContext, par: 300000)
        second.issuer = "Weighted issuer"; second.depotBank = "Other"; second.termsLegacyDateZone = "Europe/Berlin"
        second.maturityDate = try MarketDay("2029-01-19").instant
        let matured = TestPortfolio.bond(in: store.viewContext, par: 900000)
        matured.issuer = "Weighted issuer"; matured.termsLegacyDateZone = "Europe/Berlin"
        matured.maturityDate = try MarketDay("2025-01-19").instant
        let bonds = [first, second, matured]
        let report = PortfolioReportData.build(bonds: bonds, bank: "All", today: MarketDay(date: now))
        let issuer = try XCTUnwrap(report.issuers.first)
        // Remaining periods are 92 and 823 calendar days; the latter includes leap day.
        XCTAssertEqual(issuer.averageMaturityYears, 640.25 / 365.25, accuracy: 1e-12)
        let filtered = PortfolioReportData.build(bonds: bonds, bank: "Bank", today: MarketDay(date: now))
        XCTAssertEqual(try XCTUnwrap(filtered.issuers.first).averageMaturityYears, 92 / 365.25, accuracy: 1e-12)
        first.maturityDate = MarketDay(date: now).instant
        let dueToday = PortfolioReportData.build(bonds: [first], bank: "All", today: MarketDay(date: now))
        XCTAssertEqual(try XCTUnwrap(dueToday.issuers.first).averageMaturityYears, 0)
    }

    func testEmptyAndInvalidPrincipalAreExplicitAndNeverProduceNaN() throws {
        let empty = PortfolioReportData.build(bonds: [], bank: "All", today: MarketDay(date: now))
        XCTAssertEqual(empty.principal, 0)
        XCTAssertTrue(empty.issuers.isEmpty)
        XCTAssertTrue(empty.interest.isEmpty)
        let store = try TestPortfolio.make()
        let invalid = TestPortfolio.bond(in: store.viewContext, par: .nan)
        let report = PortfolioReportData.build(bonds: [invalid], bank: "All", today: MarketDay(date: now))
        XCTAssertEqual(report.principal, 0)
        XCTAssertEqual(report.exclusions.count, 1)
    }
}
