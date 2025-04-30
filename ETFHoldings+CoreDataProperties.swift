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

    @NSManaged public var acquisitionDate: Date?
    @NSManaged public var acquisitionPrice: Double
    @NSManaged public var numberOfShares: Int32
    @NSManaged public var holdingtoetf: ETFEntity?

}

extension ETFHoldings : Identifiable {

}
