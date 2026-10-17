
//
//  Formatters.swift
//  MyBondManager
//
//  Created by Olivier on 21/04/2025.
//


import Foundation

enum Formatters {
    // MARK: – Currency
    /// “€1,234”
    static let currency: NumberFormatter = {
        let f = NumberFormatter()
        f.numberStyle            = .currency
        f.maximumFractionDigits  = 0
        f.minimumFractionDigits  = 0
        return f
    }()
    
    static let marketMediumDate: DateFormatter = marketFormatter(style: .medium)
    static let marketShortDate: DateFormatter = marketFormatter(style: .short)
    static let marketMonthYear: DateFormatter = {
        let formatter = marketFormatter(style: .short)
        formatter.dateFormat = "MM/yy"
        return formatter
    }()
    private static func marketFormatter(style: DateFormatter.Style) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = MarketDay.calendar
        formatter.timeZone = MarketDay.calendar.timeZone
        formatter.dateStyle = style
        return formatter
    }

    static let paymentCurrency: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency; formatter.currencyCode = "EUR"
        formatter.minimumFractionDigits = 2; formatter.maximumFractionDigits = 6
        return formatter
    }()
    // MARK: – Dates
    /// “Mar 12, 2025”
    static let mediumDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .medium
        return f
    }()
    
    /// “03/25”
    static let monthYear: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "MM/yy"
        return f
    }()
    
    /// “3/12/25”
    static let shortDate: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        return f
    }()
    
    /// Strict parser for ISO‑style dates without times
    static let isoDateOnly: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale     = Locale(identifier: "en_US_POSIX")
        return f
    }()
}


