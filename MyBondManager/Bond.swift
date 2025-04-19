//
//  Bond.swift
//  MyBondManager
//
//  Created by Olivier on 19/04/2025.
//

import Foundation

struct Bond: Identifiable, Codable {
    var id: UUID = UUID()

    // MARK: — Core fields
    var name: String
    var issuer: String
    var isin: String
    var wkn: String

    /// Face (par) value of the bond
    var parValue: Double

    /// Annual coupon rate (percent, e.g. 3.5 for 3.5%)
    var couponRate: Double

    /// Acquisition price
    var initialPrice: Double

    /// When the bond matures
    var maturityDate: Date

    /// When you acquired it
    var acquisitionDate: Date

    /// Your depot / custodian
    var depotBank: String

    // MARK: — Computed YTM

    /// Estimated Yield‑to‑Maturity at time of acquisition, via:
    ///
    ///    YTM = ( C + (F – P) / n )  ÷  ( (F + P) / 2 )
    ///
    /// • C = coupon payment per year
    /// • F = parValue
    /// • P = initialPrice
    /// • n = years to maturity (fractional)
    var yieldAtAcquisition: Double {
        // 1) compute fractional years between acquisition and maturity
        let days = Calendar.current
            .dateComponents([.day], from: acquisitionDate, to: maturityDate)
            .day ?? 0
        // guard against zero-day or negative
        let years = max(Double(days) / 365.0, 0.000_001)

        // 2) coupon payment C
        let C = (couponRate / 100.0) * parValue
        let F = parValue
        let P = initialPrice
        let n = years

        // 3) apply formula
        let numerator   = C + (F - P) / n
        let denominator = (F + P) / 2.0

        return numerator / denominator
    }
}


