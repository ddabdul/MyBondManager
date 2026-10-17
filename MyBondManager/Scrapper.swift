//  MyBondManager
// BondDataScraperAsync.swift
// Converted to async/await (macOS 13+)
//  Adjusted to CoreData
//  Created by Olivier on 26/04/2025.
//



import Foundation

public enum ScrapError: Error {
    case invalidURL
    case invalidISIN
    case noData
    case httpError(Int)
    case decodingError(Error)
    case dateParsingError(String)
    case unknownError(Error)
}

extension ScrapError: LocalizedError {
    public var errorDescription: String? {
        switch self {
        case .invalidISIN:
            return "Enter one 12-character ISIN. Remove extra text or different identifiers pasted together."
        case .invalidURL:
            return "The ISIN you entered isn’t a valid URL."
        case .noData:
            return "No data was returned by the server."
        case .httpError(let code):
            return "Server responded with HTTP \(code)."
        case .decodingError(let err):
            return "Failed to parse server response: \(err.localizedDescription)"
        case .dateParsingError(let msg):
            return "Date parsing error: \(msg)"
        case .unknownError(let err):
            return "Unexpected error: \(err.localizedDescription)"
        }
    }
}

private struct INGInstrumentHeaderResponse: Decodable {
    let name: String
    let wkn: String

    private enum CodingKeys: String, CodingKey {
        case name = "instrumentName"
        case wkn
    }
}
private struct INGBondDatesResponse: Decodable {
    struct DateInfo: Decodable { let value: String }
    let maturityDate: DateInfo
    let issueDate: DateInfo
}
private struct INGMasterDataResponse: Decodable {
    struct IssuerInfo: Decodable { let value: String }
    let issuerCompanyName: IssuerInfo
}
private struct INGBondInterestRatesResponse: Decodable {
    struct Element: Decodable {
        let id: String
        let fieldValue: FieldValue
        struct FieldValue: Decodable {
            let value: Double?
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                if let d = try? c.decode(Double.self, forKey: .value) { value = d }
                else if let s = try? c.decode(String.self, forKey: .value), let d = Double(s) { value = d }
                else { value = nil }
            }
            private enum CodingKeys: String, CodingKey { case value }
        }
    }
    let data: [Element]
}

@available(macOS 13.0, *)
public class BondDataScraper {
    private let session: URLSession
    private let decoder = JSONDecoder()
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    public init(session: URLSession = .shared) { self.session = session }

    public func fetchNameAndWKN(isin: String) async throws -> (name: String, wkn: String) {
        guard let url = URL(string: "https://component-api.wertpapiere.ing.de/api/v1/components/localheader/\(isin)") else {
            throw ScrapError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ScrapError.httpError(http.statusCode)
        }
        let decoded = try decoder.decode(INGInstrumentHeaderResponse.self, from: data)
        return (decoded.name, decoded.wkn)
    }

    public func fetchIssuer(isin: String) async throws -> String {
        guard let url = URL(string: "https://component-api.wertpapiere.ing.de/api/v1/bond/masterdata/\(isin)?assetClass=Bond") else {
            throw ScrapError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ScrapError.httpError(http.statusCode)
        }
        let decoded = try decoder.decode(INGMasterDataResponse.self, from: data)
        return decoded.issuerCompanyName.value
    }

    public func fetchDates(isin: String) async throws -> (issue: Date, maturity: Date) {
        guard let url = URL(string: "https://component-api.wertpapiere.ing.de/api/v1/bond/dates/\(isin)") else {
            throw ScrapError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ScrapError.httpError(http.statusCode)
        }
        let decoded = try decoder.decode(INGBondDatesResponse.self, from: data)
        guard let issuePart = decoded.issueDate.value.split(separator: "T").first,
              let maturityPart = decoded.maturityDate.value.split(separator: "T").first,
              let issue = dateFormatter.date(from: String(issuePart)),
              let maturity = dateFormatter.date(from: String(maturityPart)) else {
            throw ScrapError.dateParsingError("Invalid date format")
        }
        return (issue, maturity)
    }

    public func fetchCouponRate(isin: String) async throws -> Double {
        guard let url = URL(string: "https://component-api.wertpapiere.ing.de/api/v1/bond/interestrates/\(isin)") else {
            throw ScrapError.invalidURL
        }
        let (data, response) = try await session.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ScrapError.httpError(http.statusCode)
        }
        let decoded = try decoder.decode(INGBondInterestRatesResponse.self, from: data)
        guard let el = decoded.data.first(where: { $0.id == "InterestRate" }), let rate = el.fieldValue.value else {
            throw ScrapError.decodingError(NSError(domain: "", code: 0, userInfo: [NSLocalizedDescriptionKey: "InterestRate missing"]))
        }
        return rate
    }
}

