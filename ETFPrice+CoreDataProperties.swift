//
//  ETFPrice+CoreDataProperties.swift
//  MyBondManager
//
//  Created by Olivier on 30/04/2025.
//
//

import Foundation
import CoreData


extension ETFPrice {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ETFPrice> {
        return NSFetchRequest<ETFPrice>(entityName: "ETFPrice")
    }

    @NSManaged public var datePrice: Date?
    @NSManaged public var price: Double
    @NSManaged public var etfPriceHistory: ETFEntity?

}

extension ETFPrice : Identifiable {

}
