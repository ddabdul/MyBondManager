import XCTest
@testable import MyBondManager

final class MarketDayTests: XCTestCase {
    func testRejectsNormalizedInvalidDaysAndKeepsNativeDateStrings() throws {
        for invalid in ["2026-02-29", "2026-2-03", "2026-13-01", "0000-01-01", "2026-04-31", "2026-01-01junk"] {
            XCTAssertThrowsError(try MarketDay(invalid))
        }
        let leap = try MarketDay("2028-02-29")
        XCTAssertEqual(try JSONEncoder().encode(leap), Data("\"2028-02-29\"".utf8))
        XCTAssertEqual(try JSONDecoder().decode(MarketDay.self, from: Data("\"2028-02-29\"".utf8)), leap)
    }
    func testMonthAnchorsDoNotDrift() throws {
        let jan = try MarketDay("2028-01-31")
        XCTAssertEqual(try jan.addingMonths(1, anchorDay: 31, endOfMonth: true).rawValue, "2028-02-29")
        XCTAssertEqual(try jan.addingMonths(2, anchorDay: 31, endOfMonth: true).rawValue, "2028-03-31")
        XCTAssertEqual(try MarketDay("2026-04-30").addingMonths(1, anchorDay: 30, endOfMonth: false).rawValue, "2026-05-30")
    }
    func testMarketRoundTripsAcrossDSTAndDeviceZones() throws {
        for raw in ["2026-03-29", "2026-10-25"] {
            let day = try MarketDay(raw)
            XCTAssertEqual(MarketDay(date: day.instant).rawValue, raw)
            var losAngeles = Calendar(identifier: .gregorian)
            losAngeles.timeZone = TimeZone(identifier: "America/Los_Angeles")!
            XCTAssertNotEqual(MarketDay(date: day.instant, calendar: losAngeles).rawValue, raw)
            XCTAssertEqual(try day.addingDays(1).addingDays(-1), day)
        }
    }
}
