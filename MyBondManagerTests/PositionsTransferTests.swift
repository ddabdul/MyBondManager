import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class PositionsTransferTests: XCTestCase {
    func testExportFolderShowsLocalDateAndPreservesRepeatedExports() async throws {
        let container = try TestPortfolio.make()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = try await ExportManager().exportAll(to: root, from: container.viewContext)
        let second = try await ExportManager().exportAll(to: root, from: container.viewContext)
        for folder in [first, second] {
            XCTAssertNotNil(folder.lastPathComponent.range(
                of: #"^positions-\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}(-\d+)?$"#,
                options: .regularExpression))
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("bonds.json").path))
            XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appendingPathComponent("etfs.json").path))
        }
        XCTAssertNotEqual(first, second)
    }

    func testExportDoesNotOverwritePreviouslyPublishedFiles() async throws {
        let container = try TestPortfolio.make()
        _ = TestPortfolio.bond(in: container.viewContext)
        try container.viewContext.save()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let old = Data("previous export".utf8)
        try old.write(to: folder.appendingPathComponent("bonds.json"))
        try FileManager.default.createDirectory(at: folder.appendingPathComponent("etfs.json"),
            withIntermediateDirectories: true)
        do { _ = try await ExportManager().exportAll(to: folder, from: container.viewContext) } catch {}
        XCTAssertEqual(try Data(contentsOf: folder.appendingPathComponent("bonds.json")), old)
    }
    func testFrozenPayloadSurvivesFileChangesAndKeepsExistingHistory() async throws {
        let source = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: source.viewContext, cost: 900)
        try CashFlowGenerator(context: source.viewContext).regenerateCashFlows(for: bond)
        try source.viewContext.save()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let published = try await ExportManager().exportAll(to: folder, from: source.viewContext)
        let payload = try await ImportManager().prepare(from: published)
        try Data("[]".utf8).write(to: published.appendingPathComponent("bonds.json"))
        try Data("[]".utf8).write(to: published.appendingPathComponent("etfs.json"))
        let target = try TestPortfolio.make()
        let old = TestPortfolio.bond(in: target.viewContext)
        try HistoricalDataRecorder.recordBondAcquisition(bond: old, context: target.viewContext)
        try target.viewContext.save()
        try await ImportManager().apply(payload, into: target)
        let reader = target.newBackgroundContext()
        let counts = try await reader.perform {
            (try reader.count(for: BondEntity.fetchRequest()),
             try reader.count(for: HistoricalValuation.fetchRequest()))
        }
        XCTAssertEqual(counts.0, 1); XCTAssertEqual(counts.1, 1)
    }
    func testValidationDetectsFinancialDifferenceDespiteSameName() throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext, cost: 900)
        try CashFlowGenerator(context: container.viewContext).regenerateCashFlows(for: bond)
        let original = try ExportManager.snapshot(from: container.viewContext)
        bond.initialPrice = 950
        let issues = try PositionsTransferValidation.issues(bonds: original.bonds,
            etfs: original.etfs, context: container.viewContext)
        XCTAssertFalse(issues.isEmpty)
    }
    func testFailedSecondWritePublishesNothing() async throws {
        let container = try TestPortfolio.make()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let exporter = ExportManager(write: { data, url in
            if url.lastPathComponent == "etfs.json" { throw CocoaError(.fileWriteNoPermission) }
            try data.write(to: url)
        })
        do { _ = try await exporter.exportAll(to: folder, from: container.viewContext); XCTFail("Expected write failure") }
        catch {}
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
    }
    func testValidationRejectsDuplicateIDsWithoutTrapping() throws {
        let container = try TestPortfolio.make()
        _ = TestPortfolio.bond(in: container.viewContext)
        let payload = try ExportManager.snapshot(from: container.viewContext)
        XCTAssertThrowsError(try PositionsTransferValidation.issues(
            bonds: payload.bonds + payload.bonds, etfs: [], context: container.viewContext))
    }

    func testETFTransferRoundTripComparesAllNestedValues() async throws {
        let source = try TestPortfolio.make()
        let holding = TestPortfolio.holding(in: source.viewContext)
        let quote = ETFPrice(context: source.viewContext)
        quote.etfPriceHistory = holding.holdingtoetf; quote.price = 113.5
        quote.datePrice = TestPortfolio.date("2026-01-01T12:00:00Z")
        try source.viewContext.save()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = try await ExportManager().exportAll(to: root, from: source.viewContext)
        let payload = try await ImportManager().prepare(from: folder)
        let target = try TestPortfolio.make()
        try await ImportManager().apply(payload, into: target)
        let reader = target.newBackgroundContext()
        let issues = try await reader.perform {
            try PositionsTransferValidation.issues(bonds: payload.bonds, etfs: payload.etfs, context: reader)
        }
        XCTAssertTrue(issues.isEmpty)
        let targetSnapshot = try await reader.perform { try ExportManager.snapshot(from: reader) }
        XCTAssertEqual(targetSnapshot.etfs.first?.holdings.first?.numberOfShares, 10)
        XCTAssertEqual(targetSnapshot.etfs.first?.priceHistory.first?.price, 113.5)
    }

}
