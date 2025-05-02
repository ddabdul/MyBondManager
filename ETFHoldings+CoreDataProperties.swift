//
//  ETFHoldings+CoreDataProperties.swift
//  MyBondManager
//
//  Created by Olivier on 30/04/2025.
//
//

import Foundation
import CoreData


extension ETFHoldings {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ETFHoldings> {
        return NSFetchRequest<ETFHoldings>(entityName: "ETFHoldings")
    }

    @NSManaged public var acquisitionDate: Date
    @NSManaged public var acquisitionPrice: Double
    @NSManaged public var numberOfShares: Int32
    @NSManaged public var holdingtoetf: ETFEntity

}
extension ETFHoldings {
    /// total cost of this lot
    var cost: Double {
        Double(numberOfShares) * acquisitionPrice
    }
    /// current market value of this lot
    var marketValue: Double {
        Double(numberOfShares) * (holdingtoetf.lastPrice)
    }
    /// profit or loss
    var profit: Double {
        marketValue - cost
    }
    /// percent gain
    var pctGain: Double {
        cost > 0 ? (profit / cost * 100) : 0
    }
    /// days held (at least 1, to avoid division by zero)
    var daysHeld: Int {
        let raw = Calendar.current.dateComponents(
            [.day],
            from: acquisitionDate,
            to: Date()
        ).day ?? 0
        return max(raw, 1)
    }
    /// annualized yield as (lastPrice – acquisitionPrice)/daysHeld * 365
    var annualYield: Double {
        let diff = holdingtoetf.lastPrice - acquisitionPrice
        return diff / Double(daysHeld) * 365
    }
}

extension ETFHoldings : Identifiable {

}
