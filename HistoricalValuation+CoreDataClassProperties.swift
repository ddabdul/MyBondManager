//
//  HistoricalValuation.swift
//  MyBondManager
//
//  Created by Olivier on 08/06/2025.
//

import Foundation
import CoreData

@objc(HistoricalValuation)
public class HistoricalValuation: NSManagedObject {}

extension HistoricalValuation {
    @nonobjc public class func fetchRequest() -> NSFetchRequest<HistoricalValuation> {
        return NSFetchRequest<HistoricalValuation>(entityName: "HistoricalValuation")
    }

    @NSManaged public var id: UUID
    @NSManaged public var date: Date
    @NSManaged public var assetType: String // "Bond" or "ETF"
    @NSManaged public var depotBank: String? // Only for bonds
    @NSManaged public var investedCapital: NSDecimalNumber
    @NSManaged public var interestReceived: NSDecimalNumber? // Optional for ETFs
    @NSManaged public var capitalGains: NSDecimalNumber
}

