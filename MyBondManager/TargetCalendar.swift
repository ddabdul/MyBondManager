import Foundation

enum TargetCalendar {
    static func following(_ day: MarketDay) throws -> MarketDay {
        try QuantLibBondMath.following(day)
    }
}
