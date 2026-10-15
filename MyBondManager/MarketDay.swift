import Foundation

/// A contractual calendar date, independent of a device's time zone.
struct MarketDay: Codable, Hashable, Comparable, Sendable {
    let rawValue: String
    static var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(identifier: "Europe/Berlin")!
        value.locale = Locale(identifier: "en_US_POSIX")
        return value
    }
    init(_ value: String) throws {
        let bytes = Array(value.utf8)
        guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
              bytes.enumerated().allSatisfy({ [4, 7].contains($0.offset) || (48...57).contains($0.element) }),
              let year = Int(value.prefix(4)), (1...9999).contains(year),
              let month = Int(value.dropFirst(5).prefix(2)), let day = Int(value.suffix(2)),
              let date = Self.calendar.date(from: DateComponents(year: year, month: month, day: day)) else {
            throw PortfolioError("Invalid calendar day: \(value). Use YYYY-MM-DD.")
        }
        let check = Self.calendar.dateComponents([.year, .month, .day], from: date)
        guard check.year == year, check.month == month, check.day == day else {
            throw PortfolioError("Invalid calendar day: \(value).")
        }
        rawValue = value
    }
    init(date: Date, calendar: Calendar = Self.calendar) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        rawValue = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
    }
    var year: Int { Int(rawValue.prefix(4))! }
    var month: Int { Int(rawValue.dropFirst(5).prefix(2))! }
    var day: Int { Int(rawValue.suffix(2))! }
    var instant: Date { Self.calendar.date(from: DateComponents(year: year, month: month, day: day))! }
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rawValue < rhs.rawValue }
    func addingDays(_ count: Int) throws -> Self {
        guard let date = Self.calendar.date(byAdding: .day, value: count, to: instant) else {
            throw PortfolioError("Calendar day arithmetic is out of range.")
        }
        return try Self(Self(date: date).rawValue)
    }
    func addingMonths(_ count: Int, anchorDay: Int, endOfMonth: Bool) throws -> Self {
        guard (1...31).contains(anchorDay),
              let start = Self.calendar.date(from: DateComponents(year: year, month: month, day: 1)),
              let target = Self.calendar.date(byAdding: .month, value: count, to: start),
              let days = Self.calendar.range(of: .day, in: .month, for: target) else {
            throw PortfolioError("Calendar month arithmetic is out of range.")
        }
        let parts = Self.calendar.dateComponents([.year, .month], from: target)
        return try Self(String(format: "%04d-%02d-%02d", parts.year!, parts.month!,
            endOfMonth ? days.count : min(anchorDay, days.count)))
    }
    init(from decoder: Decoder) throws {
        let box = try decoder.singleValueContainer()
        try self.init(box.decode(String.self))
    }
    func encode(to encoder: Encoder) throws {
        var box = encoder.singleValueContainer()
        try box.encode(rawValue)
    }
}
