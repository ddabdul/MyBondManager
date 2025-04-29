// CashFlowGenerator.swift
// MyBondManager
// Generates and persists cash-flow events for BondEntity
// Updated on 30/04/2025 to add expectedProfit

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
    ///   • a capitalGains event on maturity if delta > 0
    ///   • a capitalLoss event on maturity if delta < 0
    ///   • an expectedProfit event on maturity (sum of all interest + delta)
    func regenerateCashFlows(for bond: BondEntity) throws {
        // 1) Remove old flows
        let fetch: NSFetchRequest<CashFlowEntity> = CashFlowEntity.fetchRequest()
        fetch.predicate = NSPredicate(format: "bond == %@", bond)
        let existing = try context.fetch(fetch)
        existing.forEach(context.delete)

        // 2) Unwrap dates & amounts
        let maturity    = bond.maturityDate
        let acquisition = bond.acquisitionDate
        let nominal     = bond.parValue
        let couponAmt   = nominal * bond.couponRate / 100

        // 3) Generate annual interest payments and sum them
        var sumInterest: Double = 0
        let comps = calendar.dateComponents([.month, .day], from: maturity)
        var nextComp = DateComponents(
            year:  calendar.component(.year, from: acquisition),
            month: comps.month,
            day:   comps.day
        )
        if let first = calendar.date(from: nextComp), first < acquisition {
            nextComp.year! += 1
        }
        while let payDate = calendar.date(from: nextComp), payDate <= maturity {
            let cf = CashFlowEntity(context: context)
            cf.date   = payDate
            cf.amount = couponAmt
            cf.setValue(CashFlowEntity.Nature.interest.rawValue, forKey: "nature")
            cf.bond   = bond

            sumInterest += couponAmt
            nextComp.year! += 1
        }

        // 4) Principal repayment at maturity
        let principalCF = CashFlowEntity(context: context)
        principalCF.date   = maturity
        principalCF.amount = nominal
        principalCF.setValue(CashFlowEntity.Nature.principal.rawValue, forKey: "nature")
        principalCF.bond   = bond

        // 5) Capital gain or loss at maturity
        let delta = nominal - bond.initialPrice

        if delta > 0 {
            let gainCF = CashFlowEntity(context: context)
            gainCF.date   = maturity
            gainCF.amount = delta
            gainCF.setValue(CashFlowEntity.Nature.capitalGains.rawValue, forKey: "nature")
            gainCF.bond   = bond

        } else if delta < 0 {
            let lossCF = CashFlowEntity(context: context)
            lossCF.date   = maturity
            lossCF.amount = delta  // negative
            lossCF.setValue(CashFlowEntity.Nature.capitalLoss.rawValue, forKey: "nature")
            lossCF.bond   = bond
        }

        // 6) Expected profit at maturity = all interest + delta
        let expectedProfit = sumInterest + delta
        let profitCF = CashFlowEntity(context: context)
        profitCF.date   = maturity
        profitCF.amount = expectedProfit
        profitCF.setValue(CashFlowEntity.Nature.expectedProfit.rawValue, forKey: "nature")
        profitCF.bond   = bond

        // 7) Persist changes
        if context.hasChanges {
            try context.save()
        }
    }
}