private enum INGTermScalar: Decodable {
    case string(String), number(Double), boolean(Bool)
    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        if let value = try? box.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? box.decode(Double.self) { self = .number(value) }
        else { self = .string(try box.decode(String.self)) }
    }
    var text: String? { if case .string(let value) = self { return value }; return nil }
    func number() throws -> Double {
        let value: Double?
        switch self { case .number(let v): value = v; case .string(let v): value = Double(v); case .boolean: value = nil }
        guard let value, value.isFinite else { throw PortfolioError("ING supplied an invalid numeric term.") }
        return value
    }
    func boolean() throws -> Bool? {
        switch self {
        case .boolean(let v): return v
        case .string(let v):
            switch v.lowercased() { case "ja", "true": return true; case "nein", "false": return false; default: return nil }
        case .number: throw PortfolioError("ING supplied an invalid boolean term.")
        }
    }
}
private struct INGTermValue: Decodable { let value: INGTermScalar? }
private struct INGRichDates: Decodable {
    let maturityDate: INGTermValue?
    let issueDate: INGTermValue?
    let interestStartDate: INGTermValue?
    let interestPaymentDate: INGTermValue?
}
private struct INGRichMaster: Decodable {
    let issuerCompanyName: INGTermValue?
    let currencyIsoCode: INGTermValue?
    let isBondCallableBeforeMaturity: INGTermValue?
}
private struct INGRichRates: Decodable {
    struct Row: Decodable { let id: String; let fieldValue: INGTermValue? }
    let interest: INGTermScalar?
    let interestPaymentPeriod: INGTermScalar?
    let isZeroBond: INGTermScalar?
    let redemptionPayment: INGTermScalar?
    let data: [Row]?
    func field(_ id: String) -> INGTermScalar? { data?.first { $0.id == id }?.fieldValue?.value }
}
extension BondDataScraper {
    func fetchDetails(isin: String, observedAt: Date = Date()) async throws -> BondDetails {
        let normalized = ETFPurchase.normalizedISIN(isin)
        guard normalized.utf8.count == 12,
              normalized.prefix(2).utf8.allSatisfy({ (65...90).contains($0) }),
              normalized.suffix(1).utf8.allSatisfy({ (48...57).contains($0) }),
              normalized.utf8.allSatisfy({ (48...57).contains($0) || (65...90).contains($0) }) else {
            throw ScrapError.invalidISIN
        }
        let header: INGInstrumentHeaderResponse = try await fetchTermsComponent("components/localheader", isin: normalized)
        let master: INGRichMaster = try await fetchTermsComponent("bond/masterdata", isin: normalized)
        let dates: INGRichDates = try await fetchTermsComponent("bond/dates", isin: normalized)
        let rates: INGRichRates = try await fetchTermsComponent("bond/interestrates", isin: normalized)
        var terms = BondTerms()
        terms.isin = normalized; terms.collectedAt = observedAt; terms.checkpointObservedOn = MarketDay(date: observedAt)
        terms.currency = master.currencyIsoCode?.value?.text
        terms.callable = try master.isBondCallableBeforeMaturity?.value?.boolean()
        terms.couponRate = try rates.field("InterestRate")?.number()
        terms.redemptionPercent = try (rates.redemptionPayment ?? rates.field("RedemptionPayment"))?.number()
        if let rate = terms.couponRate, rate < 0 { throw PortfolioError("ING supplied a negative coupon rate.") }
        if let redemption = terms.redemptionPercent, redemption <= 0 { throw PortfolioError("ING supplied a nonpositive redemption percentage.") }
        terms.rawStructure = (rates.interest ?? rates.field("Interest"))?.text
        terms.rawFrequency = (rates.interestPaymentPeriod ?? rates.field("InterestPaymentPeriod"))?.text
        if let period = terms.rawFrequency { terms.frequency = ["Jährlich":1, "Halbjährlich":2, "Vierteljährlich":4][period] }
        let zero = try (rates.isZeroBond ?? rates.field("IsZeroBond"))?.boolean()
        if zero == true {
            terms.structure = .zero
            if let rate = terms.couponRate, rate != 0 { terms.restrictions.append("Zero-coupon flag contradicts supplied coupon.") }
        } else if terms.rawStructure == "Fest" { terms.structure = .fixed }
        else if terms.rawStructure?.localizedCaseInsensitiveContains("variabel") == true { terms.structure = .floating }
        else if let raw = terms.rawStructure { terms.restrictions.append("Unsupported interest structure: " + raw) }
        for marker in ["floating", "variabel", "inflation", "index", "perpetual", "ewig", "amort", "ex-coupon"] {
            if (header.name + " " + (terms.rawStructure ?? "")).localizedCaseInsensitiveContains(marker) { terms.restrictions.append(marker) }
        }
        terms.maturity = try instrumentDay(dates.maturityDate)
        terms.issueDay = try instrumentDay(dates.issueDate)
        terms.accrualStart = try instrumentDay(dates.interestStartDate)
        terms.nextCoupon = try instrumentDay(dates.interestPaymentDate)
        return BondDetails(name: header.name, wkn: header.wkn, issuer: master.issuerCompanyName?.value?.text ?? "",
            maturityDate: terms.maturity?.instant, couponRate: terms.couponRate, terms: terms)
    }
    private func fetchTermsComponent<T: Decodable>(_ component: String, isin: String) async throws -> T {
        let query = component == "bond/masterdata" ? "?assetClass=Bond" : ""
        guard let url = URL(string: "https://component-api.wertpapiere.ing.de/api/v1/\(component)/\(isin)\(query)") else { throw ScrapError.invalidURL }
        let (data, response) = try await session.data(from: url)
        guard let http = response as? HTTPURLResponse else { throw ScrapError.noData }
        guard (200...299).contains(http.statusCode) else { throw ScrapError.httpError(http.statusCode) }
        return try decoder.decode(T.self, from: data)
    }
    private func instrumentDay(_ info: INGTermValue?) throws -> MarketDay? {
        guard let scalar = info?.value else { return nil }
        guard let raw = scalar.text else { throw ScrapError.dateParsingError("Expected an instrument calendar date.") }
        let day = try MarketDay(String(raw.prefix(10)))
        if raw.count != 10 {
            let iso = ISO8601DateFormatter()
            let fractional = ISO8601DateFormatter(); fractional.formatOptions.insert(.withFractionalSeconds)
            guard raw.dropFirst(10).first == "T", iso.date(from: raw) != nil || fractional.date(from: raw) != nil else {
                throw ScrapError.dateParsingError("Invalid instrument date: " + raw)
            }
        }
        return day
    }
}
