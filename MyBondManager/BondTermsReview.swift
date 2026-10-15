import CoreData
import Combine

@MainActor
final class BondTermsReview: ObservableObject {
    @Published private(set) var drafts: [UUID: BondTermsDraft] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var isWorking = false
    let container: NSPersistentContainer
    private let fetch: (String) async throws -> BondDetails
    private let now: () -> Date
    init(container: NSPersistentContainer, fetch: @escaping (String) async throws -> BondDetails = {
        try await BondDataScraper().fetchDetails(isin: $0)
    }, now: @escaping () -> Date = Date.init) {
        self.container = container; self.fetch = fetch; self.now = now
    }
    nonisolated private static func resolve(_ id: UUID, in context: NSManagedObjectContext) throws -> BondEntity {
        let request = BondEntity.fetchRequest(); request.predicate = NSPredicate(format: "id == %@", id as CVarArg)
        let matches = try context.fetch(request)
        guard matches.count == 1, let bond = matches.first else { throw PortfolioError("Holding is missing or has duplicate identifiers. Refresh the review.") }
        return bond
    }
    func load() async throws {
        let values = try await container.viewContext.perform {
            var drafts: [UUID: BondTermsDraft] = [:], errors: [String: String] = [:]
            for bond in try self.container.viewContext.fetch(BondEntity.fetchRequest()) {
                do { drafts[bond.id] = try BondTermsStore.readDraft(bond) }
                catch { errors[bond.id.uuidString] = error.localizedDescription }
            }
            return (drafts, errors)
        }
        drafts = values.0; errors = values.1
    }
    func collect(ids: [UUID]) async {
        guard !isWorking else { errors["review"] = "A review operation is already running."; return }
        isWorking = true; errors = [:]; defer { isWorking = false }
        do {
            let reviewDay = MarketDay(date: now())
            let snapshots = try await container.viewContext.perform {
                try Set(ids).map { id -> BondTermsDraft in
                    let bond = try Self.resolve(id, in: self.container.viewContext)
                    let proposed = try BondTermsStore.readDraft(bond)?.proposed ?? BondTermsStore.read(bond) ?? BondTerms()
                    return BondTermsDraft(baseline: BondBaseline.capture(bond), trade: try BondTermsStore.trade(bond),
                        legacyDateZone: bond.termsLegacyDateZone ?? TimeZone.current.identifier, proposed: proposed, previewDay: reviewDay)
                }
            }
            for (isin, positions) in Dictionary(grouping: snapshots, by: { $0.trade.isin }).sorted(by: { $0.key < $1.key }) {
                do {
                    let details = try await fetch(isin)
                    guard let incoming = details.terms, ETFPurchase.normalizedISIN(incoming.isin) == isin else {
                        throw PortfolioError("Provider terms are missing or belong to another ISIN.")
                    }
                    for original in positions {
                        do {
                            let proposed = incoming.preservingConfirmed(from: original.proposed)
                            let draft = BondTermsDraft(baseline: original.baseline, trade: original.trade,
                                legacyDateZone: original.legacyDateZone, proposed: proposed, previewDay: MarketDay(date: now()))
                            try await PortfolioTransaction.run(in: container) { context in
                                let bond = try Self.resolve(draft.trade.id, in: context)
                                guard BondBaseline.capture(bond) == draft.baseline else { throw PortfolioError("Holding changed while collecting. Refresh its review.") }
                                try BondTermsStore.stageDraft(draft, for: bond)
                            }
                            drafts[draft.trade.id] = draft
                        } catch { errors[original.trade.id.uuidString] = error.localizedDescription }
                    }
                } catch { errors[isin] = error.localizedDescription }
            }
        } catch { errors["review"] = error.localizedDescription }
    }
    func preview(_ draft: BondTermsDraft) throws -> BondSchedulePreview {
        try BondSchedule.preview(trade: draft.trade, terms: draft.proposed, from: draft.previewDay)
    }
    func edit(_ draft: BondTermsDraft) async throws {
        guard let original = drafts[draft.trade.id], original.baseline == draft.baseline, original.trade == draft.trade else {
            throw PortfolioError("Review input changed. Collect a new preview.")
        }
        var frozen = draft
        frozen.proposed.restrictions = Array(Set(original.proposed.restrictions + draft.proposed.restrictions)).sorted()
        try await PortfolioTransaction.run(in: container) { context in
            let bond = try Self.resolve(frozen.trade.id, in: context)
            guard BondBaseline.capture(bond) == frozen.baseline else { throw PortfolioError("Holding changed. Collect a new preview.") }
            try BondTermsStore.stageDraft(frozen, for: bond)
        }
        drafts[frozen.trade.id] = frozen
    }
    func apply(ids: [UUID]) async throws {
        guard !isWorking, !ids.isEmpty, Set(ids).count == ids.count else { throw PortfolioError("Select distinct holdings for approval.") }
        let frozen = try ids.map { id -> BondTermsDraft in
            guard let draft = drafts[id] else { throw PortfolioError("A selected review item is missing.") }
            return draft
        }
        let appliedAt = now(); isWorking = true; defer { isWorking = false }
        try await PortfolioTransaction.run(in: container) { context in
            for draft in frozen {
                let bond = try Self.resolve(draft.trade.id, in: context)
                guard BondBaseline.capture(bond) == draft.baseline else { throw PortfolioError("Holding changed. Refresh its review before applying.") }
                guard draft.previewDay == MarketDay(date: appliedAt) else { throw PortfolioError("The review day changed. Review an updated preview.") }
                var terms = draft.proposed
                let result = try BondSchedule.preview(trade: draft.trade, terms: terms, from: draft.previewDay)
                guard result.assessment.supported else { throw PortfolioError(result.assessment.reasons.joined(separator: "\n")) }
                terms.approvedAt = appliedAt
                try BondTermsStore.replaceProjections(for: bond, terms: terms, preview: result, now: appliedAt,
                    acquisitionDay: draft.trade.acquisitionDay, legacyDateZone: draft.legacyDateZone, context: context)
                guard bond.termsReady else { throw PortfolioError(bond.termsIssue ?? "Needs review.") }
            }
        }
        for id in ids { drafts.removeValue(forKey: id) }
    }
    func saveNew(values: BondCodable, terms: BondTerms, legacyDateZone: String) async throws -> UUID {
        try ImportManager.validate(PositionsPayload(bonds: [values], etfs: []))
        guard let zone = TimeZone(identifier: legacyDateZone) else { throw PortfolioError("Invalid acquisition date time zone.") }
        let savedAt = now()
        return try await PortfolioTransaction.run(in: container) { context in
            let request = BondEntity.fetchRequest(); request.predicate = NSPredicate(format: "id == %@", values.id as CVarArg)
            guard try context.count(for: request) == 0 else { throw PortfolioError("Holding identifier already exists.") }
            let bond = BondEntity(context: context)
            bond.id = values.id; bond.name = values.name; bond.isin = ETFPurchase.normalizedISIN(values.isin)
            bond.issuer = values.issuer; bond.wkn = values.wkn; bond.depotBank = values.depotBank
            bond.parValue = values.parValue; bond.initialPrice = values.initialPrice
            bond.acquisitionDate = values.acquisitionDate; bond.maturityDate = values.maturityDate
            bond.couponRate = values.couponRate; bond.yieldToMaturity = 0
            var calendar = MarketDay.calendar; calendar.timeZone = zone
            let day = MarketDay(date: values.acquisitionDate, calendar: calendar)
            let trade = BondTrade(id: bond.id, isin: bond.isin, nominal: bond.parValue, cost: bond.initialPrice, acquisitionDay: day, bank: bond.depotBank)
            let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay(date: savedAt))
            if terms.approvedAt != nil && preview.assessment.supported {
                try BondTermsStore.replaceProjections(for: bond, terms: terms, preview: preview, now: savedAt,
                    acquisitionDay: day, legacyDateZone: legacyDateZone, context: context)
            } else {
                bond.termsIssue = "Needs review"
                try BondTermsStore.stageDraft(BondTermsDraft(baseline: BondBaseline.capture(bond), trade: trade,
                    legacyDateZone: legacyDateZone, proposed: terms, previewDay: MarketDay(date: savedAt)), for: bond)
            }
            try HistoricalDataRecorder.recordBondAcquisition(bond: bond, context: context)
            return bond.id
        }
    }
}

