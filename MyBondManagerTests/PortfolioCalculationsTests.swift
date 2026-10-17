import XCTest
@testable import MyBondManager

final class PortfolioCalculationsTests: XCTestCase {
    func testSignedPremiumLossReducesExpectedReturn() {
        XCTAssertEqual(PortfolioCalculations.expectedReturn(interest: 0, gains: 0, signedLosses: -100), -100)
        XCTAssertEqual(PortfolioCalculations.expectedReturn(interest: 50, gains: 20, signedLosses: -100), -30)
    }
}
