import Foundation

enum INGBondFixtures {
    static let responses: [String: String] = [
        "localheader": #"{"instrumentName":"EUR note","wkn":"TEST01"}"#,
        "masterdata": #"{"issuerCompanyName":{"value":"Issuer"},"currencyIsoCode":{"value":"EUR"},"isBondCallableBeforeMaturity":{"value":false}}"#,
        "dates": #"{"issueDate":{"value":"2026-02-02T00:00:00+01:00"},"interestStartDate":{"value":"2026-01-15T00:00:00+01:00"},"maturityDate":{"value":"2027-01-15T00:00:00+01:00"},"interestPaymentDate":{"value":"2026-07-15T00:00:00+02:00"}}"#,
        "interestrates": #"{"interest":"Fest","interestPaymentPeriod":"Halbjährlich","isZeroBond":false,"redemptionPayment":100,"data":[{"id":"InterestRate","fieldValue":{"value":3.375}}]}"#
    ]
    static func session(responses: [String: String] = responses) -> URLSession {
        let id = UUID().uuidString
        INGFixtureProtocol.register(responses, id: id)
        let config = URLSessionConfiguration.ephemeral
        config.httpAdditionalHeaders = ["X-Fixture-ID": id]; config.protocolClasses = [INGFixtureProtocol.self]
        return URLSession(configuration: config)
    }
    static func clear() { INGFixtureProtocol.clear() }
}
private final class INGFixtureProtocol: URLProtocol {
    private static let lock = NSLock()
    private static var maps: [String: [String: String]] = [:]
    static func register(_ map: [String: String], id: String) { lock.lock(); defer { lock.unlock() }; maps[id] = map }
    static func clear() { lock.lock(); defer { lock.unlock() }; maps.removeAll() }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock()
        let map = Self.maps[request.value(forHTTPHeaderField: "X-Fixture-ID") ?? ""] ?? [:]
        let body = map.first { request.url!.pathComponents.contains($0.key) }?.value
        Self.lock.unlock()
        guard let body else { client?.urlProtocol(self, didFailWithError: URLError(.resourceUnavailable)); return }
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil, headerFields: nil)!, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8)); client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}
