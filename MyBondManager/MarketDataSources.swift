import Foundation

/// Editable provider endpoints. No credentials or instrument identities belong here.
struct MarketDataSources: Sendable {
    let fixingQuotesURL: URL
    let swapQuotesURLs: [Int: URL]
    let historicalFixingURLs: [Int: URL]
    let sourceName: String

    init(fixingQuotesURL: URL, swapQuotesURLs: [Int: URL], historicalFixingURLs: [Int: URL],
         sourceName: String = "cf.com / Deutsche Bundesbank") throws {
        for url in [fixingQuotesURL] + Array(swapQuotesURLs.values) + Array(historicalFixingURLs.values) {
            guard url.scheme?.lowercased() == "https", url.host != nil,
                  url.user == nil, url.password == nil, url.fragment == nil else {
                throw MarketDataError("Market source URL must use HTTPS without credentials: \(url.host ?? "invalid host").")
            }
        }
        guard !sourceName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw MarketDataError("sourceName must not be empty.")
        }
        self.fixingQuotesURL = fixingQuotesURL
        self.swapQuotesURLs = swapQuotesURLs
        self.historicalFixingURLs = historicalFixingURLs
        self.sourceName = sourceName
    }

    static func bundled(bundle: Bundle = .main) throws -> Self {
        guard let url = bundle.url(forResource: "MarketDataSources", withExtension: "plist") else {
            throw MarketDataError("Missing MarketDataSources.plist provider configuration.")
        }
        let file = try PropertyListDecoder().decode(Configuration.self, from: Data(contentsOf: url))
        func endpoint(_ value: String) throws -> URL {
            guard let url = URL(string: value) else { throw MarketDataError("Invalid provider endpoint URL.") }
            return url
        }
        func endpoints(_ values: [String: String]) throws -> [Int: URL] {
            var result: [Int: URL] = [:]
            for (key, value) in values {
                guard let tenor = Int(key), [1, 3, 6, 12].contains(tenor) else {
                    throw MarketDataError("Unknown source index tenor: \(key).")
                }
                result[tenor] = try endpoint(value)
            }
            return result
        }
        return try Self(fixingQuotesURL: endpoint(file.fixingQuotesURL),
            swapQuotesURLs: endpoints(file.swapQuotesURLs), historicalFixingURLs: endpoints(file.historicalFixingURLs),
            sourceName: file.sourceName)
    }
    private struct Configuration: Decodable {
        let fixingQuotesURL: String
        let swapQuotesURLs: [String: String]
        let historicalFixingURLs: [String: String]
        let sourceName: String
    }
}
