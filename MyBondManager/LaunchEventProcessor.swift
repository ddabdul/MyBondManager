import CoreData

enum LaunchEventProcessor {
    static func stage(context: NSManagedObjectContext, since: Date, until: Date) throws -> [String] {
        guard since <= until else { throw PortfolioError("The last launch date is in the future.") }
        var messages: [(Date, String)] = []
        let bonds = try context.fetch(BondEntity.fetchRequest())
        for bond in bonds {
            if bond.maturityDate > since && bond.maturityDate <= until {
                try record(bond: bond, nature: "maturity", date: bond.maturityDate,
                    invested: -bond.parValue, interest: 0,
                    gains: bond.parValue - bond.initialPrice, amount: bond.parValue,
                    context: context, messages: &messages)
            }
            for flow in bond.cashFlowsArray where flow.nature == CashFlowEntity.Nature.interest.rawValue {
                guard flow.amount > 0, flow.date > since, flow.date <= until,
                      flow.date >= bond.acquisitionDate, flow.date <= bond.maturityDate else { continue }
                try record(bond: bond, nature: "interest", date: flow.date, invested: 0,
                    interest: flow.amount, gains: 0, amount: flow.amount,
                    context: context, messages: &messages)
            }
        }
        return messages.sorted { $0.0 < $1.0 }.map { $0.1 }
    }

    private static func record(bond: BondEntity, nature: String, date: Date,
                               invested: Double, interest: Double, gains: Double, amount: Double,
                               context: NSManagedObjectContext, messages: inout [(Date, String)]) throws {
        let key = "\(bond.id.uuidString)|\(nature)|\(Int(date.timeIntervalSince1970))"
        let request = HistoricalValuation.fetchRequest()
        request.predicate = NSPredicate(format: "eventKey == %@", key)
        request.fetchLimit = 1
        guard try context.count(for: request) == 0 else { return }
        let record = try HistoricalDataRecorder.recordChange(assetType: .bond,
            depotBank: bond.depotBank, investedDelta: invested, interestDelta: interest,
            gainsDelta: gains, date: date, context: context)
        record.eventKey = key
        let kind = nature == "maturity" ? "Matured" : "Coupon"
        let amountText = Formatters.currency.string(from: NSNumber(value: amount)) ?? String(amount)
        messages.append((date, "\(bond.name) at \(bond.depotBank): \(kind) \(amountText) on \(Formatters.mediumDate.string(from: date))"))
    }
}
