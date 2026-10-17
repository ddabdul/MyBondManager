import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class ImportManagerTests: XCTestCase {
    func testMalformedSecondFileDoesNotLeavePartialChanges() async throws {
        let container = try TestPortfolio.make()
        _ = TestPortfolio.bond(in: container.viewContext)
        try container.viewContext.save()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data("[]".utf8).write(to: folder.appendingPathComponent("bonds.json"))
        try Data("{broken".utf8).write(to: folder.appendingPathComponent("etfs.json"))
        do {
            try await ImportManager().importAll(from: folder, into: container)
            XCTFail("Expected malformed file error")
        } catch {}
        XCTAssertFalse(container.viewContext.hasChanges)
        XCTAssertEqual(try container.viewContext.count(for: BondEntity.fetchRequest()), 1)
    }
}
