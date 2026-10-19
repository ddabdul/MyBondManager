import Foundation

struct PortfolioReportData {
    struct Maturity: Identifiable {
        let year: Int
        let principal: Double
        let share: Double
        let purchaseYTM: Double?
        let yieldCoveredPrincipal: Double
        var id: Int { year }
    }
    struct Issuer: Identifiable {
        let name: String
        let principal: Double
        let share: Double
        let averageMaturityYears: Double
        var id: String { name }
    }
    struct Interest: Identifiable {
        let year: Int
        let amount: Double
        var id: Int { year }
    }
    let principal: Double
    let holdingCount: Int
    let maturities: [Maturity]
    let issuers: [Issuer]
    let interest: [Interest]
    let interestReceipts: [CalendarReceipt]
    let exclusions: [CashFlowCalendarData.Exclusion]
    let missingYieldCount: Int

    static func build(bonds: [BondEntity], bank: String, today: MarketDay) -> Self {
        let active = bonds.filter { (bank == "All" || $0.depotBank == bank) && BondEligibility.isActive($0, on: today) }
        let valid = active.filter { $0.parValue.isFinite && $0.parValue > 0 }
        let principal = valid.reduce(0.0) { $0 + $1.parValue }
        let cash = CashFlowCalendarData.build(bonds: valid, from: today, through: try! MarketDay("2199-12-31"), kind: .interest)
        var issues = Dictionary(uniqueKeysWithValues: cash.exclusions.map { ($0.id, $0) })
        for bond in active where !bond.parValue.isFinite || bond.parValue <= 0 {
            issues[bond.id] = .init(id: bond.id, name: bond.name, reason: "Nominal principal is missing or invalid; this holding is excluded from reporting.")
        }
        var yields: [UUID: Double] = [:]
        for bond in valid {
            do {
                if let value = try BondTermsStore.validatedPreview(bond, from: today)?.estimatedYTM, value.isFinite {
                    yields[bond.id] = value
                }
            } catch {
                issues[bond.id] = .init(id: bond.id, name: bond.name, reason: error.localizedDescription)
            }
        }
        let maturity = Dictionary(grouping: valid, by: { BondEligibility.contractualMaturityDay($0).year })
        let maturities = maturity.keys.sorted().map { year in
            let holdings = maturity[year] ?? []
            let nominal = holdings.reduce(0.0) { $0 + $1.parValue }
            let covered = holdings.filter { yields[$0.id] != nil }
            let coveredPrincipal = covered.reduce(0.0) { $0 + $1.parValue }
            let weighted = covered.reduce(0.0) { $0 + (yields[$1.id] ?? 0) * $1.parValue }
            return Maturity(year: year, principal: nominal, share: principal > 0 ? nominal / principal : 0,
                purchaseYTM: coveredPrincipal > 0 ? weighted / coveredPrincipal : nil, yieldCoveredPrincipal: coveredPrincipal)
        }
        let issuerGroups = Dictionary(grouping: valid, by: { bond in
            let name = bond.issuer.trimmingCharacters(in: .whitespacesAndNewlines)
            return name.isEmpty ? "Unknown issuer" : name
        })
        var issuers: [Issuer] = []
        for (name, holdings) in issuerGroups {
            let nominal: Double = holdings.reduce(0.0) { $0 + $1.parValue }
            let share: Double = principal > 0 ? nominal / principal : 0
            let weightedDays = holdings.reduce(0.0) { total, bond in
                let maturity = BondEligibility.contractualMaturityDay(bond)
                let days = MarketDay.calendar.dateComponents([.day], from: today.instant, to: maturity.instant).day!
                return total + Double(max(0, days)) * bond.parValue
            }
            issuers.append(Issuer(name: name, principal: nominal, share: share,
                averageMaturityYears: weightedDays / nominal / 365.25))
        }
        issuers.sort {
            if $0.principal == $1.principal { return $0.name < $1.name }
            return $0.principal > $1.principal
        }
        let coupons = Dictionary(grouping: cash.receipts, by: { $0.paymentDay.year })
        var interest: [Interest] = []
        if let lastYear = coupons.keys.max() {
            for year in today.year...lastYear {
                let amount = (coupons[year] ?? []).reduce(0.0) { $0 + $1.amount }
                interest.append(Interest(year: year, amount: amount))
            }
        }
        return Self(principal: principal, holdingCount: valid.count, maturities: maturities, issuers: issuers,
            interest: interest, interestReceipts: cash.receipts,
            exclusions: issues.values.sorted { $0.name == $1.name ? $0.id.uuidString < $1.id.uuidString : $0.name < $1.name },
            missingYieldCount: valid.count - yields.count)
    }
}
