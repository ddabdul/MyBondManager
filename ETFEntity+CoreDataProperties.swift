//
//  ETFEntity+CoreDataProperties.swift
//  MyBondManager
//
//  Created by Olivier on 30/04/2025.
//
//

import Foundation
import CoreData


extension ETFEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<ETFEntity> {
        return NSFetchRequest<ETFEntity>(entityName: "ETFEntity")
    }

    @NSManaged public var etfName: String
    @NSManaged public var isin: String
    @NSManaged public var id: UUID
    @NSManaged public var wkn: String
    @NSManaged public var lastPrice: Double
    @NSManaged public var issuer: String

}

extension ETFEntity : Identifiable {

}
