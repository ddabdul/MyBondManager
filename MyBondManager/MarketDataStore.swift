import Foundation
import CryptoKit

struct MarketDataStore {
    let directory: URL
    init(directory: URL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("MarketData", isDirectory: true)) { self.directory = directory }

    private struct Fingerprint: Codable { let payload: MarketDataPayload; let calibration: CurveCalibrationDiagnostics }
    private static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; return encoder
    }
    private static func identifier(payload: MarketDataPayload, calibration: CurveCalibrationDiagnostics) throws -> String {
        let bytes = try encoder().encode(Fingerprint(payload: payload, calibration: calibration))
        return SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }
    static func validate(_ snapshot: MarketDataSnapshot) throws {
        let normalized = try MarketDataClient.validated(snapshot.payload, pricingDay: MarketDay(date: snapshot.retrievedAt))
        guard normalized == snapshot.payload, snapshot.calibration.quantLibVersion == QuantLibBondMath.version,
              snapshot.calibration.maxDepositResidual.isFinite, snapshot.calibration.maxSwapResidual.isFinite,
              (0...1e-6).contains(snapshot.calibration.maxDepositResidual),
              (0...1e-6).contains(snapshot.calibration.maxSwapResidual),
              snapshot.id == (try identifier(payload: normalized, calibration: snapshot.calibration)) else {
            throw MarketDataError("Market snapshot content or calibration fingerprint is invalid.")
        }
        let actual = try QuantLibBondMath.forwards(quotes: normalized.quotes, fixingDays: []).calibration
        guard actual.quantLibVersion == snapshot.calibration.quantLibVersion,
              actual.lastCurveDay == snapshot.calibration.lastCurveDay,
              actual.maxDepositResidual.isFinite, actual.maxSwapResidual.isFinite,
              (0...1e-6).contains(actual.maxDepositResidual), (0...1e-6).contains(actual.maxSwapResidual) else { throw MarketDataError("Market snapshot calibration is not reproducible.") }
    }
    func save(_ payload: MarketDataPayload, retrievedAt: Date) throws -> MarketDataSnapshot {
        let payload = try MarketDataClient.validated(payload, pricingDay: MarketDay(date: retrievedAt))
        let calibration = try QuantLibBondMath.forwards(quotes: payload.quotes, fixingDays: []).calibration
        let id = try Self.identifier(payload: payload, calibration: calibration)
        let snapshot = MarketDataSnapshot(id: id, payload: payload, calibration: calibration, retrievedAt: retrievedAt)
        let url = directory.appendingPathComponent(id + ".json")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: url.path) {
            let existing = try load(id: id)
            guard existing.payload == payload, existing.calibration == calibration else {
                throw MarketDataError("Existing market snapshot conflicts with its content identity.")
            }
            return existing
        }
        let temporary = directory.appendingPathComponent("." + UUID().uuidString + ".pending")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Self.encoder().encode(snapshot).write(to: temporary, options: .atomic)
        // Same-directory hard-link publication is atomic and never replaces an existing snapshot.
        do { try FileManager.default.linkItem(at: temporary, to: url) }
        catch let failure as NSError where failure.domain == NSCocoaErrorDomain && failure.code == NSFileWriteFileExistsError {
            let existing = try load(id: id)
            guard existing.payload == payload, existing.calibration == calibration else {
                throw MarketDataError("Concurrent market snapshot publication conflicts with its identity.")
            }
            return existing
        }
        return snapshot
    }
    func load(id: String) throws -> MarketDataSnapshot {
        guard id.count == 64, id.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw MarketDataError("Market snapshot identifier is invalid.")
        }
        let data = try Data(contentsOf: directory.appendingPathComponent(id + ".json"))
        let snapshot = try JSONDecoder().decode(MarketDataSnapshot.self, from: data)
        guard snapshot.id == id else { throw MarketDataError("Market snapshot filename does not match its identity.") }
        try Self.validate(snapshot)
        return snapshot
    }
    func list() throws -> [MarketDataSnapshot] {
        guard FileManager.default.fileExists(atPath: directory.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }.map { try load(id: $0.deletingPathExtension().lastPathComponent) }
            .sorted { $0.payload.quotes.quoteDay > $1.payload.quotes.quoteDay }
    }
    static func isStale(quoteDay: MarketDay, on day: MarketDay) throws -> Bool {
        guard day >= quoteDay else { throw MarketDataError("Quote day is after the inspection day.") }
        var current = quoteDay, businessDays = 0
        while current < day {
            current = try current.addingDays(1)
            if try QuantLibBondMath.following(current) == current { businessDays += 1 }
            if businessDays > 2 { return true }
        }
        return false
    }
}
