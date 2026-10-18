import CoreData

struct BondBaseline: Codable, Equatable, Sendable {
    let id: UUID
    let isin: String
    let name: String
    let issuer: String
    let wkn: String
    let bank: String
    let acquisition: Date
    let maturity: Date
    let nominal: Double
    let cost: Double
    let rate: Double
    let terms: Data?
    static func capture(_ bond: BondEntity) -> Self {
        Self(id: bond.id, isin: ETFPurchase.normalizedISIN(bond.isin), name: bond.name, issuer: bond.issuer,
            wkn: bond.wkn, bank: bond.depotBank, acquisition: bond.acquisitionDate, maturity: bond.maturityDate,
            nominal: bond.parValue, cost: bond.initialPrice, rate: bond.couponRate, terms: bond.termsData)
    }
}
struct BondTermsDraft: Codable, Equatable, Sendable {
    let baseline: BondBaseline
    let trade: BondTrade
    let legacyDateZone: String
    var proposed: BondTerms
    var previewDay: MarketDay
    var projectionContext: ProjectionContext? = nil
}
enum BondTermsStore {
    private static let previewCache = BondPreviewCache()
    private struct Envelope<T: Codable>: Codable { let version: Int; let value: T }
    private struct Profile: Codable {
        let terms: BondTerms
        let trade: BondTrade
        let acquisitionInstant: Date
        let projectionContext: ProjectionContext?
    }
    static func encode<T: Codable>(_ value: T) throws -> Data {
        let encoder = JSONEncoder()
        return try encoder.encode(Envelope(version: 1, value: value))
    }
    static func decode<T: Codable>(_ type: T.Type, _ data: Data) throws -> T {
        let decoder = JSONDecoder()
        let envelope = try decoder.decode(Envelope<T>.self, from: data)
        guard envelope.version == 1 else { throw PortfolioError("Unsupported saved bond terms version.") }
        return envelope.value
    }
    static func read(_ bond: BondEntity) throws -> BondTerms? {
        try bond.termsData.map { try decode(Profile.self, $0).terms }
    }
    static func projectionContext(_ bond: BondEntity) throws -> ProjectionContext? {
        try bond.termsData.map { try decode(Profile.self, $0).projectionContext } ?? nil
    }
    static func trade(_ bond: BondEntity) throws -> BondTrade {
        let day: MarketDay
        if let raw = bond.termsAcquisitionDay { day = try MarketDay(raw) }
        else { day = MarketDay(date: bond.acquisitionDate, calendar: .current) }
        return BondTrade(id: bond.id, isin: ETFPurchase.normalizedISIN(bond.isin), nominal: bond.parValue,
            cost: bond.initialPrice, acquisitionDay: day, bank: bond.depotBank)
    }
    @discardableResult
    static func stageDraft(_ draft: BondTermsDraft, for bond: BondEntity) throws -> BondTermsDraft {
        var saved = draft
        if ![.floating, .fixedToFloating].contains(saved.proposed.structure) { saved.projectionContext = nil }
        bond.termsDraftData = try encode(saved)
        if bond.termsAcquisitionDay == nil { bond.termsAcquisitionDay = draft.trade.acquisitionDay.rawValue }
        if bond.termsLegacyDateZone == nil { bond.termsLegacyDateZone = draft.legacyDateZone }
        return saved
    }
    static func readDraft(_ bond: BondEntity) throws -> BondTermsDraft? {
        try bond.termsDraftData.map { try decode(BondTermsDraft.self, $0) }
    }
    static func sameInstrumentTerms(_ lhs: BondTerms, _ rhs: BondTerms) -> Bool {
        var left = lhs, right = rhs
        left.isin = ETFPurchase.normalizedISIN(left.isin); right.isin = ETFPurchase.normalizedISIN(right.isin)
        left.approvedAt = nil; right.approvedAt = nil
        left.collectedAt = nil; right.collectedAt = nil
        return left == right
    }
    @discardableResult
    static func reuseApprovedTerms(for isin: String, targetIDs: Set<UUID>? = nil, in context: NSManagedObjectContext, now: Date) throws -> Bool {
        let bonds = try context.fetch(BondEntity.fetchRequest()).filter { ETFPurchase.normalizedISIN($0.isin) == isin }
        guard Set(bonds.map(\.id)).count == bonds.count else { throw PortfolioError("Stored bonds contain duplicate identifiers.") }
        let day = MarketDay(date: now)
        var candidates: [BondTerms] = []
        for bond in bonds {
            if let terms = try read(bond), terms.approvedAt != nil,
                ETFPurchase.normalizedISIN(terms.isin) == isin,
                (terms.couponRate ?? 0) == bond.couponRate, terms.maturity == MarketDay(date: bond.maturityDate) {
                candidates.append(terms)
            }
        }
        guard let canonical = candidates.max(by: { $0.approvedAt! < $1.approvedAt! }) else { return false }
        guard candidates.filter({ $0.approvedAt == canonical.approvedAt }).allSatisfy({ sameInstrumentTerms($0, canonical) }) else {
            throw PortfolioError("Conflicting approvals for ISIN " + isin + ". Review this instrument explicitly.")
        }
        for bond in bonds {
            guard let proposed = try readDraft(bond)?.proposed else { continue }
            let newRestrictions = !Set(proposed.restrictions).isSubset(of: Set(canonical.restrictions))
            let newDeferral = proposed.interestDeferral == true && canonical.interestDeferral != true
            let newVariableStructure = [.floating, .fixedToFloating].contains(proposed.structure) && proposed.structure != canonical.structure
            let newFirstCoupon = proposed.verifiedTermsSource != nil && proposed.firstCoupon != nil && proposed.firstCoupon != canonical.firstCoupon
            // Reuse must not waive safeguards discovered by a newer collection.
            if newRestrictions || newDeferral || newVariableStructure || newFirstCoupon { return false }
        }
        for bond in bonds where targetIDs.map({ $0.contains(bond.id) }) ?? true {
            if try read(bond) == canonical, try validatedPreview(bond, from: day) != nil { continue }
            let pending = try readDraft(bond)
            let trade = try trade(bond)
            let zone = bond.termsLegacyDateZone ?? TimeZone.current.identifier
            var selectedContext: ProjectionContext?
            for candidate in bonds where try read(candidate)?.approvedAt == canonical.approvedAt {
                selectedContext = try projectionContext(candidate); break
            }
            let preview = try BondSchedule.preview(trade: trade, terms: canonical, from: day, context: selectedContext)
            guard preview.assessment.supported else {
                bond.termsIssue = preview.assessment.reasons.joined(separator: " ")
                continue
            }
            try replaceProjections(for: bond, terms: canonical, preview: preview, now: now,
                acquisitionDay: trade.acquisitionDay, legacyDateZone: zone, context: context, projectionContext: selectedContext)
            if let pending, (!pending.proposed.confirmedFields.isEmpty || pending.proposed.conventions.sources.values.contains(.confirmed)),
                !sameInstrumentTerms(pending.proposed, canonical) {
                var proposed = pending.proposed; proposed.approvedAt = nil
                try stageDraft(BondTermsDraft(baseline: BondBaseline.capture(bond), trade: trade,
                    legacyDateZone: zone, proposed: proposed, previewDay: day, projectionContext: pending.projectionContext), for: bond)
            }
        }
        return true
    }
    static func clear(_ bond: BondEntity) {
        bond.termsData = nil; bond.termsDraftData = nil; bond.termsReady = false; bond.termsIssue = nil
        bond.termsAcquisitionDay = nil; bond.termsLegacyDateZone = nil; bond.termsEffectiveFrom = nil
        bond.eventsActivateAfter = nil; bond.redemptionPaymentDate = nil; bond.legacyEventAliasesData = nil
    }
    static func validatedPreview(_ bond: BondEntity, from day: MarketDay) throws -> BondSchedulePreview? {
        guard bond.termsReady, let data = bond.termsData else { return nil }
        let profile = try decode(Profile.self, data)
        guard profile.terms.approvedAt != nil, profile.trade == (try trade(bond)),
              profile.acquisitionInstant == bond.acquisitionDate,
              (profile.terms.couponRate ?? 0) == bond.couponRate,
              profile.terms.maturity == MarketDay(date: bond.maturityDate) else { return nil }
        let preview = try previewCache.preview(profile: data, from: day) {
            try BondSchedule.preview(trade: profile.trade, terms: profile.terms, from: day, context: profile.projectionContext)
        }
        return preview.assessment.supported ? preview : nil
    }
    static func isReady(_ bond: BondEntity) -> Bool {
        do { return try validatedPreview(bond, from: MarketDay(date: Date())) != nil }
        catch { NSLog("Bond terms validation failed for %@: %@", bond.id.uuidString, error.localizedDescription); return false }
    }
    static func estimatedYTM(_ bond: BondEntity) throws -> Double? {
        try validatedPreview(bond, from: MarketDay(date: Date()))?.estimatedYTM
    }
    static func legacyAliases(_ bond: BondEntity) throws -> [String: [String]] {
        try bond.legacyEventAliasesData.map { try decode([String: [String]].self, $0) } ?? [:]
    }
    static func projectedPayments(_ bond: BondEntity, from day: MarketDay) throws -> [BondPayment] {
        try validatedPreview(bond, from: day)?.payments ?? []
    }
    static func captureLegacyAliases(_ bond: BondEntity, maturity: MarketDay? = nil,
                                     legacyDateZone: String? = nil) throws -> [String: [String]] {
        let zoneID = legacyDateZone ?? bond.termsLegacyDateZone ?? TimeZone.current.identifier
        guard let zone = TimeZone(identifier: zoneID) else { throw PortfolioError("Invalid local legacy date time zone.") }
        var calendar = MarketDay.calendar; calendar.timeZone = zone
        var aliases = try legacyAliases(bond)
        func retain(_ identity: String, _ date: Date, kind: String) {
            let oldKey = "\(bond.id.uuidString)|\(kind)|\(Int(date.timeIntervalSince1970))"
            aliases[identity] = Array(Set((aliases[identity] ?? []) + [oldKey])).sorted()
        }
        for flow in bond.cashFlowsArray where flow.natureEnum == .interest {
            let identity = flow.eventIdentity ?? "\(bond.id.uuidString)|interest|\(MarketDay(date: flow.date, calendar: calendar).rawValue)"
            retain(identity, flow.date, kind: "interest")
        }
        let prefix = bond.id.uuidString + "|maturity|"
        let target = prefix + (maturity ?? MarketDay(date: bond.maturityDate, calendar: calendar)).rawValue
        var priorKeys = Set(aliases[target] ?? [])
        for (identity, keys) in aliases where identity.hasPrefix(prefix) { priorKeys.formUnion(keys); priorKeys.insert(identity) }
        aliases[target] = priorKeys.sorted()
        retain(target, bond.maturityDate, kind: "maturity")
        return aliases
    }
    static func historyIssue(for bond: BondEntity, payments: [BondPayment], before: Date,
                             context: NSManagedObjectContext) throws -> String? {
        let request = HistoricalValuation.fetchRequest()
        request.predicate = NSPredicate(format: "assetType == %@ AND (eventKey == nil OR eventKey == '') AND date <= %@ AND (depotBank == %@ OR depotBank == nil)",
            AssetType.bond.rawValue, before as NSDate, bond.depotBank)
        let aliases = try legacyAliases(bond)
        for payment in payments where payment.paymentDay.instant <= before {
            guard payment.rateSource == .publishedFixing else { continue }
            let linked = HistoricalValuation.fetchRequest()
            linked.predicate = NSPredicate(format: "eventKey IN %@", [payment.identity] + (aliases[payment.identity] ?? []))
            for row in try context.fetch(linked) {
                let actual = payment.kind == .interest ? row.interestReceived?.doubleValue ?? 0
                    : row.capitalGains.doubleValue + bond.initialPrice
                if abs(actual - payment.amount) > 1e-10 * max(1,abs(payment.amount)) {
                    return "Needs history review: published payment conflicts with an existing receipt. Recorded history was preserved."
                }
            }
        }
        let legacy = try context.fetch(request)
        for payment in payments {
            let end = try payment.paymentDay.addingDays(1).instant
            for record in legacy where record.date >= payment.contractualDay.instant && record.date < end {
                let couldMatch = payment.kind == .interest ? (record.interestReceived?.doubleValue ?? 0) != 0
                    : record.investedCapital.doubleValue < 0
                if couldMatch { return "Needs history review: an unlinked legacy payment overlaps this schedule." }
            }
        }
        return nil
    }
    static func replaceProjections(for bond: BondEntity, terms: BondTerms, preview: BondSchedulePreview,
        now: Date, acquisitionDay: MarketDay, legacyDateZone: String, context: NSManagedObjectContext, projectionContext: ProjectionContext? = nil) throws {
        guard TimeZone(identifier: legacyDateZone) != nil else { throw PortfolioError("Invalid legacy date time zone.") }
        let day = MarketDay(date: now)
        let trade = BondTrade(id: bond.id, isin: ETFPurchase.normalizedISIN(bond.isin), nominal: bond.parValue,
            cost: bond.initialPrice, acquisitionDay: acquisitionDay, bank: bond.depotBank)
        let verified = try BondSchedule.preview(trade: trade, terms: terms, from: day, context: projectionContext)
        guard verified == preview else { throw PortfolioError("Payment preview changed before application.") }
        guard verified.assessment.supported, terms.approvedAt != nil else {
            bond.termsReady = false; bond.termsIssue = verified.assessment.reasons.joined(separator: "\n")
            return
        }
        let priorApproval = try read(bond)?.approvedAt
        let activation = priorApproval == terms.approvedAt ? (bond.eventsActivateAfter ?? now) : now
        let receipts = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay(date: activation), context: projectionContext)
        guard receipts.assessment.supported else { throw PortfolioError(receipts.assessment.reasons.joined(separator: " ")) }
        if let issue = try historyIssue(for: bond, payments: receipts.payments.filter { $0.paymentDay.instant > activation }, before: now, context: context) {
            bond.termsReady = false; bond.termsIssue = issue; return
        }
        let aliases = try captureLegacyAliases(bond, maturity: terms.maturity, legacyDateZone: legacyDateZone)
        let prior = try read(bond)
        if bond.eventsActivateAfter == nil || prior?.approvedAt != terms.approvedAt { bond.eventsActivateAfter = now }
        for flow in bond.cashFlowsArray where MarketDay(date: flow.date) >= day { context.delete(flow) }
        for value in verified.flows {
            let flow = CashFlowEntity(context: context)
            flow.date = value.paymentDay.instant; flow.amount = value.amount; flow.natureEnum = value.nature
            flow.contractualDay = value.contractualDay.rawValue; flow.eventIdentity = value.eventIdentity
            flow.generatedFromTerms = true; flow.bond = bond
        }
        bond.couponRate = terms.couponRate ?? 0; bond.maturityDate = terms.maturity!.instant
        bond.yieldToMaturity = verified.estimatedYTM ?? 0
        bond.termsData = try encode(Profile(terms: terms, trade: trade, acquisitionInstant: bond.acquisitionDate, projectionContext: [.floating, .fixedToFloating].contains(terms.structure) ? projectionContext : nil))
        bond.termsAcquisitionDay = acquisitionDay.rawValue; bond.termsLegacyDateZone = legacyDateZone
        bond.termsEffectiveFrom = day.rawValue; bond.redemptionPaymentDate = verified.redemptionDay?.instant
        bond.termsReady = true; bond.termsIssue = nil; bond.termsDraftData = nil
        bond.legacyEventAliasesData = try encode(aliases)
    }
}
