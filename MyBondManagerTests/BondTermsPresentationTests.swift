import XCTest
@testable import MyBondManager

@MainActor
final class BondTermsPresentationTests: XCTestCase {
    func testUnsupportedAndUnapprovedForecastsAreClearlyExcluded() {
        let missing = TermsAssessment(reasons: ["Coupon frequency is missing."], warnings: [])
        XCTAssertEqual(BondTermsPresentation.status(assessment: missing, approved: true), "Needs review")
        XCTAssertEqual(BondTermsPresentation.status(assessment: TermsAssessment(reasons: [], warnings: []), approved: true), "Ready")
        XCTAssertEqual(BondTermsPresentation.exclusions(2), "Forecast excludes 2 holdings needing review.")
        XCTAssertNil(BondTermsPresentation.exclusions(0))
        var terms = BondTerms(); terms.callable = true
        XCTAssertEqual(BondTermsPresentation.callWarning(terms), "Early redemption is not modeled.")
    }
    func testManualReviewPersistsWithoutFetchAndCannotApproveMissingTerms() async throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext); try container.viewContext.save()
        let review = BondTermsReview(container: container, fetch: { _ in throw PortfolioError("Unexpected network work") })
        try await review.beginManualReview(ids: [bond.id])
        let draft = try XCTUnwrap(review.drafts[bond.id])
        XCTAssertNil(draft.proposed.collectedAt); XCTAssertNil(draft.proposed.callable)
        XCTAssertFalse(try review.preview(draft).assessment.supported)
        let resumed = BondTermsReview(container: container); try await resumed.load()
        XCTAssertNotNil(resumed.drafts[bond.id])
        let reader = container.newBackgroundContext()
        try await reader.perform {
            let stored = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first)
            XCTAssertEqual(stored.termsAcquisitionDay, "2025-01-01")
            XCTAssertNotNil(stored.termsLegacyDateZone)
        }
    }
    func testImportConfirmationShowsIncomingAndRemovedCountsAndLegacyState() throws {
        let transfer = try BondTransfer.prepare(bonds: Data("[]".utf8), sidecar: nil)
        let text = BondTermsPresentation.importSummary(transfer, existingIDs: [UUID(), UUID()])
        XCTAssertTrue(text.contains("0 incoming")); XCTAssertTrue(text.contains("2 removed"))
        XCTAssertTrue(text.contains("all bond positions")); XCTAssertTrue(text.contains("Needs review"))
    }
}
