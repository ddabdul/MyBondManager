import XCTest
import CryptoKit
@testable import MyBondManager

final class MarketDataStoreTests: XCTestCase {
    private func payload() throws -> MarketDataPayload {
        MarketDataPayload(formatVersion: 1, method: "euribor-singlecurve-v1", sourceName: "Public fixture",
            quotes: try CurveFixtures.quotes(), historicalFixings: [PublishedFixing(day: try MarketDay("2026-10-08"), rate: 0.02642)])
    }
    func testIdenticalFinancialInputsDoNotCreateDuplicateSnapshots() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MarketDataStore(directory: directory)
        let first = try store.save(payload(), retrievedAt: Date(timeIntervalSince1970: 1791504000))
        let second = try store.save(payload(), retrievedAt: Date(timeIntervalSince1970: 1791590400))
        XCTAssertEqual(first.id, second.id)
        XCTAssertEqual(try store.list().count, 1)
        XCTAssertEqual(try store.load(id: first.id), first)
    }
    func testTamperedContentAndPathTraversalAreRejected() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = MarketDataStore(directory: directory)
        let first = try store.save(payload(), retrievedAt: Date(timeIntervalSince1970: 1791504000))
        let url = directory.appendingPathComponent(first.id + ".json")
        let text = try String(contentsOf: url, encoding: .utf8)
        try text.replacingOccurrences(of: "0.02642", with: "0.02643").write(to: url, atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try store.load(id: first.id))
        XCTAssertThrowsError(try store.load(id: "../../outside"))
    }
    func testStalenessCountsTARGETBusinessDays() throws {
        XCTAssertFalse(try MarketDataStore.isStale(quoteDay: MarketDay("2026-10-09"), on: MarketDay("2026-10-13")))
        XCTAssertTrue(try MarketDataStore.isStale(quoteDay: MarketDay("2026-10-09"), on: MarketDay("2026-10-14")))
    }
    func testEquivalentCalibrationResidualsFromAnotherCPURemainValid() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let original = try MarketDataStore(directory: directory).save(payload(), retrievedAt: Date(timeIntervalSince1970: 1791504000))
        let calibration = CurveCalibrationDiagnostics(quantLibVersion: original.calibration.quantLibVersion,
            maxDepositResidual: original.calibration.maxDepositResidual + 1e-12,
            maxSwapResidual: original.calibration.maxSwapResidual + 1e-12, lastCurveDay: original.calibration.lastCurveDay)
        struct FinancialInput: Encodable { let payload: MarketDataPayload; let calibration: CurveCalibrationDiagnostics }
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        let bytes = try encoder.encode(FinancialInput(payload: original.payload, calibration: calibration))
        let id = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let transferred = MarketDataSnapshot(id: id, payload: original.payload, calibration: calibration, retrievedAt: original.retrievedAt)
        XCTAssertNoThrow(try MarketDataStore.validate(transferred))
    }
}
