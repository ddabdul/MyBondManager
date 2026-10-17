import CoreData
import Combine

struct BondTermsApplyReport {
    var appliedISINs: Set<String> = []
    var appliedHoldingIDs: Set<UUID> = []
    var failures: [String: String] = [:]
    var summary: String { "Applied \(appliedISINs.count) ISINs across \(appliedHoldingIDs.count) purchases. \(failures.count) instruments need attention and remain open." }
}

@MainActor
final class BondTermsReview: ObservableObject, Identifiable {
    @Published private(set) var drafts: [UUID: BondTermsDraft] = [:]
    @Published private(set) var errors: [String: String] = [:]
    @Published private(set) var isWorking = false
    @Published private(set) var lastApplyReport: BondTermsApplyReport?
    let container: NSPersistentContainer
    private let fetch: (String) async throws -> BondDetails
    private let now: () -> Date
    private var collectionErrors: [String: String] = [:]
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
        let reader = container.newBackgroundContext()
        let values = try await reader.perform {
            var drafts: [UUID: BondTermsDraft] = [:], errors: [String: String] = [:]
            for bond in try reader.fetch(BondEntity.fetchRequest()) {
                do { drafts[bond.id] = try BondTermsStore.readDraft(bond) }
                catch { errors[bond.id.uuidString] = error.localizedDescription }
            }
            return (drafts, errors)
        }
        drafts = values.0; errors = values.1
    }
    nonisolated private static func matchingPurchases(ids: [UUID], in context: NSManagedObjectContext) throws -> [BondEntity] {
        let isins = try Set(ids.map { ETFPurchase.normalizedISIN(try resolve($0, in: context).isin) })
        let bonds = try context.fetch(BondEntity.fetchRequest()).filter { isins.contains(ETFPurchase.normalizedISIN($0.isin)) }
        guard Set(bonds.map(\.id)).count == bonds.count else { throw PortfolioError("Stored bonds contain duplicate identifiers.") }
        return bonds.sorted { $0.id.uuidString < $1.id.uuidString }
    }
    func collect(ids: [UUID]) async {
        guard !isWorking else { errors["review"] = "A review operation is already running."; return }
        isWorking = true; errors = [:]; defer { isWorking = false }
        do {
            let reviewDay = MarketDay(date: now())
            let snapshots = try await container.viewContext.perform {
                try Self.matchingPurchases(ids: ids, in: self.container.viewContext).map { bond -> BondTermsDraft in
                    let pending = try BondTermsStore.readDraft(bond)
                    let proposed = try pending?.proposed ?? BondTermsStore.read(bond) ?? BondTerms()
                    let market = try pending != nil ? pending?.projectionContext : BondTermsStore.projectionContext(bond)
                    return BondTermsDraft(baseline: BondBaseline.capture(bond), trade: try BondTermsStore.trade(bond),
                        legacyDateZone: bond.termsLegacyDateZone ?? TimeZone.current.identifier, proposed: proposed, previewDay: reviewDay, projectionContext: market)
                }
            }
            for (isin, positions) in Dictionary(grouping: snapshots, by: { $0.trade.isin }).sorted(by: { $0.key < $1.key }) {
                do {
                    collectionErrors.removeValue(forKey: isin)
                    let details = try await fetch(isin)
                    guard let incoming = details.terms, ETFPurchase.normalizedISIN(incoming.isin) == isin else {
                        throw PortfolioError("Provider terms are missing or belong to another ISIN.")
                    }
                    var proposed = incoming
                    for position in positions { proposed = proposed.preservingConfirmed(from: position.proposed) }
                    guard positions.allSatisfy({ BondTermsStore.sameInstrumentTerms(proposed, proposed.preservingConfirmed(from: $0.proposed)) }) else {
                        throw PortfolioError("Confirmed values disagree for this ISIN. Save one shared instrument draft before refreshing.")
                    }
                    for original in positions {
                        do {
                            let draft = BondTermsDraft(baseline: original.baseline, trade: original.trade,
                                legacyDateZone: original.legacyDateZone, proposed: proposed, previewDay: MarketDay(date: now()), projectionContext: original.projectionContext)
                            let saved = try await PortfolioTransaction.run(in: container) { context in
                                let bond = try Self.resolve(draft.trade.id, in: context)
                                guard BondBaseline.capture(bond) == draft.baseline else { throw PortfolioError("Holding changed while collecting. Refresh its review.") }
                                return try BondTermsStore.stageDraft(draft, for: bond)
                            }
                            drafts[draft.trade.id] = saved
                        } catch { errors[original.trade.id.uuidString] = error.localizedDescription }
                    }
                } catch {
                    errors[isin] = error.localizedDescription
                    collectionErrors[isin] = error.localizedDescription
                }
            }
        } catch { errors["review"] = error.localizedDescription }
    }
    var today: MarketDay { MarketDay(date: now()) }
    func beginManualReview(ids: [UUID]) async throws {
        let day = today
        let values = try await PortfolioTransaction.run(in: container) { context in
            let bonds = try Self.matchingPurchases(ids: ids, in: context)
            var result: [BondTermsDraft] = []
            for (_, positions) in Dictionary(grouping: bonds, by: { ETFPurchase.normalizedISIN($0.isin) }) {
                var saved: [UUID: BondTermsDraft] = [:]
                for bond in positions { saved[bond.id] = try BondTermsStore.readDraft(bond) }
                let requested = ids.compactMap { id in positions.first { $0.id == id } }
                let source = requested.first { saved[$0.id] != nil } ?? positions.first { saved[$0.id] != nil }
                    ?? requested.first ?? positions[0]
                let zone = source.termsLegacyDateZone ?? TimeZone.current.identifier
                var calendar = MarketDay.calendar; calendar.timeZone = TimeZone(identifier: zone)!
                var proposed = try BondTermsStore.readDraft(source)?.proposed ?? BondTermsStore.read(source) ?? BondTerms()
                proposed.isin = ETFPurchase.normalizedISIN(source.isin)
                if proposed.couponRate == nil { proposed.couponRate = source.couponRate }
                if proposed.maturity == nil { proposed.maturity = MarketDay(date: source.maturityDate, calendar: calendar) }
                proposed.approvedAt = nil
                for bond in positions {
                    if let existing = saved[bond.id] { result.append(existing); continue }
                    let draft = try BondTermsDraft(baseline: BondBaseline.capture(bond), trade: BondTermsStore.trade(bond),
                        legacyDateZone: bond.termsLegacyDateZone ?? TimeZone.current.identifier, proposed: proposed, previewDay: day, projectionContext: try BondTermsStore.projectionContext(source))
                    result.append(try BondTermsStore.stageDraft(draft, for: bond))
                }
            }
            return result
        }
        for draft in values { drafts[draft.trade.id] = draft }
    }
    func preview(_ draft: BondTermsDraft) throws -> BondSchedulePreview {
        try BondSchedule.preview(trade: draft.trade, terms: draft.proposed, from: draft.previewDay, context: draft.projectionContext)
    }
    func edit(_ draft: BondTermsDraft) async throws {
        guard let original = drafts[draft.trade.id], original.baseline == draft.baseline, original.trade == draft.trade else {
            throw PortfolioError("Review input changed. Collect a new preview.")
        }
        if let rate = draft.proposed.couponRate, !rate.isFinite || rate < 0 { throw PortfolioError("Enter a valid nonnegative coupon rate.") }
        if let redemption = draft.proposed.redemptionPercent, !redemption.isFinite || redemption <= 0 { throw PortfolioError("Enter a valid positive redemption percentage.") }
        var proposed = draft.proposed
        let frozen = drafts
        for prior in frozen.values where ETFPurchase.normalizedISIN(prior.trade.isin) == ETFPurchase.normalizedISIN(draft.trade.isin) {
            proposed = proposed.preservingSafeguards(from: prior.proposed)
        }
        let shared = proposed
        let values = try await PortfolioTransaction.run(in: container) { context in
            try Self.matchingPurchases(ids: [draft.trade.id], in: context).map { bond -> BondTermsDraft in
                if let prior = frozen[bond.id], BondBaseline.capture(bond) != prior.baseline {
                    throw PortfolioError("Holding changed. Collect a new preview.")
                }
                let updated = try BondTermsDraft(baseline: BondBaseline.capture(bond), trade: BondTermsStore.trade(bond),
                    legacyDateZone: bond.termsLegacyDateZone ?? TimeZone.current.identifier, proposed: shared, previewDay: draft.previewDay, projectionContext: draft.projectionContext)
                return try BondTermsStore.stageDraft(updated, for: bond)
            }
        }
        for value in values { drafts[value.trade.id] = value }
    }
    private func selectionGroups(ids: [UUID], frozen: [UUID: BondTermsDraft]) async throws -> [String: [UUID]] {
        let storedISINs = try await PortfolioTransaction.run(in: container) { context in
            let bonds = try context.fetch(BondEntity.fetchRequest())
            guard Set(bonds.map(\.id)).count == bonds.count else { throw PortfolioError("Stored bonds contain duplicate identifiers.") }
            return Dictionary(uniqueKeysWithValues: bonds.map { ($0.id, ETFPurchase.normalizedISIN($0.isin)) })
        }
        return Dictionary(grouping: ids, by: { ETFPurchase.normalizedISIN(frozen[$0]?.trade.isin ?? storedISINs[$0] ?? $0.uuidString) })
    }
    @discardableResult
    func apply(ids: [UUID]) async throws -> BondTermsApplyReport {
        guard !isWorking, !ids.isEmpty, Set(ids).count == ids.count else { throw PortfolioError("Select distinct instruments for approval.") }
        lastApplyReport = nil
        let frozen = drafts
        let appliedAt = now(); isWorking = true; defer { isWorking = false }
        let groups = try await selectionGroups(ids: ids, frozen: frozen)
        var report = BondTermsApplyReport()
        for (isin, selectedIDs) in groups.sorted(by: { $0.key < $1.key }) {
            do {
                let siblingDraft = frozen.values.filter { ETFPurchase.normalizedISIN($0.trade.isin) == isin }
                    .sorted { $0.trade.id.uuidString < $1.trade.id.uuidString }.first
                guard let source = selectedIDs.compactMap({ frozen[$0] }).first ?? siblingDraft else {
                    let detail = collectionErrors[isin].map { "Last collection failed: " + $0 }
                        ?? "Choose Collect missing terms or Enter terms manually before applying."
                    throw PortfolioError("No saved draft for this ISIN. " + detail)
                }
                guard source.previewDay == MarketDay(date: appliedAt) else { throw PortfolioError("The review day changed. Save an updated preview.") }
                let updated = try await PortfolioTransaction.run(in: container) { context in
                    for id in selectedIDs { _ = try Self.resolve(id, in: context) }
                    let positions = try Self.matchingPurchases(ids: selectedIDs, in: context)
                    for bond in positions {
                        if let saved = try BondTermsStore.readDraft(bond), (!BondTermsStore.sameInstrumentTerms(saved.proposed, source.proposed) || saved.projectionContext != source.projectionContext) {
                            throw PortfolioError("Saved drafts disagree for this ISIN. Save one instrument draft before applying.")
                        }
                    }
                    var terms = source.proposed; terms.approvedAt = appliedAt; terms.isin = isin
                    for bond in positions {
                        if let prior = frozen[bond.id], BondBaseline.capture(bond) != prior.baseline {
                            throw PortfolioError("Holding changed. Refresh its review before applying.")
                        }
                        let trade = try BondTermsStore.trade(bond)
                        let result = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay(date: appliedAt), context: source.projectionContext)
                        guard result.assessment.supported else { throw PortfolioError(result.assessment.reasons.joined(separator: "\n")) }
                        try BondTermsStore.replaceProjections(for: bond, terms: terms, preview: result, now: appliedAt,
                            acquisitionDay: trade.acquisitionDay, legacyDateZone: bond.termsLegacyDateZone ?? TimeZone.current.identifier, context: context, projectionContext: source.projectionContext)
                        guard bond.termsReady else { throw PortfolioError(bond.termsIssue ?? "Needs review.") }
                    }
                    return Set(positions.map(\.id))
                }
                report.appliedISINs.insert(isin); report.appliedHoldingIDs.formUnion(updated)
                for id in updated { drafts.removeValue(forKey: id); errors.removeValue(forKey: id.uuidString) }
                errors.removeValue(forKey: isin)
            } catch { report.failures[isin] = error.localizedDescription }
        }
        errors.merge(report.failures) { _, new in new }
        lastApplyReport = report
        guard !report.appliedISINs.isEmpty else { throw PortfolioError(report.failures.values.sorted().joined(separator: "\n")) }
        return report
    }
    @discardableResult
    func refreshForecasts(ids: [UUID], context selectedContext: ProjectionContext) async throws -> BondTermsApplyReport {
        guard !isWorking, !ids.isEmpty, Set(ids).count == ids.count else { throw PortfolioError("Select distinct instruments to rebuild.") }
        try selectedContext.validate()
        let at = now()
        let groups = try await selectionGroups(ids: ids, frozen: drafts)
        isWorking = true; defer { isWorking = false }
        var report = BondTermsApplyReport()
        for (isin, selectedIDs) in groups.sorted(by: { $0.key < $1.key }) {
            do {
                let updated = try await PortfolioTransaction.run(in: container) { context -> Set<UUID> in
                    let positions = try Self.matchingPurchases(ids: selectedIDs, in: context)
                    for bond in positions {
                        guard let terms = try BondTermsStore.read(bond), terms.approvedAt != nil,
                              [.floating, .fixedToFloating].contains(terms.structure),
                              try BondTermsStore.validatedPreview(bond, from: MarketDay(date: at)) != nil else {
                            throw PortfolioError("Approve complete floating terms before rebuilding their forecast.")
                        }
                        let pending = try BondTermsStore.readDraft(bond)
                        let trade = try BondTermsStore.trade(bond)
                        let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay(date: at), context: selectedContext)
                        guard preview.assessment.supported else { throw PortfolioError(preview.assessment.reasons.joined(separator: " ")) }
                        try BondTermsStore.replaceProjections(for: bond, terms: terms, preview: preview, now: at,
                            acquisitionDay: trade.acquisitionDay, legacyDateZone: bond.termsLegacyDateZone ?? TimeZone.current.identifier,
                            context: context, projectionContext: selectedContext)
                        guard bond.termsReady else { throw PortfolioError(bond.termsIssue ?? "Forecast requires review.") }
                        if let pending {
                            try BondTermsStore.stageDraft(BondTermsDraft(baseline: BondBaseline.capture(bond), trade: trade,
                                legacyDateZone: pending.legacyDateZone, proposed: pending.proposed, previewDay: pending.previewDay,
                                projectionContext: pending.projectionContext), for: bond)
                        }
                    }
                    return Set(positions.map(\.id))
                }
                report.appliedISINs.insert(isin); report.appliedHoldingIDs.formUnion(updated)
            } catch { report.failures[isin] = error.localizedDescription }
        }
        errors = report.failures; lastApplyReport = report
        try await load()
        errors.merge(report.failures) { _, new in new }
        return report
    }
    @discardableResult
    func reuseApproved(ids: [UUID]) async throws -> BondTermsApplyReport {
        guard !isWorking, !ids.isEmpty else { throw PortfolioError("Select instruments whose existing approvals should be reused.") }
        lastApplyReport = nil; isWorking = true; defer { isWorking = false }
        let at = now()
        let groups = try await selectionGroups(ids: ids, frozen: drafts)
        var report = BondTermsApplyReport()
        for (isin, selectedIDs) in groups.sorted(by: { $0.key < $1.key }) {
            do {
                let updated = try await PortfolioTransaction.run(in: container) { context in
                    for id in selectedIDs { _ = try Self.resolve(id, in: context) }
                    guard try BondTermsStore.reuseApprovedTerms(for: isin, in: context, now: at) else {
                        throw PortfolioError("No reusable approval, or a saved draft adds safeguards missing from the approval. Collect, review and apply this ISIN's terms before reusing an approval.")
                    }
                    let bonds = try context.fetch(BondEntity.fetchRequest()).filter { ETFPurchase.normalizedISIN($0.isin) == isin }
                    guard bonds.allSatisfy(BondTermsStore.isReady) else {
                        throw PortfolioError("No reusable approval, or a purchase requires history/trade review. Collect or correct this ISIN's terms.")
                    }
                    var retained: [UUID: BondTermsDraft] = [:]
                    for bond in bonds { retained[bond.id] = try BondTermsStore.readDraft(bond) }
                    return (ids: Set(bonds.map(\.id)), drafts: retained)
                }
                report.appliedISINs.insert(isin); report.appliedHoldingIDs.formUnion(updated.ids)
                errors.removeValue(forKey: isin)
                for id in updated.ids { drafts.removeValue(forKey: id); errors.removeValue(forKey: id.uuidString) }
                drafts.merge(updated.drafts) { _, saved in saved }
            } catch { report.failures[isin] = error.localizedDescription }
        }
        errors.merge(report.failures) { _, new in new }; lastApplyReport = report
        guard !report.appliedISINs.isEmpty else { throw PortfolioError(report.failures.values.sorted().joined(separator: "\n")) }
        return report
    }
    func saveNew(values: BondCodable, terms: BondTerms, legacyDateZone: String, projectionContext: ProjectionContext? = nil) async throws -> UUID {
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
            bond.termsAcquisitionDay = day.rawValue; bond.termsLegacyDateZone = legacyDateZone
            let trade = BondTrade(id: bond.id, isin: bond.isin, nominal: bond.parValue, cost: bond.initialPrice, acquisitionDay: day, bank: bond.depotBank)
            let preview = try BondSchedule.preview(trade: trade, terms: terms, from: MarketDay(date: savedAt), context: projectionContext)
            if terms.approvedAt != nil && preview.assessment.supported {
                try BondTermsStore.replaceProjections(for: bond, terms: terms, preview: preview, now: savedAt,
                    acquisitionDay: day, legacyDateZone: legacyDateZone, context: context, projectionContext: projectionContext)
            } else {
                bond.termsIssue = "Needs review"
                try BondTermsStore.stageDraft(BondTermsDraft(baseline: BondBaseline.capture(bond), trade: trade,
                    legacyDateZone: legacyDateZone, proposed: terms, previewDay: MarketDay(date: savedAt), projectionContext: projectionContext), for: bond)
            }
            try BondTermsStore.reuseApprovedTerms(for: ETFPurchase.normalizedISIN(bond.isin), targetIDs: [bond.id], in: context, now: savedAt)
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
            case "firstCoupon": result.firstCoupon = old.firstCoupon
            case "interestDeferral": result.interestDeferral = old.interestDeferral
            case "floatingStart": result.floatingStart = old.floatingStart
            case "nextCoupon": result.nextCoupon = old.nextCoupon; result.checkpointObservedOn = old.checkpointObservedOn
            case "checkpointObservedOn": result.checkpointObservedOn = old.checkpointObservedOn
            case "redemptionPercent": result.redemptionPercent = old.redemptionPercent
            case "callable": result.callable = old.callable
            case "roll": result.roll = old.roll
            default: break
            }
        }
        if old.conventions.sources["dayCount"] == .confirmed { result.conventions.dayCount = old.conventions.dayCount; result.conventions.sources["dayCount"] = .confirmed }
        if old.conventions.sources["calendar"] == .confirmed { result.conventions.calendar = old.conventions.calendar; result.conventions.sources["calendar"] = .confirmed }
        if old.conventions.sources["adjustment"] == .confirmed { result.conventions.adjustment = old.conventions.adjustment; result.conventions.sources["adjustment"] = .confirmed }
        if let oldFloating = old.floatingTerms {
            var current = result.floatingTerms ?? FloatingBondTerms()
            func preserve<T>(_ key: String, _ path: WritableKeyPath<FloatingBondTerms, T?>) {
                if oldFloating.confirmedFields.contains(key) { current[keyPath: path] = oldFloating[keyPath: path] }
            }
            preserve("indexTenorMonths", \.indexTenorMonths); preserve("spreadBps", \.spreadBps)
            preserve("gearing", \.gearing); preserve("resetLagTARGETDays", \.resetLagTARGETDays)
            preserve("resetTiming", \.resetTiming); preserve("resetAnchor", \.resetAnchor)
            preserve("dayCount", \.dayCount); preserve("frequency", \.frequency)
            preserve("firstFloatingCoupon", \.firstFloatingCoupon); preserve("accrualAdjustment", \.accrualAdjustment)
            preserve("paymentAdjustment", \.paymentAdjustment); preserve("roll", \.roll); preserve("payoff", \.payoff)
            current.confirmedFields.formUnion(oldFloating.confirmedFields)
            result.floatingTerms = current
        }
        result.confirmedFields.formUnion(old.confirmedFields)
        return result.preservingSafeguards(from: old)
    }
}
