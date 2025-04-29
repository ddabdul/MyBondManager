// CashFlowGenerator.swift
// MyBondManager
// Generates and persists cash-flow events for BondEntity
// Updated on 01/05/2025 to adjust principal for gains vs losses

import Foundation
import CoreData

struct CashFlowGenerator {
    let context: NSManagedObjectContext
    private let calendar = Calendar.current

    /// Regenerates all cash flows for a given bond.
    /// - Deletes any existing CashFlowEntity for that bond.
    /// - Creates:
    ///   • interest events on each anniversary up to & including maturity
    ///   • a principal event on maturity (acquisitionPrice if gain, else nominal)
    ///   • a capitalGains event on maturity if delta > 0
    ///   • a capitalLoss event on maturity if delta < 0
    ///   • an expectedProfit event on maturity (sum of all interest + delta)
    func regenerateCashFlows(for bond: BondEntity) throws {
        // 1) Remove old flows
        let request: NSFetchRequest<CashFlowEntity> = CashFlowEntity.fetchRequest()
        request.predicate = NSPredicate(format: "bond == %@", bond)
        let old = try context.fetch(request)
        old.forEach(context.delete)

        // 2) Unwrap
        let maturity       = bond.maturityDate
        let acquisition    = bond.acquisitionDate
        let nominal        = bond.parValue
        let acquisitionCost = bond.initialPrice
        let couponAmt      = nominal * bond.couponRate / 100

        // 3) Coupons
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
            cf.natureEnum = .interest
            cf.bond   = bond
            sumInterest += couponAmt
            nextComp.year! += 1
        }

        // 4) Compute delta & principal amount
        let delta = nominal - acquisitionCost

        let principalAmt: Double = delta > 0
            ? acquisitionCost    // you only get back your cost when there's a gain
            : nominal            // otherwise you still get the full nominal

        let principalCF = CashFlowEntity(context: context)
        principalCF.date   = maturity
        principalCF.amount = principalAmt
        principalCF.natureEnum = .principal
        principalCF.bond   = bond

        // 5) Capital gain or loss
        if delta > 0 {
            let gainCF = CashFlowEntity(context: context)
            gainCF.date   = maturity
            gainCF.amount = delta
            gainCF.natureEnum = .capitalGains
            gainCF.bond   = bond

        } else if delta < 0 {
            let lossCF = CashFlowEntity(context: context)
            lossCF.date   = maturity
            lossCF.amount = delta  // negative
            lossCF.natureEnum = .capitalLoss
            lossCF.bond   = bond
        }

        // 6) Expected profit
        let expectedProfit = sumInterest + delta
        let profitCF = CashFlowEntity(context: context)
        profitCF.date   = maturity
        profitCF.amount = expectedProfit
        profitCF.natureEnum = .expectedProfit
        profitCF.bond   = bond

        // 7) Persist
        if context.hasChanges {
            try context.save()
        }
    }
}
