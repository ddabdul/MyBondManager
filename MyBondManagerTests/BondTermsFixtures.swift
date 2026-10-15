import Foundation
@testable import MyBondManager

enum BondTermsFixtures {
    static func fixed(frequency: Int = 2, maturity: String = "2027-01-15", next: String = "2026-07-15") throws -> BondTerms {
        var terms = BondTerms()
        terms.isin = "DE0000000001"; terms.currency = "EUR"; terms.structure = .fixed
        terms.frequency = frequency; terms.couponRate = 3.375
        terms.accrualStart = try MarketDay("2026-01-15")
        terms.maturity = try MarketDay(maturity); terms.nextCoupon = try MarketDay(next)
        terms.checkpointObservedOn = try MarketDay("2026-02-01")
        terms.callable = false; terms.redemptionPercent = 100; terms.roll = .dayOfMonth
        terms.collectedAt = TestPortfolio.date("2026-02-01T12:00:00Z")
        return terms
    }
}

extension BondTermsFixtures {
    static func trade(cost: Double = 100000) throws -> BondTrade {
        BondTrade(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, isin: "DE0000000001",
            nominal: 100000, cost: cost, acquisitionDay: try MarketDay("2026-02-01"), bank: "Bank")
    }
}

extension BondTermsFixtures {
    static func details() throws -> BondDetails {
        let terms = try fixed()
        return BondDetails(name: "EUR note", wkn: "TEST01", issuer: "Issuer", maturityDate: terms.maturity?.instant,
            couponRate: terms.couponRate, terms: terms)
    }
}
