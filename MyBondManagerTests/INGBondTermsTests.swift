import XCTest
@testable import MyBondManager

final class INGBondTermsTests: XCTestCase {
    override func tearDown() { INGBondFixtures.clear(); super.tearDown() }
    func testEveryISINUsesProviderDataWithoutSupplementation() async throws {
        let session = INGBondFixtures.session(); defer { session.invalidateAndCancel() }
        for isin in ["FR001400ZQ88", "FR001400H9B5", "XS2767489391", "XS3081821699", "DE0000000001"] {
            let details = try await BondDataScraper(session: session).fetchDetails(isin: isin)
            let terms = try XCTUnwrap(details.terms)
            XCTAssertEqual(terms.structure, .fixed); XCTAssertEqual(terms.couponRate, 3.375)
            XCTAssertEqual(terms.frequency, 2); XCTAssertEqual(terms.maturity?.rawValue, "2027-01-15")
            XCTAssertNil(terms.firstCoupon); XCTAssertNil(terms.interestDeferral)
            XCTAssertNil(terms.floatingStart); XCTAssertNil(terms.verifiedTermsSource)
        }
    }
    func testSparseINGDataRemainsMissingForEveryISIN() async throws {
        var map = INGBondFixtures.responses
        map["masterdata"] = #"{"currencyIsoCode":{"value":"EUR"}}"#
        map["dates"] = #"{"issueDate":{"value":"2024-02-15"}}"#
        map["interestrates"] = #"{"data":[]}"#
        let session = INGBondFixtures.session(responses: map); defer { session.invalidateAndCancel() }
        for isin in ["FR001400ZQ88", "FR001400H9B5", "XS2767489391", "XS3081821699"] {
            let details = try await BondDataScraper(session: session).fetchDetails(isin: isin)
            let terms = try XCTUnwrap(details.terms)
            XCTAssertEqual(terms.structure, .unknown)
            XCTAssertNil(details.couponRate); XCTAssertNil(details.maturityDate)
            XCTAssertNil(terms.frequency); XCTAssertNil(terms.redemptionPercent); XCTAssertNil(terms.callable)
            XCTAssertNil(terms.accrualStart); XCTAssertNil(terms.firstCoupon); XCTAssertNil(terms.nextCoupon)
        }
    }
    func testDifferentPastedISINsAndExtraTextAreRejectedWithAnActionableError() async throws {
        let session = INGBondFixtures.session(); defer { session.invalidateAndCancel() }
        for value in ["EU000A2SCAK5\nFR001400P1Y4", "ISIN: FR001400P1Y4", "FR001400P1Y"] {
            do {
                _ = try await BondDataScraper(session: session).fetchDetails(isin: value)
                XCTFail("Extra identifiers or text must not be selected silently")
            } catch ScrapError.invalidISIN {} catch { XCTFail("Expected an actionable ISIN validation error, got \(error)") }
        }
    }
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
        XCTAssertEqual(terms.structure, .floating); XCTAssertFalse(terms.restrictions.isEmpty)
    }
}
