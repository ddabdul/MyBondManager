//
//  BondEntity+CoreDataProperties.swift
//  MyBondManager
//
//  Created by Olivier on 25/04/2025.
//
//

import Foundation
import CoreData


extension BondEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<BondEntity> {
        return NSFetchRequest<BondEntity>(entityName: "BondEntity")
    }

    @NSManaged public var id: UUID?
    @NSManaged public var name: String?
    @NSManaged public var issuer: String?
    @NSManaged public var isin: String?
    @NSManaged public var wkn: String?
    @NSManaged public var parValue: Double
    @NSManaged public var initialPrice: Double
    @NSManaged public var couponRate: Double
    @NSManaged public var depotBank: String?
    @NSManaged public var acquisitionDate: Date?
    @NSManaged public var yieldToMaturity: Double

}

extension BondEntity : Identifiable {

}
