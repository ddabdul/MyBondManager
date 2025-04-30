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
    @NSManaged public var etftoholding: NSSet
    @NSManaged public var etfPriceMany: NSSet

}

// MARK: Generated accessors for etftoholding
extension ETFEntity {

    @objc(addEtftoholdingObject:)
    @NSManaged public func addToEtftoholding(_ value: ETFHoldings)

    @objc(removeEtftoholdingObject:)
    @NSManaged public func removeFromEtftoholding(_ value: ETFHoldings)

    @objc(addEtftoholding:)
    @NSManaged public func addToEtftoholding(_ values: NSSet)

    @objc(removeEtftoholding:)
    @NSManaged public func removeFromEtftoholding(_ values: NSSet)

}

// MARK: Generated accessors for etfPriceMany
extension ETFEntity {

    @objc(addEtfPriceManyObject:)
    @NSManaged public func addToEtfPriceMany(_ value: ETFPrice)

    @objc(removeEtfPriceManyObject:)
    @NSManaged public func removeFromEtfPriceMany(_ value: ETFPrice)

    @objc(addEtfPriceMany:)
    @NSManaged public func addToEtfPriceMany(_ values: NSSet)

    @objc(removeEtfPriceMany:)
    @NSManaged public func removeFromEtfPriceMany(_ values: NSSet)

}

extension ETFEntity : Identifiable {

}
