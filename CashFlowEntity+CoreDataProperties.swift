// CashFlowEntity+CoreDataProperties.swift
// MyBondManager
// Updated on 29/04/2025 to match Core Data model

import Foundation
import CoreData

extension CashFlowEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<CashFlowEntity> {
        NSFetchRequest<CashFlowEntity>(entityName: "CashFlowEntity")
    }

    // MARK: – Stored Properties (must match your .xcdatamodeld exactly)
    @NSManaged public var date: Date
    @NSManaged public var amount: Double

    // Rename to match your attribute; if your model’s attribute is “nature”:
    @NSManaged public var nature: String

    @NSManaged public var bond: BondEntity?

    // MARK: – Typed Nature Enum
    public enum Nature: String, CaseIterable {
        case interest
        case principal
        case capitalGains
        case capitalLoss
        case expectedProfit
    }

    /// Type-safe wrapper around the raw string
    public var natureEnum: Nature {
        get { Nature(rawValue: nature) ?? .interest }
        set { nature = newValue.rawValue }
    }
}

extension CashFlowEntity: Identifiable {}
