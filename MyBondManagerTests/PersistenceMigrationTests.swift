import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class PersistenceMigrationTests: XCTestCase {
    func testOriginalHistorySurvivesLightweightMigration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let models = try XCTUnwrap(Bundle(for: BondEntity.self).url(forResource: "MyBondManager", withExtension: "momd"))
        let originalModel = try XCTUnwrap(NSManagedObjectModel(contentsOf: models.appendingPathComponent("MyBondManager.mom")))
        let url = root.appendingPathComponent("migration.sqlite")
        let old = NSPersistentContainer(name: "MyBondManager", managedObjectModel: originalModel)
        let description = NSPersistentStoreDescription(url: url)
        description.shouldAddStoreAsynchronously = false
        old.persistentStoreDescriptions = [description]
        var error: Error?
        old.loadPersistentStores { _, value in error = value }
        if let error { throw error }
        let entity = try XCTUnwrap(originalModel.entitiesByName["HistoricalValuation"])
        let record = NSManagedObject(entity: entity, insertInto: old.viewContext)
        let id = UUID()
        record.setValue(id, forKey: "id"); record.setValue(Date(), forKey: "date")
        record.setValue("Bond", forKey: "assetType"); record.setValue("Bank", forKey: "depotBank")
        record.setValue(NSDecimalNumber(value: 1000), forKey: "investedCapital")
        record.setValue(NSDecimalNumber(value: 100), forKey: "capitalGains")
        try old.viewContext.save()
        old.viewContext.reset()
        for store in old.persistentStoreCoordinator.persistentStores {
            try old.persistentStoreCoordinator.remove(store)
        }
        let migrated = NSPersistentContainer(name: "MyBondManager", managedObjectModel: TestPortfolio.model)
        let target = NSPersistentStoreDescription(url: url)
        target.shouldAddStoreAsynchronously = false
        target.shouldMigrateStoreAutomatically = true; target.shouldInferMappingModelAutomatically = true
        migrated.persistentStoreDescriptions = [target]
        error = nil
        migrated.loadPersistentStores { _, value in error = value }
        if let error { throw error }
        let restored = try XCTUnwrap(migrated.viewContext.fetch(HistoricalValuation.fetchRequest()).first)
        XCTAssertEqual(restored.id, id)
        XCTAssertEqual(restored.investedCapital.doubleValue, 1000)
        XCTAssertEqual(restored.capitalGains.doubleValue, 100)
        XCTAssertNil(restored.eventKey)
        migrated.viewContext.reset()
        for store in migrated.persistentStoreCoordinator.persistentStores {
            try migrated.persistentStoreCoordinator.remove(store)
        }
    }
}
