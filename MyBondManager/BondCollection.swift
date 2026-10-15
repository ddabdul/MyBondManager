import Foundation
import Combine

struct BondDetails: Sendable {
    let name: String
    let wkn: String
    let issuer: String
    let maturityDate: Date?
    let couponRate: Double?
    let terms: BondTerms?
    init(name: String, wkn: String, issuer: String, maturityDate: Date?, couponRate: Double?, terms: BondTerms? = nil) {
        self.name = name; self.wkn = wkn; self.issuer = issuer
        self.maturityDate = maturityDate; self.couponRate = couponRate; self.terms = terms
    }
}

@MainActor
final class BondCollection: ObservableObject {
    @Published var isin = "" {
        didSet {
            if ETFPurchase.normalizedISIN(isin) != ETFPurchase.normalizedISIN(oldValue) {
                requestID = nil; details = nil; isLoading = false; errorMessage = ""
            }
        }
    }
    @Published private(set) var details: BondDetails?
    @Published private(set) var isLoading = false
    @Published private(set) var errorMessage = ""
    private var requestID: UUID?
    private let fetch: (String) async throws -> BondDetails

    init(fetch: @escaping (String) async throws -> BondDetails = { isin in
        try await BondDataScraper().fetchDetails(isin: isin)
    }) { self.fetch = fetch }

    func collect() async {
        let requestedISIN = ETFPurchase.normalizedISIN(isin)
        guard !requestedISIN.isEmpty else { errorMessage = "Enter an ISIN."; return }
        let request = UUID()
        requestID = request; details = nil; isLoading = true; errorMessage = ""
        defer { if requestID == request { isLoading = false } }
        do {
            let result = try await fetch(requestedISIN)
            guard requestID == request, ETFPurchase.normalizedISIN(isin) == requestedISIN else { return }
            guard [result.name, result.wkn, result.issuer].allSatisfy({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) else {
                throw PortfolioError("The provider returned incomplete bond details. Collect the data again before saving.")
            }
            if let rate = result.couponRate, !rate.isFinite || rate < 0 {
                throw PortfolioError("The provider returned an invalid coupon rate.")
            }
            details = result
        } catch {
            if requestID == request { errorMessage = error.localizedDescription }
        }
    }
}
