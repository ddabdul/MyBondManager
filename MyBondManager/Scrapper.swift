//  MyBondManager
// BondDataScraperAsync.swift
// Converted to async/await (macOS 13+)
//  Adjusted to CoreData
//  Created by Olivier on 26/04/2025.
//



import Foundation

public enum ScrapError: Error {
    case invalidURL
    case noData
    case httpError(Int)
    case decodingError(Error)
    case dateParsingError(String)
    case unknownError(Error)
}

extension ScrapError: LocalizedError {
    public var errorDescription: String? {
        switch self {
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

private struct INGInstrumentHeaderResponse: Decodable { let name: String; let wkn: String }
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
    private let decoder = JSONDecoder()
    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    public init() {}

    public func fetchNameAndWKN(isin: String) async throws -> (name: String, wkn: String) {
        guard let url = URL(string: "https://component-api.wertpapiere.ing.de/api/v1/components/instrumentheader/\(isin)?assetClass=Bond") else {
            throw ScrapError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
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
        let (data, response) = try await URLSession.shared.data(from: url)
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
        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ScrapError.httpError(http.statusCode)
        }
        let decoded = try decoder.decode(INGBondDatesResponse.self, from: data)
        guard let issue = dateFormatter.date(from: String(decoded.issueDate.value.split(separator: "T").first!)),
              let maturity = dateFormatter.date(from: String(decoded.maturityDate.value.split(separator: "T").first!)) else {
            throw ScrapError.dateParsingError("Invalid date format")
        }
        return (issue, maturity)
    }

    public func fetchCouponRate(isin: String) async throws -> Double {
        guard let url = URL(string: "https://component-api.wertpapiere.ing.de/api/v1/bond/interestrates/\(isin)") else {
            throw ScrapError.invalidURL
        }
        let (data, response) = try await URLSession.shared.data(from: url)
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
