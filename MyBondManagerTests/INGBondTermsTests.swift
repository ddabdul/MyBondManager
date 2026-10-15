import XCTest
@testable import MyBondManager

final class INGBondTermsTests: XCTestCase {
    override func tearDown() { INGBondFixtures.clear(); super.tearDown() }
    func testRetainsPrecisionDistinctDatesFrequencyAndUnknownState() async throws {
        for (label, frequency) in [("Jährlich",1),("Halbjährlich",2),("Vierteljährlich",4)] {
            var map = INGBondFixtures.responses
            map["interestrates"] = map["interestrates"]!.replacingOccurrences(of: "Halbjährlich", with: label)
            let session = INGBondFixtures.session(responses: map); defer { session.invalidateAndCancel() }
            let details = try await BondDataScraper(session: session).fetchDetails(isin: " de0000000001 ", observedAt: TestPortfolio.date("2026-02-03T12:00:00Z"))
            let terms = try XCTUnwrap(details.terms)
            XCTAssertEqual(terms.frequency, frequency); XCTAssertEqual(terms.couponRate, 3.375)
            XCTAssertEqual(terms.accrualStart?.rawValue, "2026-01-15")
            XCTAssertEqual(terms.issueDay?.rawValue, "2026-02-02")
            XCTAssertEqual(terms.nextCoupon?.rawValue, "2026-07-15")
            XCTAssertEqual(terms.callable, false); XCTAssertEqual(terms.currency, "EUR")
        }
    }
    func testMissingCouponAndMaturityStayMissingInsteadOfFailingCollection() async throws {
        for field in ["coupon", "maturity"] {
            var map = INGBondFixtures.responses
            if field == "coupon" { map["interestrates"] = #"{"interest":"Fest","data":[]}"# }
            else { map["dates"] = #"{"issueDate":{"value":"2026-02-02"}}"# }
            let session = INGBondFixtures.session(responses: map); defer { session.invalidateAndCancel() }
            let details = try await BondDataScraper(session: session).fetchDetails(isin: "DE0000000001")
            if field == "coupon" { XCTAssertNil(details.couponRate); XCTAssertNil(details.terms?.couponRate) }
            else { XCTAssertNil(details.maturityDate); XCTAssertNil(details.terms?.maturity) }
        }
    }
    func testMalformedSuppliedCalendarDatesThrow() async throws {
        for date in ["", "2026-02-31", "2026-01-15bad", "2026-01-15Tgarbage"] {
            var map = INGBondFixtures.responses
            map["dates"] = "{\"maturityDate\":{\"value\":\"\(date)\"}}"
            let session = INGBondFixtures.session(responses: map); defer { session.invalidateAndCancel() }
            do { _ = try await BondDataScraper(session: session).fetchDetails(isin: "DE0000000001"); XCTFail("Expected bad date rejection") }
            catch {}
        }
    }
    func testInvalidSuppliedAmountsAreErrorsAndZeroContradictionsStayRestricted() async throws {
        for (rate, redemption) in [("-1", "100"), ("3.375", "0")] {
            var map = INGBondFixtures.responses
            map["interestrates"] = "{\"interest\":\"Fest\",\"redemptionPayment\":\(redemption),\"data\":[{\"id\":\"InterestRate\",\"fieldValue\":{\"value\":\(rate)}}]}"
            let session = INGBondFixtures.session(responses: map); defer { session.invalidateAndCancel() }
            do { _ = try await BondDataScraper(session: session).fetchDetails(isin: "DE0000000001"); XCTFail("Expected amount rejection") }
            catch {}
        }
        var map = INGBondFixtures.responses
        map["interestrates"] = map["interestrates"]!.replacingOccurrences(of: "false", with: "true")
        let session = INGBondFixtures.session(responses: map); defer { session.invalidateAndCancel() }
        let details = try await BondDataScraper(session: session).fetchDetails(isin: "DE0000000001")
        XCTAssertEqual(details.terms?.structure, .zero)
        XCTAssertFalse(try XCTUnwrap(details.terms).restrictions.isEmpty)
    }
    func testUnknownFrequencyCallableAndUnsupportedStructureAreNotInvented() async throws {
        var map = INGBondFixtures.responses
        map["masterdata"] = #"{"issuerCompanyName":{"value":"Issuer"},"currencyIsoCode":{"value":"USD"}}"#
        map["interestrates"] = #"{"interest":"Variabel","interestPaymentPeriod":"Unbekannt","data":[{"id":"InterestRate","fieldValue":{"value":"3.375"}}]}"#
        let session = INGBondFixtures.session(responses: map); defer { session.invalidateAndCancel() }
        let details = try await BondDataScraper(session: session).fetchDetails(isin: "DE0000000001")
        let terms = try XCTUnwrap(details.terms)
        XCTAssertNil(terms.frequency); XCTAssertNil(terms.callable)
        XCTAssertEqual(terms.currency, "USD"); XCTAssertEqual(terms.couponRate, 3.375)
        XCTAssertEqual(terms.structure, .unknown); XCTAssertFalse(terms.restrictions.isEmpty)
    }
}
