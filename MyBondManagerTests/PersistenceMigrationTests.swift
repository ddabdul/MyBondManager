import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class PersistenceMigrationTests: XCTestCase {
    func testBothOlderModelsKeepPositionsFlowsAndHistoryInV3() throws {
        let models = try XCTUnwrap(Bundle(for: BondEntity.self).url(forResource: "MyBondManager", withExtension: "momd"))
        for name in ["MyBondManager", "MyBondManagerV2"] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            defer { try? FileManager.default.removeItem(at: root) }
            let model = try XCTUnwrap(NSManagedObjectModel(contentsOf: models.appendingPathComponent(name + ".mom")))
            let source = NSPersistentContainer(name: "MyBondManager", managedObjectModel: model)
            let url = root.appendingPathComponent("migration.sqlite")
            let description = NSPersistentStoreDescription(url: url); description.shouldAddStoreAsynchronously = false
            source.persistentStoreDescriptions = [description]
            var failure: Error?
            source.loadPersistentStores { _, error in failure = error }; if let failure { throw failure }
            let bond = NSManagedObject(entity: model.entitiesByName["BondEntity"]!, insertInto: source.viewContext)
            let id = UUID(), date = TestPortfolio.date("2027-01-01T00:00:00Z")
            for (key, value) in ["id": id, "name": "Old", "isin": "DE0000000001", "issuer": "Issuer",
                "wkn": "TEST01", "depotBank": "Bank", "couponRate": 3.375, "initialPrice": 900.0,
                "parValue": 1000.0, "yieldToMaturity": 4.0, "acquisitionDate": TestPortfolio.date("2026-01-01T00:00:00Z"),
                "maturityDate": date] as [String: Any] { bond.setValue(value, forKey: key) }
            let flow = NSManagedObject(entity: model.entitiesByName["CashFlowEntity"]!, insertInto: source.viewContext)
            flow.setValue(date, forKey: "date"); flow.setValue(33.75, forKey: "amount")
            flow.setValue("interest", forKey: "nature"); flow.setValue(bond, forKey: "bond")
            let history = NSManagedObject(entity: model.entitiesByName["HistoricalValuation"]!, insertInto: source.viewContext)
            history.setValue(UUID(), forKey: "id"); history.setValue(date, forKey: "date")
            history.setValue("Bond", forKey: "assetType"); history.setValue(NSDecimalNumber(value: 1000), forKey: "investedCapital")
            try source.viewContext.save(); source.viewContext.reset()
            for store in source.persistentStoreCoordinator.persistentStores { try source.persistentStoreCoordinator.remove(store) }
            let target = NSPersistentContainer(name: "MyBondManager", managedObjectModel: TestPortfolio.model)
            let upgraded = NSPersistentStoreDescription(url: url); upgraded.shouldAddStoreAsynchronously = false
            upgraded.shouldMigrateStoreAutomatically = true; upgraded.shouldInferMappingModelAutomatically = true
            target.persistentStoreDescriptions = [upgraded]
            failure = nil; target.loadPersistentStores { _, error in failure = error }; if let failure { throw failure }
            let restored = try XCTUnwrap(target.viewContext.fetch(BondEntity.fetchRequest()).first)
            XCTAssertEqual(restored.id, id); XCTAssertEqual(restored.couponRate, 3.375)
            XCTAssertEqual(restored.cashFlowsArray.first?.amount, 33.75)
            XCTAssertNil(try BondTermsStore.read(restored)); XCTAssertFalse(BondTermsStore.isReady(restored))
            XCTAssertEqual(try target.viewContext.count(for: HistoricalValuation.fetchRequest()), 1)
            target.viewContext.reset()
            for store in target.persistentStoreCoordinator.persistentStores { try target.persistentStoreCoordinator.remove(store) }
        }
    }
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
