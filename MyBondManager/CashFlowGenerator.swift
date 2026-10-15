import Foundation
import CoreData

struct CashFlowGenerator {
    let context: NSManagedObjectContext
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
            acquisitionDay: BondTermsStore.trade(bond).acquisitionDay, legacyDateZone: zone, context: context)
    }
}
