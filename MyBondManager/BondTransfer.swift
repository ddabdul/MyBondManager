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
}
struct BondTermsEnvelope: Codable, Equatable, Sendable {
    let version: Int
    let bondsSHA256: String
    let bonds: [BondTermsEntry]
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
        let entries = try positions.map { bond -> BondTermsEntry in
            let ready = BondTermsStore.isReady(bond)
            let approved = try BondTermsStore.read(bond)
            var draft = try BondTermsStore.readDraft(bond)?.proposed ?? (ready ? nil : approved)
            draft?.approvedAt = nil
            return BondTermsEntry(id: bond.id, isin: ETFPurchase.normalizedISIN(bond.isin), terms: ready ? approved : nil,
                draft: draft, acquisitionDay: try BondTermsStore.trade(bond).acquisitionDay,
                legacyDateZone: bond.termsLegacyDateZone ?? TimeZone.current.identifier,
                projectionFrom: try bond.termsEffectiveFrom.map(MarketDay.init),
                needsReviewReasons: ready ? [] : [bond.termsIssue ?? "Needs review"])
        }
        return PreparedBondTransfer(bonds: try ExportManager.snapshotBonds(from: context), bondsBytes: nil,
            native: BondTermsEnvelope(version: 1, bondsSHA256: "", bonds: entries))
    }
    static func encode(_ snapshot: PreparedBondTransfer) throws -> (bonds: Data, sidecar: Data) {
        guard let native = snapshot.native else { throw PortfolioError("Native bond metadata is missing from the export snapshot.") }
        let bonds = try encoder().encode(snapshot.bonds)
        let envelope = BondTermsEnvelope(version: native.version, bondsSHA256: digest(bonds), bonds: native.bonds)
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
        guard native.version == 1 else { throw PortfolioError("Unsupported bond-terms.json version. Expected version 1.") }
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
            guard let terms = entry.terms, let approved = terms.approvedAt else {
                guard bond.cashFlows.isEmpty else { throw PortfolioError("A Needs review native entry must not claim approved cash flows.") }
                continue
            }
            guard entry.needsReviewReasons.isEmpty, let from = entry.projectionFrom,
                  from >= MarketDay(date: approved), terms.couponRate == bond.couponRate,
                  terms.maturity == MarketDay(date: bond.maturityDate) else { throw PortfolioError("Approved native terms conflict with the position or projection boundary.") }
            let trade = BondTrade(id: bond.id, isin: entry.isin, nominal: bond.parValue, cost: bond.initialPrice,
                acquisitionDay: entry.acquisitionDay, bank: bond.depotBank)
            let preview = try BondSchedule.preview(trade: trade, terms: terms, from: from)
            guard preview.assessment.supported else { throw PortfolioError("Claimed approved native terms are unsupported: " + preview.assessment.reasons.joined(separator: "; ")) }
            let yield = preview.estimatedYTM ?? 0
            guard abs(bond.yieldToMaturity - yield) <= 1e-10 * max(1, abs(yield)) else { throw PortfolioError("Approved estimated yield conflicts with native terms.") }
            let actual = bond.cashFlows.filter { MarketDay(date: $0.date) >= from }
            let expected = preview.flows.map { CashFlowCodable(date: $0.paymentDay.instant, amount: $0.amount, nature: $0.nature.rawValue) }
            guard try normalizedFlows(actual) == normalizedFlows(expected) else { throw PortfolioError("Approved cash flows conflict with the native payment schedule.") }
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
