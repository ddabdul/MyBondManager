import Foundation

enum TargetCalendar {
    static func isBusinessDay(_ day: MarketDay) -> Bool {
        let weekday = MarketDay.calendar.component(.weekday, from: day.instant)
        if weekday == 1 || weekday == 7 { return false }
        let month = day.month, date = day.day, year = day.year
        if (month == 1 && date == 1) || (month == 12 && date == 25) { return false }
        if month == 12 && date == 31 && [1998, 1999, 2001].contains(year) { return false }
        if year >= 2000 {
            if (month == 5 && date == 1) || (month == 12 && date == 26) { return false }
            let easter = easterSunday(year)
            let offset = MarketDay.calendar.dateComponents([.day], from: easter, to: day.instant).day!
            if offset == -2 || offset == 1 { return false }
        }
        return true
    }
    static func following(_ day: MarketDay) throws -> MarketDay {
        guard (1900...2199).contains(day.year) else { throw PortfolioError("TARGET dates must be in 1900...2199.") }
        for offset in 0..<14 {
            let candidate = try day.addingDays(offset)
            guard (1900...2199).contains(candidate.year) else { throw PortfolioError("TARGET adjustment is out of range.") }
            if isBusinessDay(candidate) { return candidate }
        }
        throw PortfolioError("No TARGET payment day could be determined.")
    }
    private static func easterSunday(_ year: Int) -> Date {
        // Gregorian computus; the calendar's supported range is enforced by following.
        let a = year % 19, b = year / 100, c = year % 100
        let d = b / 4, e = b % 4, f = (b + 8) / 25
        let g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30
        let i = c / 4, k = c % 4
        let l = (32 + 2 * e + 2 * i - h - k) % 7
        let m = (a + 11 * h + 22 * l) / 451
        let value = h + l - 7 * m + 114
        return MarketDay.calendar.date(from: DateComponents(year: year, month: value / 31, day: value % 31 + 1))!
    }
}
