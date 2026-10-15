//  BondEntity+CoreDataProperties.swift
//  MyBondManager
//
//  Created by Olivier on 28/04/2025.
//

import Foundation
import CoreData

extension BondEntity {

    @nonobjc public class func fetchRequest() -> NSFetchRequest<BondEntity> {
        return NSFetchRequest<BondEntity>(entityName: "BondEntity")
    }

    @NSManaged public var acquisitionDate: Date
    @NSManaged public var couponRate: Double
    @NSManaged public var depotBank: String
    @NSManaged public var id: UUID
    @NSManaged public var initialPrice: Double
    @NSManaged public var isin: String
    @NSManaged public var issuer: String
    @NSManaged public var maturityDate: Date
    @NSManaged public var name: String
    @NSManaged public var parValue: Double
    @NSManaged public var wkn: String
    @NSManaged public var yieldToMaturity: Double

    @NSManaged public var termsData: Data?
    @NSManaged public var termsDraftData: Data?
    @NSManaged public var termsReady: Bool
    @NSManaged public var termsIssue: String?
    @NSManaged public var termsAcquisitionDay: String?
    @NSManaged public var termsLegacyDateZone: String?
    @NSManaged public var termsEffectiveFrom: String?
    @NSManaged public var eventsActivateAfter: Date?
    @NSManaged public var redemptionPaymentDate: Date?
    @NSManaged public var legacyEventAliasesData: Data?

    // Use Set<> instead of NSSet
    @NSManaged public var cashFlows: Set<CashFlowEntity>?
}

// MARK: - Convenience Accessors

extension BondEntity {
    /// Sorted array of cash flows
    public var cashFlowsArray: [CashFlowEntity] {
        (cashFlows ?? []).sorted { $0.date < $1.date }
    }

    @objc(addCashFlowsObject:)
    @NSManaged public func addToCashFlows(_ value: CashFlowEntity)

    @objc(removeCashFlowsObject:)
    @NSManaged public func removeFromCashFlows(_ value: CashFlowEntity)

    @objc(addCashFlows:)
    @NSManaged public func addToCashFlows(_ values: Set<CashFlowEntity>)

    @objc(removeCashFlows:)
    @NSManaged public func removeFromCashFlows(_ values: Set<CashFlowEntity>)
}

extension BondEntity : Identifiable {}

