import Foundation
import CoreData

struct CashFlowGenerator {
    let context: NSManagedObjectContext
    func regenerateAllCashFlows(now: Date = Date()) throws -> Int {
        let day = MarketDay(date: now)
        let bonds = try context.fetch(BondEntity.fetchRequest()).filter { BondEligibility.isActive($0, on: day) }
        for bond in bonds { try regenerateCashFlows(for: bond, now: now) }
        return BondEligibility.excludedCount(bonds, on: day)
    }
    func regenerateCashFlows(for bond: BondEntity) throws {
        try regenerateCashFlows(for: bond, now: Date())
    }
    func regenerateCashFlows(for bond: BondEntity, now: Date) throws {
        guard let preview = try BondTermsStore.validatedPreview(bond, from: MarketDay(date: now)),
              let terms = try BondTermsStore.read(bond),
              let zone = bond.termsLegacyDateZone else {
            bond.termsReady = false; bond.termsIssue = "Needs review before recalculating payments."
            return
        }
        try BondTermsStore.replaceProjections(for: bond, terms: terms, preview: preview, now: now,
            acquisitionDay: BondTermsStore.trade(bond).acquisitionDay, legacyDateZone: zone, context: context,
            projectionContext: BondTermsStore.projectionContext(bond))
    }
}
