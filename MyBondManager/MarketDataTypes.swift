import Foundation

struct SwapMarketQuote: Codable, Equatable, Sendable {
    let years: Int
    let rate: Double
}
struct PublishedFixing: Codable, Equatable, Sendable {
    let day: MarketDay
    let rate: Double
}
struct CurveMarketQuotes: Codable, Equatable, Sendable {
    let indexTenorMonths: Int
    let quoteDay: MarketDay
    let depositRate: Double
    let swaps: [SwapMarketQuote]
}
struct MarketDataPayload: Codable, Equatable, Sendable {
    let formatVersion: Int
    let method: String
    let sourceName: String
    let quotes: CurveMarketQuotes
    let historicalFixings: [PublishedFixing]
}
struct CurveCalibrationDiagnostics: Codable, Equatable, Sendable {
    let quantLibVersion: String
    let maxDepositResidual: Double
    let maxSwapResidual: Double
    let lastCurveDay: MarketDay
}
struct MarketDataSnapshot: Codable, Equatable, Sendable {
    let id: String
    let payload: MarketDataPayload
    let calibration: CurveCalibrationDiagnostics
    let retrievedAt: Date
}
struct ParsedPublicRates: Equatable, Sendable {
    let quoteDay: MarketDay
    let decimalRatesByMonths: [Int: Double]
}

struct MarketDataError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}
