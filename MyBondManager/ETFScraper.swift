//  MyBondManager
//  InstrumentHeaderScraperAsync.swift
//  Converted to async/await (macOS 13+)
//  Created by Olivier on 30/04/2025.

import Foundation

@available(macOS 13.0, *)
public class InstrumentHeaderScraper {
    private let decoder = JSONDecoder()

    public init() {}

    /// Errors thrown by the scraper
    public enum ScrapError: Error {
        case invalidURL
        case noData
        case httpError(Int)
        case decodingError(Error)
        case unknownError(Error)
    }

    /// Model returned to callers with all relevant ETF header info
    public struct ETFInstrumentHeader {
        public let name: String
        public let wkn: String
        public let price: Double
        public let close: Double?
        public let changePercent: Double?
        public let changeAbsolute: Double?
        public let instrumentType: String?
        public let currency: String?
    }

    /// Raw response from the ETF instrument header endpoint
    private struct ETFInstrumentHeaderResponse: Decodable {
        let name: String
        let wkn: String
        let price: Double
        let close: Double?
        let changePercent: Double?
        let changeAbsolute: Double?
        let instrumentTypeDisplayName: String?
        let currency: String?
    }

    /// Fetches the current price only for a given ISIN.
    /// - Parameter isin: The ISIN of the instrument.
    /// - Returns: The latest price as a Double.
    public func fetchPrice(isin: String) async throws -> Double {
        let urlString = "https://component-api.wertpapiere.ing.de/api/v1/components/instrumentheader/\(isin)"
        guard let url = URL(string: urlString) else {
            throw ScrapError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ScrapError.httpError(http.statusCode)
        }

        do {
            let decoded = try decoder.decode(ETFInstrumentHeaderResponse.self, from: data)
            return decoded.price
        } catch {
            throw ScrapError.decodingError(error)
        }
    }

    /// Fetches detailed header information for a given ISIN.
    /// - Parameter isin: The ISIN of the instrument.
    /// - Returns: An ETFInstrumentHeader containing name, wkn, price, and more.
    public func fetchInstrumentHeader(isin: String) async throws -> ETFInstrumentHeader {
        let urlString = "https://component-api.wertpapiere.ing.de/api/v1/components/instrumentheader/\(isin)"
        guard let url = URL(string: urlString) else {
            throw ScrapError.invalidURL
        }

        let (data, response) = try await URLSession.shared.data(from: url)
        if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
            throw ScrapError.httpError(http.statusCode)
        }

        do {
            let decoded = try decoder.decode(ETFInstrumentHeaderResponse.self, from: data)
            return ETFInstrumentHeader(
                name: decoded.name,
                wkn: decoded.wkn,
                price: decoded.price,
                close: decoded.close,
                changePercent: decoded.changePercent,
                changeAbsolute: decoded.changeAbsolute,
                instrumentType: decoded.instrumentTypeDisplayName,
                currency: decoded.currency
            )
        } catch {
            throw ScrapError.decodingError(error)
        }
    }
}
