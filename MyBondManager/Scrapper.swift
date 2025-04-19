//  ScrapError.swift
//  MyBondManager
//
//  Created by Olivier on 18/04/2025.
//

import SwiftUI
import Foundation

// ——————————————————
// MARK: – BondDataScraper Errors
// ——————————————————
enum ScrapError: Error {
    case invalidURL
    case noData
    case httpError(Int)
    case decodingError(Error)
    case dateParsingError(String)
    case unknownError(Error)
}

extension ScrapError: LocalizedError {
    var errorDescription: String? {
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

// ——————————————————
// MARK: – ING JSON Responses
// ——————————————————
private struct INGInstrumentHeaderResponse: Decodable {
    let name: String
    let wkn: String
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

            // Custom Decoding to accept either Double or String for "value"
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: CodingKeys.self)
                if let d = try? c.decode(Double.self, forKey: .value) {
                    value = d
                } else if let s = try? c.decode(String.self, forKey: .value),
                          let d = Double(s) {
                    value = d
                } else {
                    // Couldn't decode as Double or numeric String
                    value = nil
                }
            }

            private enum CodingKeys: String, CodingKey {
                case value
            }
        }
    }
    let data: [Element]
}

// ——————————————————
// MARK: – BondDataScraper
// ——————————————————
class BondDataScraper {
    
    /// A formatter for exactly "yyyy‑MM‑dd"
    private let dateOnlyFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()
    
    /// 1) Fetches the `name` and `wkn` for the given ISIN.
    func fetchNameAndWKN(fromINGFor isin: String,
                         completion: @escaping (Result<(name: String, wkn: String), ScrapError>) -> Void) {
        let urlString =
            "https://component-api.wertpapiere.ing.de/api/v1/components/instrumentheader/\(isin)?assetClass=Bond"
        guard let url = URL(string: urlString) else {
            return DispatchQueue.main.async { completion(.failure(.invalidURL)) }
        }
        URLSession.shared.dataTask(with: url) { data, response, err in
            if let e = err {
                return DispatchQueue.main.async { completion(.failure(.unknownError(e))) }
            }
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                return DispatchQueue.main.async { completion(.failure(.httpError(http.statusCode))) }
            }
            guard let data = data else {
                return DispatchQueue.main.async { completion(.failure(.noData)) }
            }
            do {
                let decoded = try JSONDecoder()
                    .decode(INGInstrumentHeaderResponse.self, from: data)
                DispatchQueue.main.async {
                    completion(.success((name: decoded.name, wkn: decoded.wkn)))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.decodingError(error)))
                }
            }
        }
        .resume()
    }
    
    /// 1b) Fetches the `issuerCompanyName` for the given ISIN.
    func fetchIssuer(fromINGFor isin: String,
                     completion: @escaping (Result<String, ScrapError>) -> Void) {
        let urlString =
            "https://component-api.wertpapiere.ing.de/api/v1/bond/masterdata/\(isin)?assetClass=Bond"
        guard let url = URL(string: urlString) else {
            return DispatchQueue.main.async { completion(.failure(.invalidURL)) }
        }
        URLSession.shared.dataTask(with: url) { data, response, err in
            if let e = err {
                return DispatchQueue.main.async { completion(.failure(.unknownError(e))) }
            }
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                return DispatchQueue.main.async { completion(.failure(.httpError(http.statusCode))) }
            }
            guard let data = data else {
                return DispatchQueue.main.async { completion(.failure(.noData)) }
            }
            do {
                let decoded = try JSONDecoder()
                    .decode(INGMasterDataResponse.self, from: data)
                DispatchQueue.main.async {
                    completion(.success(decoded.issuerCompanyName.value))
                }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.decodingError(error)))
                }
            }
        }
        .resume()
    }

    /// 2) Fetches the `issueDate` and `maturityDate`, ignoring any time component.
    func fetchDates(fromINGFor isin: String,
                    completion: @escaping (Result<(issue: Date, maturity: Date), ScrapError>) -> Void) {
        let urlString = "https://component-api.wertpapiere.ing.de/api/v1/bond/dates/\(isin)"
        guard let url = URL(string: urlString) else {
            return DispatchQueue.main.async { completion(.failure(.invalidURL)) }
        }
        URLSession.shared.dataTask(with: url) { [weak self] data, response, err in
            guard let self = self else { return }
            if let e = err {
                return DispatchQueue.main.async { completion(.failure(.unknownError(e))) }
            }
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                return DispatchQueue.main.async { completion(.failure(.httpError(http.statusCode))) }
            }
            guard let data = data else {
                return DispatchQueue.main.async { completion(.failure(.noData)) }
            }
            do {
                let decoded = try JSONDecoder()
                    .decode(INGBondDatesResponse.self, from: data)

                func parseDateOnly(_ raw: String) -> Date? {
                    guard let datePart = raw
                          .split(separator: "T", maxSplits: 1)
                          .first else {
                        return nil
                    }
                    return self.dateOnlyFormatter.date(from: String(datePart))
                }

                guard
                    let issue    = parseDateOnly(decoded.issueDate.value),
                    let maturity = parseDateOnly(decoded.maturityDate.value)
                else {
                    throw ScrapError.dateParsingError(
                        "Could not parse dates “\(decoded.issueDate.value)” or “\(decoded.maturityDate.value)”"
                    )
                }

                DispatchQueue.main.async {
                    completion(.success((issue: issue, maturity: maturity)))
                }
            } catch let se as ScrapError {
                DispatchQueue.main.async { completion(.failure(se)) }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.decodingError(error)))
                }
            }
        }
        .resume()
    }

    /// 3) Fetches the coupon rate (InterestRate) for the given ISIN.
    func fetchCouponRate(fromINGFor isin: String,
                         completion: @escaping (Result<Double, ScrapError>) -> Void) {
        let urlString = "https://component-api.wertpapiere.ing.de/api/v1/bond/interestrates/\(isin)"
        guard let url = URL(string: urlString) else {
            return DispatchQueue.main.async { completion(.failure(.invalidURL)) }
        }
        URLSession.shared.dataTask(with: url) { data, response, err in
            if let e = err {
                return DispatchQueue.main.async { completion(.failure(.unknownError(e))) }
            }
            if let http = response as? HTTPURLResponse,
               !(200...299).contains(http.statusCode) {
                return DispatchQueue.main.async { completion(.failure(.httpError(http.statusCode))) }
            }
            guard let data = data else {
                return DispatchQueue.main.async { completion(.failure(.noData)) }
            }
            do {
                let decoded = try JSONDecoder()
                    .decode(INGBondInterestRatesResponse.self, from: data)

                if let el = decoded.data.first(where: { $0.id == "InterestRate" }),
                   let rate = el.fieldValue.value {
                    DispatchQueue.main.async {
                        completion(.success(rate))
                    }
                } else {
                    throw ScrapError.decodingError(
                        NSError(domain: "", code: 0,
                                userInfo: [NSLocalizedDescriptionKey:
                                   "InterestRate field not found"])
                    )
                }
            } catch let se as ScrapError {
                DispatchQueue.main.async { completion(.failure(se)) }
            } catch {
                DispatchQueue.main.async {
                    completion(.failure(.decodingError(error)))
                }
            }
        }
        .resume()
    }
}

