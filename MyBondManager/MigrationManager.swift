import Foundation
import CoreData

struct MigrationManager {
    /// Returns the number of bonds imported
    @discardableResult
    static func migrateJSONIfNeeded() -> Int {
        let ctx = PersistenceController.shared.container.viewContext

        // 1) Skip if Core Data already has bonds
        let countRequest: NSFetchRequest<BondEntity> = BondEntity.fetchRequest()
        if let storedCount = try? ctx.count(for: countRequest), storedCount > 0 {
            print("📦 Core Data already has \(storedCount) bonds – skipping migration.")
            return 0
        }

        // 2) Locate bonds.json in Documents
        let documentsDir = FileManager.default
            .urls(for: .documentDirectory, in: .userDomainMask)
            .first!
        let fileURL = documentsDir.appendingPathComponent("bonds.json")

        // Diagnostic logging
        print("🔍 Looking for bonds.json at: \(fileURL.path)")
        let exists = FileManager.default.fileExists(atPath: fileURL.path)
        print("📁 File exists in Documents? \(exists)")

        // 3) Load the data
        let data: Data
        do {
            if exists {
                data = try Data(contentsOf: fileURL)
            } else if let bundleURL = Bundle.main.url(forResource: "bonds", withExtension: "json") {
                print("🛠️ Falling back to bundled bonds.json at: \(bundleURL.path)")
                data = try Data(contentsOf: bundleURL)
            } else {
                print("❌ No JSON file found in Documents or bundle.")
                return 0
            }
        } catch {
            print("❌ Failed to load bonds.json data: \(error)")
            return 0
        }

        // 4) Decode into [Bond]
        let bonds: [Bond]
        do {
            bonds = try JSONDecoder().decode([Bond].self, from: data)
        } catch {
            print("❌ Failed to decode bonds.json: \(error)")
            return 0
        }

        // 5) Import into Core Data
        for bond in bonds {
            let entity = BondEntity(context: ctx)
            entity.update(from: bond)
        }
        PersistenceController.shared.saveContext()
        print("✅ Imported \(bonds.count) bonds into Core Data.")

        // 6) Leave the JSON file in place as a backup
        return bonds.count
    }
}

