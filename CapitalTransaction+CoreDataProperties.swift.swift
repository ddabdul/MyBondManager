//
//  CapitalTransaction+CoreDataProperties.swift
//  MyBondManager
//
//  Created by Olivier on 15/06/2025.
//


import Foundation
import CoreData

extension CapitalTransaction {

  @nonobjc public class func fetchRequest() -> NSFetchRequest<CapitalTransaction> {
    return NSFetchRequest<CapitalTransaction>(entityName: "CapitalTransaction")
  }

  @NSManaged public var date: Date
  @NSManaged public var amount: Double
  @NSManaged public var type: String
  @NSManaged public var bond: BondEntity?
  @NSManaged public var etf: ETFEntity?

}

extension CapitalTransaction: Identifiable { }
