// CashFlowGenerator.swift
// MyBondManager
// Generates and persists cash-flow events for BondEntity
// Updated by ChatGPT on 30/04/2025.

import Foundation
import CoreData

struct CashFlowGenerator {
    let context: NSManagedObjectContext
    private let calendar = Calendar.current

    /// Regenerates all cash flows for a given bond.
    /// - Deletes any existing CashFlowEntity for that bond.
    /// - Creates:
    ///   • interest events on each anniversary up to & including maturity
    ///   • a principal event on maturity (nominal)
    ///   • a capitalGains event on maturity (nominal – acquisitionPrice)
    func regenerateCashFlows(for bond: BondEntity) throws {
        // 1) Remove old flows
        let fetch: NSFetchRequest<CashFlowEntity> = CashFlowEntity.fetchRequest()
        fetch.predicate = NSPredicate(format: "bond == %@", bond)
        let existing = try context.fetch(fetch)
        existing.forEach(context.delete)

        // 2) Unwrap dates & amounts
        let maturity = bond.maturityDate
        let acquisition = bond.acquisitionDate
        let nominal = bond.parValue
        let couponAmt = nominal * bond.couponRate / 100

        // 3) Generate annual interest payments
        let comps = calendar.dateComponents([.month, .day], from: maturity)
        var nextComp = DateComponents(
            year: calendar.component(.year, from: acquisition),
            month: comps.month,
            day: comps.day
        )
        // If the first anniversary is before acquisition, bump to next year
        if let first = calendar.date(from: nextComp), first < acquisition {
            nextComp.year! += 1
        }
        // Loop until maturity
        while let payDate = calendar.date(from: nextComp), payDate <= maturity {
            let cf = CashFlowEntity(context: context)
            cf.date = payDate
            cf.amount = couponAmt
            // Use rawValue since 'nature' is a String attribute
            cf.setValue(CashFlowEntity.Nature.interest.rawValue, forKey: "nature")
            cf.bond = bond
            nextComp.year! += 1
        }

        // 4) Principal repayment at maturity
        let principalCF = CashFlowEntity(context: context)
        principalCF.date = maturity
        principalCF.amount = nominal
        principalCF.setValue(CashFlowEntity.Nature.principal.rawValue, forKey: "nature")
        principalCF.bond = bond

        // 5) Capital gain at maturity
        let gain = nominal - bond.initialPrice
        // Only persist a capital-gains flow if the gain is positive
        if gain > 0 {
            let gainCF = CashFlowEntity(context: context)
            gainCF.date = maturity
            gainCF.amount = gain
            gainCF.setValue(CashFlowEntity.Nature.capitalGains.rawValue, forKey: "nature")
            gainCF.bond = bond
        }

        // 6) Persist changes if any
        if context.hasChanges {
            try context.save()
        }
    }
}
