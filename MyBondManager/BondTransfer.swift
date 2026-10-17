import CoreData
import CryptoKit

struct BondTermsEntry: Codable, Equatable, Sendable {
    let id: UUID
    let isin: String
    let terms: BondTerms?
    let draft: BondTerms?
    let acquisitionDay: MarketDay
    let legacyDateZone: String
    let projectionFrom: MarketDay?
    let needsReviewReasons: [String]
    var valuationDay: MarketDay? = nil
    var snapshotID: String? = nil
    var draftValuationDay: MarketDay? = nil
    var draftSnapshotID: String? = nil
    var draftPreviewDay: MarketDay? = nil
}
struct BondTermsEnvelope: Codable, Equatable, Sendable {
    let version: Int
    let bondsSHA256: String
    let bonds: [BondTermsEntry]
    var snapshots: [String: MarketDataSnapshot]? = nil
}
struct PreparedBondTransfer: Equatable, Sendable {
    let bonds: [BondCodable]
    let bondsBytes: Data?
    let native: BondTermsEnvelope?
    var unresolvedCount: Int { native?.bonds.filter { $0.terms?.approvedAt == nil }.count ?? bonds.count }
}
enum BondTransfer {
    static func digest(_ bytes: Data) -> String { SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined() }
    static func encoder() -> JSONEncoder { let value = JSONEncoder(); value.dateEncodingStrategy = .iso8601; return value }
    static func decoder() -> JSONDecoder { let value = JSONDecoder(); value.dateDecodingStrategy = .iso8601; return value }
    static func prepare(bonds: Data, sidecar: Data?) throws -> PreparedBondTransfer {
        let decoded = try decoder().decode([BondCodable].self, from: bonds)
        let native = try sidecar.map { try decoder().decode(BondTermsEnvelope.self, from: $0) }
        let result = PreparedBondTransfer(bonds: decoded, bondsBytes: bonds, native: native)
        try validate(result)
        return result
    }
    static func snapshot(from context: NSManagedObjectContext) throws -> PreparedBondTransfer {
        guard !context.hasChanges else { throw PortfolioError("Save pending portfolio changes before exporting.") }
        let positions = try context.fetch(BondEntity.fetchRequest())
        var snapshots: [String: MarketDataSnapshot] = [:]
        let entries = try positions.map { bond -> BondTermsEntry in
            let ready = BondTermsStore.isReady(bond)
            let approved = try BondTermsStore.read(bond)
            let savedDraft = try BondTermsStore.readDraft(bond)
            var draft = savedDraft?.proposed ?? (ready ? nil : approved)
            let approvedContext = ready ? try BondTermsStore.projectionContext(bond) : nil
            let draftContext = savedDraft != nil ? savedDraft?.projectionContext
                : (ready ? nil : try BondTermsStore.projectionContext(bond))
            for context in [approvedContext, draftContext].compactMap({ $0 }) {
                try context.validate()
                if let existing = snapshots[context.marketData.id], existing != context.marketData {
                    throw PortfolioError("Market snapshots conflict with the same content identity.")
                }
                snapshots[context.marketData.id] = context.marketData
            }
            draft?.approvedAt = nil
            return BondTermsEntry(id: bond.id, isin: ETFPurchase.normalizedISIN(bond.isin), terms: ready ? approved : nil,
                draft: draft, acquisitionDay: try BondTermsStore.trade(bond).acquisitionDay,
                legacyDateZone: bond.termsLegacyDateZone ?? TimeZone.current.identifier,
                projectionFrom: try bond.termsEffectiveFrom.map(MarketDay.init),
                needsReviewReasons: ready ? [] : [bond.termsIssue ?? "Needs review"],
                valuationDay: approvedContext?.valuationDay, snapshotID: approvedContext?.marketData.id,
                draftValuationDay: draftContext?.valuationDay, draftSnapshotID: draftContext?.marketData.id,
                draftPreviewDay: savedDraft?.previewDay)
        }
        return PreparedBondTransfer(bonds: try ExportManager.snapshotBonds(from: context), bondsBytes: nil,
            native: BondTermsEnvelope(version: snapshots.isEmpty ? 1 : 2, bondsSHA256: "", bonds: entries,
                snapshots: snapshots.isEmpty ? nil : snapshots))
    }
    static func encode(_ snapshot: PreparedBondTransfer) throws -> (bonds: Data, sidecar: Data) {
        guard let native = snapshot.native else { throw PortfolioError("Native bond metadata is missing from the export snapshot.") }
        let bonds = try encoder().encode(snapshot.bonds)
        let envelope = BondTermsEnvelope(version: native.version, bondsSHA256: digest(bonds), bonds: native.bonds, snapshots: native.snapshots)
        let sidecar = try encoder().encode(envelope)
        _ = try prepare(bonds: bonds, sidecar: sidecar)
        return (bonds, sidecar)
    }
    static func validate(_ transfer: PreparedBondTransfer) throws {
        try ImportManager.validate(PositionsPayload(bonds: transfer.bonds, etfs: []))
        guard transfer.bonds.allSatisfy({ !ETFPurchase.normalizedISIN($0.isin).isEmpty }) else { throw PortfolioError("A bond ISIN is missing.") }
        if let bytes = transfer.bondsBytes {
            let decoded = try decoder().decode([BondCodable].self, from: bytes)
            guard try normalized(decoded) == normalized(transfer.bonds) else { throw PortfolioError("Frozen bond data differs from its companion bytes.") }
        }
        guard let native = transfer.native else { return }
        guard native.version == 1 || native.version == 2 else { throw PortfolioError("Unsupported bond-terms.json version. Expected version 1 or 2.") }
        let references = Set(native.bonds.flatMap { [$0.snapshotID, $0.draftSnapshotID].compactMap { $0 } })
        if native.version == 1 {
            guard native.snapshots == nil, references.isEmpty,
                  native.bonds.allSatisfy({ $0.valuationDay == nil && $0.draftValuationDay == nil }) else {
                throw PortfolioError("Version 1 native terms cannot contain market context.")
            }
        } else {
            guard let snapshots = native.snapshots, !snapshots.isEmpty, Set(snapshots.keys) == references else {
                throw PortfolioError("Native market snapshots contain missing or extra entries.")
            }
            for (id, snapshot) in snapshots {
                guard id == snapshot.id else { throw PortfolioError("Native market snapshot reference conflicts with its identity.") }
                try MarketDataStore.validate(snapshot)
            }
        }
        guard let bytes = transfer.bondsBytes, native.bondsSHA256 == digest(bytes) else { throw PortfolioError("bond-terms.json does not match these exact bonds.json bytes. Export both files together.") }
        guard Set(native.bonds.map(\.id)).count == native.bonds.count,
              Set(native.bonds.map(\.id)) == Set(transfer.bonds.map(\.id)) else { throw PortfolioError("Native bond entries contain duplicate, missing or extra identifiers.") }
        let positions = Dictionary(uniqueKeysWithValues: transfer.bonds.map { ($0.id, $0) })
        for entry in native.bonds {
            let bond = positions[entry.id]!
            guard entry.isin == ETFPurchase.normalizedISIN(bond.isin), let zone = TimeZone(identifier: entry.legacyDateZone) else {
                throw PortfolioError("Native bond identity or legacy date time zone is invalid.")
            }
            var calendar = MarketDay.calendar; calendar.timeZone = zone
            guard MarketDay(date: bond.acquisitionDate, calendar: calendar) == entry.acquisitionDay else { throw PortfolioError("Native acquisition day conflicts with the position.") }
            for terms in [entry.terms, entry.draft].compactMap({ $0 }) { try validateTerms(terms, isin: entry.isin) }
            let context = try projectionContext(for: entry, in: native)
            let draftContext = try projectionContext(for: entry, in: native, draft: true)
            try validateContext(context, terms: entry.terms)
            try validateContext(draftContext, terms: entry.draft)
            if let draft = entry.draft, draft.approvedAt != nil { throw PortfolioError("A native draft must not claim approval.") }
            guard let terms = entry.terms, let approved = terms.approvedAt else {
                guard bond.cashFlows.isEmpty else { throw PortfolioError("A Needs review native entry must not claim approved cash flows.") }
                continue
            }
            guard entry.needsReviewReasons.isEmpty, let from = entry.projectionFrom,
                  from >= MarketDay(date: approved), (terms.couponRate ?? 0) == bond.couponRate,
                  terms.maturity == MarketDay(date: bond.maturityDate) else { throw PortfolioError("Approved native terms conflict with the position or projection boundary.") }
            let trade = BondTrade(id: bond.id, isin: entry.isin, nominal: bond.parValue, cost: bond.initialPrice,
                acquisitionDay: entry.acquisitionDay, bank: bond.depotBank)
            if terms.structure == .floating || terms.structure == .fixedToFloating {
                guard context != nil else { throw PortfolioError("Approved floating terms require a frozen market context.") }
            }
            let preview = try BondSchedule.preview(trade: trade, terms: terms, from: from, context: context)
            guard preview.assessment.supported else { throw PortfolioError("Claimed approved native terms are unsupported: " + preview.assessment.reasons.joined(separator: "; ")) }
            let yield = preview.estimatedYTM ?? 0
            guard abs(bond.yieldToMaturity - yield) <= 1e-10 * max(1, abs(yield)) else { throw PortfolioError("Approved estimated yield conflicts with native terms.") }
            let actual = bond.cashFlows.filter { MarketDay(date: $0.date) >= from }
            let expected = preview.flows.map { CashFlowCodable(date: $0.paymentDay.instant, amount: $0.amount, nature: $0.nature.rawValue) }
            let matching = native.version == 2 ? matchingFlows(actual, expected) : try normalizedFlows(actual) == normalizedFlows(expected)
            guard matching else { throw PortfolioError("Approved cash flows conflict with the native payment schedule.") }
        }
    }
    static func projectionContext(for entry: BondTermsEntry, in envelope: BondTermsEnvelope,
                                  draft: Bool = false) throws -> ProjectionContext? {
        let day = draft ? entry.draftValuationDay : entry.valuationDay
        let id = draft ? entry.draftSnapshotID : entry.snapshotID
        guard day != nil || id != nil else { return nil }
        guard envelope.version == 2, let day, let id, let snapshot = envelope.snapshots?[id] else {
            throw PortfolioError("Native market context is incomplete or missing its snapshot.")
        }
        let context = ProjectionContext(valuationDay: day, marketData: snapshot)
        try context.validate()
        return context
    }
    private static func validateContext(_ context: ProjectionContext?, terms: BondTerms?) throws {
        guard let context else { return }
        guard let terms, terms.structure == .floating || terms.structure == .fixedToFloating,
              terms.floatingTerms?.indexTenorMonths == context.marketData.payload.quotes.indexTenorMonths else {
            throw PortfolioError("Native market context conflicts with the selected floating terms or tenor.")
        }
    }
    private static func matchingFlows(_ actual: [CashFlowCodable], _ expected: [CashFlowCodable]) -> Bool {
        let ordered: (CashFlowCodable, CashFlowCodable) -> Bool = {
            if $0.date != $1.date { return $0.date < $1.date }
            if $0.nature != $1.nature { return $0.nature < $1.nature }
            return $0.amount < $1.amount
        }
        guard actual.count == expected.count else { return false }
        return zip(actual.sorted(by: ordered), expected.sorted(by: ordered)).allSatisfy { left, right in
            left.date == right.date && left.nature == right.nature
                && abs(left.amount - right.amount) <= max(1e-8, abs(right.amount) * 1e-12)
        }
    }
    private static func validateTerms(_ terms: BondTerms, isin: String) throws {
        guard (terms.isin.isEmpty && terms.approvedAt == nil) || ETFPurchase.normalizedISIN(terms.isin) == isin else { throw PortfolioError("Terms refer to another ISIN.") }
        if let rate = terms.couponRate, !rate.isFinite || rate < 0 { throw PortfolioError("Native coupon rate is invalid.") }
        if let amount = terms.redemptionPercent, !amount.isFinite || amount <= 0 { throw PortfolioError("Native redemption percentage is invalid.") }
    }
    private static func normalized(_ bonds: [BondCodable]) throws -> [String] {
        try bonds.map { try PositionsTransferValidation.normalized($0) }.sorted()
    }
    static func normalizedFlows(_ values: [CashFlowCodable]) throws -> [String] {
        let encoder = encoder(); encoder.outputFormatting = .sortedKeys
        return try values.map { try encoder.encode($0).base64EncodedString() }.sorted()
    }
}
