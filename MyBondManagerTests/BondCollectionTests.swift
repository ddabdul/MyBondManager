import XCTest
@testable import MyBondManager

@MainActor
final class BondCollectionTests: XCTestCase {
    private func details(rate: Double = 3.375) -> BondDetails {
        BondDetails(name: "Bond A", wkn: "TEST", issuer: "Issuer",
            maturityDate: TestPortfolio.date("2028-01-01T00:00:00Z"), couponRate: rate)
    }

    func testChangingISINInvalidatesCollectedDetails() async {
        let fixture = details()
        let collection = BondCollection(fetch: { _ in fixture })
        collection.isin = " de0000000001 "
        await collection.collect()
        XCTAssertEqual(collection.details?.couponRate, 3.375)
        collection.isin = "DE0000000002"
        XCTAssertNil(collection.details)
    }

    func testLateResponseDoesNotRestoreObsoleteDetails() async {
        let fixture = details()
        var resume: CheckedContinuation<BondDetails, Error>?
        let collection = BondCollection(fetch: { _ in
            try await withCheckedThrowingContinuation { resume = $0 }
        })
        collection.isin = "DE0000000001"
        let task = Task { await collection.collect() }
        while resume == nil { await Task.yield() }
        collection.isin = "DE0000000002"
        resume?.resume(returning: fixture)
        await task.value
        XCTAssertNil(collection.details)
        XCTAssertFalse(collection.isLoading)
    }

    func testSameISINLatestRequestWinsWhenResponsesReverse() async throws {
        var continuations: [CheckedContinuation<BondDetails, Error>] = []
        let collection = BondCollection(fetch: { _ in try await withCheckedThrowingContinuation { continuations.append($0) } })
        collection.isin = "DE0000000001"
        let first = Task { await collection.collect() }
        while continuations.count < 1 { await Task.yield() }
        let second = Task { await collection.collect() }
        while continuations.count < 2 { await Task.yield() }
        continuations[1].resume(returning: details(rate: 4.25)); await second.value
        continuations[0].resume(returning: details(rate: 1.25)); await first.value
        XCTAssertEqual(collection.details?.couponRate, 4.25)
        XCTAssertFalse(collection.isLoading)
    }

    func testCollectedCouponPrecisionSurvivesStorageAndGeneration() async throws {
        let fixture = details()
        let collection = BondCollection(fetch: { _ in fixture })
        collection.isin = "DE0000000001"
        await collection.collect()
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext, cost: 100000, par: 100000)
        bond.couponRate = try XCTUnwrap(collection.details?.couponRate)
        try CashFlowGenerator(context: container.viewContext).regenerateCashFlows(for: bond)
        try container.viewContext.save()
        let reader = container.newBackgroundContext()
        let result = try await reader.perform {
            let stored = try XCTUnwrap(reader.fetch(BondEntity.fetchRequest()).first)
            return (stored.couponRate, stored.cashFlowsArray.first { $0.natureEnum == .interest }?.amount)
        }
        XCTAssertEqual(result.0, 3.375); XCTAssertEqual(result.1, 3375)
    }

    func testIncompleteProviderDetailsCannotBeSaved() async {
        let fixture = BondDetails(name: "", wkn: "TEST", issuer: "Issuer",
            maturityDate: TestPortfolio.date("2028-01-01T00:00:00Z"), couponRate: 3.375)
        let collection = BondCollection(fetch: { _ in fixture })
        collection.isin = "DE0000000001"
        await collection.collect()
        XCTAssertNil(collection.details)
        XCTAssertFalse(collection.errorMessage.isEmpty)
    }

    func testEmptyProviderDateIsReportedAsError() async throws {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [BondDateProtocol.self]
        let session = URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        do {
            _ = try await BondDataScraper(session: session).fetchDates(isin: "DE0000000001")
            XCTFail("Expected date validation error")
        } catch let error as ScrapError {
            guard case .dateParsingError = error else { return XCTFail("Unexpected error: \(error)") }
        }
    }
}

private final class BondDateProtocol: URLProtocol {
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(#"{"issueDate":{"value":""},"maturityDate":{"value":"2028-01-01"}}"#.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
