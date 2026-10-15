import CoreData

enum LaunchEventProcessor {
    static func stage(context: NSManagedObjectContext, since: Date, until: Date) throws -> [String] {
        guard since <= until else { throw PortfolioError("The last launch date is in the future.") }
        var messages: [(Date, String)] = []
        for bond in try context.fetch(BondEntity.fetchRequest()) {
            guard let activation = bond.eventsActivateAfter,
                  let preview = try BondTermsStore.validatedPreview(bond, from: MarketDay(date: since)) else { continue }
            if let issue = try BondTermsStore.historyIssue(for: bond, payments: preview.payments, before: until, context: context) {
                bond.termsReady = false; bond.termsIssue = issue
                continue
            }
            let aliases = try BondTermsStore.legacyAliases(bond)
            for payment in preview.payments {
                let date = payment.paymentDay.instant
                guard date > since, date <= until, date > activation, payment.amount > 0 else { continue }
                let request = HistoricalValuation.fetchRequest()
                request.predicate = NSPredicate(format: "eventKey IN %@", [payment.identity] + (aliases[payment.identity] ?? []))
                guard try context.count(for: request) == 0 else { continue }
                let record = try HistoricalDataRecorder.recordChange(assetType: .bond, depotBank: bond.depotBank,
                    investedDelta: payment.kind == .maturity ? -bond.parValue : 0,
                    interestDelta: payment.kind == .interest ? payment.amount : 0,
                    gainsDelta: payment.kind == .maturity ? payment.amount - bond.initialPrice : 0,
                    date: date, context: context)
                record.eventKey = payment.identity
                let kind = payment.kind == .maturity ? "Matured" : "Coupon"
                let amount = Formatters.currency.string(from: NSNumber(value: payment.amount)) ?? String(payment.amount)
                messages.append((date, "\(bond.name) at \(bond.depotBank): \(kind) \(amount) on \(Formatters.marketMediumDate.string(from: date))"))
            }
        }
        return messages.sorted { $0.0 < $1.0 }.map { $0.1 }
    }
}
