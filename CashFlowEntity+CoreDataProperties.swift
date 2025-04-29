//  CashFlowEntity+CoreDataProperties.swift
//  MyBondManager
//
//  Created by Olivier on 28/04/2025.
//

import Foundation
import CoreData

extension CashFlowEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CashFlowEntity> {
        return NSFetchRequest<CashFlowEntity>(entityName: "CashFlowEntity")
    }

    // MARK: - Stored Properties (must match your .xcdatamodeld exactly)
    @NSManaged public var date: Date
    @NSManaged public var amount: Double
    @NSManaged public var natureRaw: String
    @NSManaged public var bond: BondEntity?

    // MARK: - Typed Nature Enum
    public enum Nature: String, CaseIterable {
        case interest
        case principal
        case capitalGains
        case capitalLoss
        case expectedProfit
    }

    /// A Swift-native wrapper around the raw string.
    public var nature: Nature {
        get { Nature(rawValue: natureRaw) ?? .interest }
        set { natureRaw = newValue.rawValue }
    }
}

extension CashFlowEntity: Identifiable {}

