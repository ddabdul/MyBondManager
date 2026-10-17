import XCTest
@testable import MyBondManager

enum CurveFixtures {
    static func quotes(tenor: Int = 3) throws -> CurveMarketQuotes {
        let values: [(Int, Double)] = tenor == 3 ? [(1,0.03037),(2,0.03205),(3,0.03264),(5,0.03287),(7,0.03327),(10,0.03407),(15,0.03508),(30,0.03384)] : [(1,0.03172),(2,0.03331),(3,0.03384),(5,0.03395),(7,0.03424),(10,0.03486),(15,0.03555),(30,0.03383)]
        return CurveMarketQuotes(indexTenorMonths: tenor, quoteDay: try MarketDay("2026-10-08"),
            depositRate: tenor == 3 ? 0.02642 : 0.02936, swaps: values.map { SwapMarketQuote(years: $0.0, rate: $0.1) })
    }
}
final class CurveBootstrapTests: XCTestCase {
    func testRecordedMarketDepositRepricesForMatchingIndex() throws {
        for tenor in [3,6] {
            let quotes = try CurveFixtures.quotes(tenor: tenor)
            let result = try QuantLibBondMath.forwards(quotes: quotes, fixingDays: [MarketDay("2026-10-08")])
            let observation = try XCTUnwrap(result.observations.first)
            XCTAssertEqual(observation.valueDay.rawValue, "2026-10-12")
            XCTAssertEqual(observation.indexEndDay.rawValue, tenor == 3 ? "2027-01-12" : "2027-04-12")
            XCTAssertEqual(observation.rate, tenor == 3 ? 0.02642 : 0.02936, accuracy: 1e-6)
            XCTAssertLessThanOrEqual(result.calibration.maxDepositResidual, 1e-6)
            XCTAssertLessThanOrEqual(result.calibration.maxSwapResidual, 1e-6)
            XCTAssertEqual(result.calibration.quantLibVersion, "1.44")
        }
    }
    func testCalibrationWithoutProbesAndNoHorizonExtrapolation() throws {
        let quotes = try CurveFixtures.quotes()
        let result = try QuantLibBondMath.forwards(quotes: quotes, fixingDays: [])
        XCTAssertTrue(result.observations.isEmpty)
        XCTAssertGreaterThan(result.calibration.lastCurveDay, try MarketDay("2056-10-08"))
        XCTAssertThrowsError(try QuantLibBondMath.forwards(quotes: quotes, fixingDays: [MarketDay("2060-01-15")]))
    }
    func testMissingPillarsAndNonfiniteQuotesAreRejected() throws {
        let valid = try CurveFixtures.quotes()
        let incomplete = CurveMarketQuotes(indexTenorMonths: 3, quoteDay: valid.quoteDay,
            depositRate: valid.depositRate, swaps: Array(valid.swaps.dropLast()))
        XCTAssertThrowsError(try QuantLibBondMath.forwards(quotes: incomplete, fixingDays: []))
        let invalid = CurveMarketQuotes(indexTenorMonths: 3, quoteDay: valid.quoteDay,
            depositRate: .nan, swaps: valid.swaps)
        XCTAssertThrowsError(try QuantLibBondMath.forwards(quotes: invalid, fixingDays: []))
    }
    func testIndependentNonSpotForwardFixtures() throws {
        for (tenor, expected) in [(3, 0.030998676706575447), (6, 0.0327148)] {
            let result = try QuantLibBondMath.forwards(quotes: CurveFixtures.quotes(tenor: tenor),
                fixingDays: [MarketDay("2027-04-08")])
            XCTAssertEqual(try XCTUnwrap(result.observations.first).rate, expected, accuracy: 1e-6)
        }
    }
    func testAlternatingConcurrentRequestsAndFailureDoNotLeakState() async throws {
        let first = try CurveFixtures.quotes(), second = try CurveFixtures.quotes(tenor: 6)
        let later = CurveMarketQuotes(indexTenorMonths: 6, quoteDay: try MarketDay("2026-10-09"),
            depositRate: second.depositRate, swaps: second.swaps)
        try await withThrowingTaskGroup(of: (Int, Double).self) { group in
            for index in 0..<32 {
                group.addTask {
                    let quotes = index.isMultiple(of: 2) ? first : later
                    let result = try QuantLibBondMath.forwards(quotes: quotes, fixingDays: [quotes.quoteDay])
                    return (index, try XCTUnwrap(result.observations.first).rate)
                }
            }
            for try await (index, rate) in group { XCTAssertEqual(rate, index.isMultiple(of: 2) ? 0.02642 : 0.02936, accuracy: 1e-6) }
        }
        XCTAssertThrowsError(try QuantLibBondMath.forwards(quotes: first, fixingDays: [MarketDay("2100-01-15")]))
        let after = try QuantLibBondMath.forwards(quotes: first, fixingDays: [MarketDay("2027-04-08")])
        XCTAssertEqual(try XCTUnwrap(after.observations.first).rate, 0.030998676706575447, accuracy: 1e-6)
        XCTAssertEqual(try QuantLibBondMath.following(MarketDay("2026-04-03")).rawValue, "2026-04-07")
    }
}
