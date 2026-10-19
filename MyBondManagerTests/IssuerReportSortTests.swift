import XCTest
@testable import MyBondManager

final class IssuerReportSortTests: XCTestCase {
    private let rows: [PortfolioReportData.Issuer] = [
        .init(name: "Alpha", principal: 100000, share: 0.2, averageMaturityYears: 2),
        .init(name: "Charlie", principal: 300000, share: 0.6, averageMaturityYears: 10),
        .init(name: "Bravo", principal: 100000, share: 0.2, averageMaturityYears: 0.5)
    ]

    func testDefaultAndRepeatedPrincipalClicksToggleNumericallyWithStableNameTies() {
        var sort = IssuerReportSort()
        XCTAssertEqual(sort.sorted(rows).map(\.name), ["Charlie", "Alpha", "Bravo"])
        sort.select(.principal)
        XCTAssertEqual(sort.sorted(rows).map(\.name), ["Alpha", "Bravo", "Charlie"])
        sort.select(.principal)
        XCTAssertEqual(sort.sorted(rows).map(\.name), ["Charlie", "Alpha", "Bravo"])
    }

    func testIssuerAndMaturityColumnsSortBothDirectionsWithoutChangingValues() {
        var sort = IssuerReportSort()
        sort.select(.issuer)
        XCTAssertEqual(sort.sorted(rows).map(\.name), ["Alpha", "Bravo", "Charlie"])
        sort.select(.issuer)
        XCTAssertEqual(sort.sorted(rows).map(\.name), ["Charlie", "Bravo", "Alpha"])
        sort.select(.averageMaturity)
        XCTAssertEqual(sort.sorted(rows).map(\.averageMaturityYears), [10, 2, 0.5])
        sort.select(.averageMaturity)
        XCTAssertEqual(sort.sorted(rows).map(\.averageMaturityYears), [0.5, 2, 10])
        XCTAssertEqual(sort.sorted([]).count, 0)
        XCTAssertEqual(sort.sorted(rows).reduce(0) { $0 + $1.principal }, 500000)
    }
}
