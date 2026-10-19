import XCTest
@testable import MyBondManager

final class BondPreviewCacheTests: XCTestCase {
    func testSavedProfilesDecodeOncePerDistinctBytesAndRetryFailures() throws {
        let cache = BondPreviewCache()
        let original = BondTermsStore.Profile(terms: try BondTermsFixtures.fixed(), trade: try BondTermsFixtures.trade(),
            acquisitionInstant: TestPortfolio.date("2026-02-01T00:00:00Z"), projectionContext: nil)
        var changed = original.terms; changed.couponRate = 4
        let replacement = BondTermsStore.Profile(terms: changed, trade: original.trade,
            acquisitionInstant: original.acquisitionInstant, projectionContext: nil)
        let first = try BondTermsStore.encode(original), second = try BondTermsStore.encode(replacement)
        var decodes = 0
        for data in [first, first, second, second, first] {
            let profile = try cache.profile(data) {
                decodes += 1
                return try BondTermsStore.decode(BondTermsStore.Profile.self, data)
            }
            XCTAssertEqual(profile.terms.couponRate, data == first ? original.terms.couponRate : 4)
        }
        XCTAssertEqual(decodes, 2, "Summary tiles and rows must reuse already decoded profiles")
        for _ in 0..<2 {
            XCTAssertThrowsError(try cache.profile(Data([0])) {
                decodes += 1
                return try BondTermsStore.decode(BondTermsStore.Profile.self, Data([0]))
            })
        }
        XCTAssertEqual(decodes, 4, "Decoding failures must not become cached success values")
    }

    func testRepeatedProfileAndDateReuseCalculatedSchedule() throws {
        let cache = BondPreviewCache()
        let terms = try BondTermsFixtures.fixed()
        let data = try JSONEncoder().encode(terms)
        let early = try MarketDay("2026-02-03"), later = try MarketDay("2026-08-01")
        var calculations = 0
        func calculate(_ from: MarketDay) throws -> BondSchedulePreview {
            calculations += 1
            return try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: terms, from: from)
        }
        for _ in 0..<20 {
            let first = try cache.preview(profile: data, from: early) { try calculate(early) }
            let second = try cache.preview(profile: data, from: later) { try calculate(later) }
            XCTAssertEqual(first.payments.filter { $0.kind == .interest }.count, 2)
            XCTAssertEqual(second.payments.filter { $0.kind == .interest }.count, 1)
            XCTAssertEqual(try XCTUnwrap(first.payments.first).amount, 1687.5, accuracy: 1e-8)
        }
        XCTAssertEqual(calculations, 2)
    }
    func testChangedTermsRecalculateAmounts() throws {
        let cache = BondPreviewCache()
        let day = try MarketDay("2026-02-03")
        var calculations = 0
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        for rate in [3.375, 3.5, 3.375] {
            var terms = try BondTermsFixtures.fixed(); terms.couponRate = rate
            let value = try cache.preview(profile: encoder.encode(terms), from: day) {
                calculations += 1
                return try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: terms, from: day)
            }
            XCTAssertEqual(try XCTUnwrap(value.payments.first).amount, rate == 3.5 ? 1750 : 1687.5, accuracy: 1e-8)
        }
        XCTAssertEqual(calculations, 2)
    }
    func testFailuresAreRetriedRatherThanCached() throws {
        let cache = BondPreviewCache()
        let day = try MarketDay("2026-02-03")
        var calculations = 0
        for _ in 0..<2 {
            XCTAssertThrowsError(try cache.preview(profile: Data([1]), from: day) {
                calculations += 1; throw PortfolioError("Unavailable")
            })
        }
        XCTAssertEqual(calculations, 2)
    }
    func testUnsupportedPreviewIsNotReused() throws {
        let cache = BondPreviewCache()
        let day = try MarketDay("2026-02-03")
        var calculations = 0
        for _ in 0..<2 {
            let preview = try cache.preview(profile: Data([1]), from: day) {
                calculations += 1
                return try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: BondTerms(), from: day)
            }
            XCTAssertFalse(preview.assessment.supported)
        }
        XCTAssertEqual(calculations, 2)
    }
    func testOldPreviewsAreEvictedRatherThanRetainedWithoutLimit() throws {
        let cache = BondPreviewCache()
        let day = try MarketDay("2026-02-03")
        let preview = try BondSchedule.preview(trade: BondTermsFixtures.trade(), terms: BondTermsFixtures.fixed(), from: day)
        var calculations = 0
        for index in Array(0..<1000) + [0] {
            _ = cache.preview(profile: Data("profile-\(index)".utf8), from: day) {
                calculations += 1; return preview
            }
        }
        XCTAssertEqual(calculations, 1001)
    }
    @MainActor
    func testCachedPreviewStillRejectsUnsavedTradeAndReadinessChanges() throws {
        let container = try TestPortfolio.make()
        let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(),
            now: TestPortfolio.date("2026-02-03T12:00:00Z"))
        try container.viewContext.save()
        let day = try MarketDay("2026-02-03")
        let mutations: [(MyBondManager.BondEntity) -> Void] = [
            { $0.parValue += 1 }, { $0.initialPrice += 1 }, { $0.depotBank = "Other" },
            { $0.acquisitionDate = $0.acquisitionDate.addingTimeInterval(1) },
            { $0.termsAcquisitionDay = "2026-02-02" }, { $0.couponRate += 1 },
            { $0.maturityDate = $0.maturityDate.addingTimeInterval(86400) },
            { $0.isin = "DE0000000002" }, { $0.termsReady = false }, { $0.termsData = nil }
        ]
        for mutate in mutations {
            XCTAssertNotNil(try BondTermsStore.validatedPreview(bond, from: day))
            mutate(bond)
            XCTAssertNil(try BondTermsStore.validatedPreview(bond, from: day))
            container.viewContext.rollback()
            XCTAssertNotNil(try BondTermsStore.validatedPreview(bond, from: day))
        }
    }
}
