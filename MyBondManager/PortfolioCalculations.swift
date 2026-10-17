enum PortfolioCalculations {
    static func expectedReturn(interest: Double, gains: Double, signedLosses: Double) -> Double {
        interest + gains + signedLosses
    }
}
