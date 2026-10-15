import CoreData

enum BondEligibility {
    static func redemptionDay(_ bond: BondEntity) -> MarketDay {
        if BondTermsStore.isReady(bond), let date = bond.redemptionPaymentDate { return MarketDay(date: date) }
        if let zone = bond.termsLegacyDateZone.flatMap(TimeZone.init(identifier:)) {
            var calendar = MarketDay.calendar; calendar.timeZone = zone
            return MarketDay(date: bond.maturityDate, calendar: calendar)
        }
        return MarketDay(date: bond.maturityDate, calendar: .current)
    }
    static func isActive(_ bond: BondEntity, on day: MarketDay) -> Bool { redemptionDay(bond) >= day }
    static func excludedCount(_ bonds: [BondEntity], on day: MarketDay) -> Int {
        bonds.filter { isActive($0, on: day) && !BondTermsStore.isReady($0) }.count
    }
    /// Validate the profile once per holding rather than rebuilding a schedule for every row.
    static func flows(_ bond: BondEntity, from: MarketDay, through: MarketDay) throws -> [CashFlowEntity] {
        guard let preview = try BondTermsStore.validatedPreview(bond, from: from) else { return [] }
        let expected = Dictionary(grouping: preview.flows, by: { $0.contractualDay.rawValue + "|" + $0.nature.rawValue })
        return bond.cashFlowsArray.filter { row in
            guard row.generatedFromTerms, let contractual = row.contractualDay, row.natureEnum != .expectedProfit,
                  let value = expected[contractual + "|" + row.nature]?.first,
                  value.paymentDay <= through, row.date == value.paymentDay.instant,
                  row.amount == value.amount, row.eventIdentity == value.eventIdentity else { return false }
            return true
        }
    }
    static func includes(_ flow: CashFlowEntity, from: MarketDay, through: MarketDay) -> Bool {
        guard let bond = flow.bond else { return false }
        do { return try flows(bond, from: from, through: through).contains(flow) }
        catch { NSLog("Cannot validate forecast for %@: %@", bond.id.uuidString, error.localizedDescription); return false }
    }
    static func nextCoupon(_ bonds: [BondEntity], on day: MarketDay) -> CashFlowEntity? {
        let end = try! MarketDay("2199-12-31")
        return bonds.flatMap { bond -> [CashFlowEntity] in
            do { return try flows(bond, from: day, through: end).filter { $0.natureEnum == .interest && $0.amount > 0 } }
            catch { NSLog("Cannot validate next coupon for %@: %@", bond.id.uuidString, error.localizedDescription); return [] }
        }.min { $0.date < $1.date }
    }
    static func weightedYTM(_ bonds: [BondEntity]) throws -> Double? {
        var nominal = 0.0, weighted = 0.0
        for bond in bonds {
            if let yield = try BondTermsStore.estimatedYTM(bond) { nominal += bond.parValue; weighted += yield * bond.parValue }
        }
        return nominal > 0 ? weighted / nominal : nil
    }
}