// ——————————————————
// MARK: – ISINScraperView
// ——————————————————
struct ISINScraperView: View {
    @State private var isin: String = ""
    @State private var name: String?
    @State private var wkn: String?
    @State private var issuerName: String?
    @State private var issueDate: Date?
    @State private var maturityDate: Date?
    @State private var couponRate: Double?
    @State private var isLoading = false
    @State private var errorMessage: String?

    private let scraper = BondDataScraper()

    var body: some View {
        VStack(spacing: 16) {
            Text("Fetch Bond Data")
                .font(.title2).bold()

            TextField("Enter ISIN (e.g. XS2676816940)", text: $isin)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .padding(.horizontal)

            Button(action: fetch) {
                if isLoading { ProgressView() }
                else         { Text("Fetch").frame(minWidth: 100) }
            }
            .disabled(isLoading || isin.isEmpty)
            .buttonStyle(.borderedProminent)

            Group {
                if let name = name   { Text("Name: \(name)") }
                if let wkn = wkn     { Text("WKN:  \(wkn)") }
                if let issuer = issuerName { Text("Issuer: \(issuer)") }
                if let issue = issueDate   { Text("Issue Date: \(displayFormatter.string(from: issue))") }
                if let mat = maturityDate  { Text("Maturity Date: \(displayFormatter.string(from: mat))") }
                if let coupon = couponRate { Text(String(format: "Coupon: %.3f%%", coupon)) }
            }
            .padding(.top, 8)

            if let err = errorMessage {
                Text("Error: \(err)")
                    .foregroundColor(.red)
                    .padding(.top, 8)
            }

            Spacer()
        }
        .padding(.top, 40)
    }

    private func fetch() {
        // reset
        name = nil; wkn = nil; issuerName = nil
        issueDate = nil; maturityDate = nil; couponRate = nil
        errorMessage = nil
        isLoading = true

        // 1) Fetch name & WKN
        scraper.fetchNameAndWKN(fromINGFor: isin) { result in
            switch result {
            case .success(let pair):
                self.name = pair.name
                self.wkn  = pair.wkn

                // 1b) Fetch issuer
                scraper.fetchIssuer(fromINGFor: isin) { issuerResult in
                    switch issuerResult {
                    case .success(let emittent):
                        self.issuerName = emittent
                    case .failure(let err):
                        self.errorMessage = err.errorDescription
                    }
                }

                // 2) Fetch dates
                scraper.fetchDates(fromINGFor: isin) { dateResult in
                    switch dateResult {
                    case .success(let tup):
                        self.issueDate    = tup.issue
                        self.maturityDate = tup.maturity
                    case .failure(let err):
                        self.errorMessage = err.errorDescription
                    }
                }

                // 3) Fetch coupon rate
                scraper.fetchCouponRate(fromINGFor: isin) { couponResult in
                    DispatchQueue.main.async {
                        self.isLoading = false
                        switch couponResult {
                        case .success(let rate):
                            self.couponRate = rate
                        case .failure(let err):
                            self.errorMessage = err.errorDescription
                        }
                    }
                }

            case .failure(let err):
                self.isLoading = false
                self.errorMessage = err.errorDescription
            }
        }
    }

    private let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()
}

// ——————————————————
// MARK: – Preview
// ——————————————————
struct ISINScraperView_Previews: PreviewProvider {
    static var previews: some View {
        ISINScraperView()
    }
}