extension BondTerms {
    func preservingConfirmed(from old: BondTerms) -> BondTerms {
        var result = self
        for field in old.confirmedFields {
            switch field {
            case "currency": result.currency = old.currency
            case "structure": result.structure = old.structure
            case "frequency": result.frequency = old.frequency
            case "couponRate": result.couponRate = old.couponRate
            case "maturity": result.maturity = old.maturity
            case "accrualStart": result.accrualStart = old.accrualStart
            case "issueDay": result.issueDay = old.issueDay
            case "nextCoupon": result.nextCoupon = old.nextCoupon; result.checkpointObservedOn = old.checkpointObservedOn
            case "redemptionPercent": result.redemptionPercent = old.redemptionPercent
            case "callable": result.callable = old.callable
            case "roll": result.roll = old.roll
            default: break
            }
        }
        if old.conventions.sources["dayCount"] == .confirmed { result.conventions.dayCount = old.conventions.dayCount; result.conventions.sources["dayCount"] = .confirmed }
        if old.conventions.sources["calendar"] == .confirmed { result.conventions.calendar = old.conventions.calendar; result.conventions.sources["calendar"] = .confirmed }
        if old.conventions.sources["adjustment"] == .confirmed { result.conventions.adjustment = old.conventions.adjustment; result.conventions.sources["adjustment"] = .confirmed }
        result.confirmedFields.formUnion(old.confirmedFields)
        result.restrictions = Array(Set(result.restrictions + old.restrictions)).sorted()
        return result
    }
}
