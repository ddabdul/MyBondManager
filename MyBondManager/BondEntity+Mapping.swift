//
//  Bond Entity + Mappingswift
//  MyBondManager
//
//  Created by Olivier on 25/04/2025.
//


import Foundation
import CoreData

extension BondEntity {
    /// Update this entity’s fields from a Codable Bond, computing YTM once
    func update(from bond: Bond) {
        self.id = bond.id
        self.name = bond.name
        self.issuer = bond.issuer
        self.isin = bond.isin
        self.wkn = bond.wkn
        self.parValue = bond.parValue
        self.couponRate = bond.couponRate
        self.initialPrice = bond.initialPrice
        self.maturityDate = bond.maturityDate
        self.acquisitionDate = bond.acquisitionDate
        self.depotBank = bond.depotBank

        // compute & store YTM once
        let days = Calendar.current
            .dateComponents([.day], from: bond.acquisitionDate, to: bond.maturityDate)
            .day ?? 0
        let years = max(Double(days) / 365.0, 0.000_001)
        let C = (bond.couponRate / 100.0) * bond.parValue
        let F = bond.parValue
        let P = bond.initialPrice
        let n = years
        let numerator   = C + (F - P) / n
        let denominator = (F + P) / 2.0
        self.yieldToMaturity = numerator / denominator
    }

    /// Convert this entity back to a Bond struct
    func toBond() -> Bond {
        return Bond(
            id: self.id,
            name: self.name,
            issuer: self.issuer,
            isin: self.isin,
            wkn: self.wkn,
            parValue: self.parValue,
            couponRate: self.couponRate,
            initialPrice: self.initialPrice,
            maturityDate: self.maturityDate,
            acquisitionDate: self.acquisitionDate,
            depotBank: self.depotBank
        )
    }
}
