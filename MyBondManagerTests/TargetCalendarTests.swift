import XCTest
@testable import MyBondManager

final class TargetCalendarTests: XCTestCase {
    func testFollowingAcrossConsecutiveHolidaysAndYearBoundaries() throws {
        for (input, expected) in [("2026-04-03", "2026-04-07"), ("2026-05-01", "2026-05-04"),
            ("2027-01-01", "2027-01-04"), ("2026-12-25", "2026-12-28"),
            ("2026-12-28", "2026-12-28"), ("1999-12-31", "2000-01-03"),
            ("1999-04-02", "1999-04-02"), ("2001-12-31", "2002-01-02"),
            ("2002-12-31", "2002-12-31"), ("2028-02-29", "2028-02-29")] {
            XCTAssertEqual(try TargetCalendar.following(MarketDay(input)).rawValue, expected)
        }
    }
    func testOutOfRangeAdjustmentFailsExplicitly() throws {
        XCTAssertThrowsError(try TargetCalendar.following(MarketDay("2200-01-01")))
    }
}
