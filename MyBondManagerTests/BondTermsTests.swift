import XCTest
@testable import MyBondManager

final class BondTermsTests: XCTestCase {
    func testMissingProviderValuesRemainUnknownAfterPersistence() throws {
        let original = BondTerms()
        let restored = try JSONDecoder().decode(BondTerms.self, from: JSONEncoder().encode(original))
        XCTAssertNil(restored.frequency)
        XCTAssertNil(restored.callable)
        XCTAssertNil(restored.couponRate)
        XCTAssertNil(restored.maturity)
        XCTAssertEqual(restored.conventions.sources["calendar"], .assumed)
        XCTAssertEqual(restored, original)
    }
}
