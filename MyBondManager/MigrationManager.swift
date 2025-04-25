//
//  MigrationManager.swift
//  MyBondManager
//
//  Created by Olivier on 25/04/2025.
//


import Foundation
import CoreData

/// Manages one-time migration of existing JSON bond data into Core Data:
/// 1. Verifies Core Data store is empty to avoid duplicate imports.
/// 2. Loads and decodes `bonds.json` into `[Bond]`.
/// 3. Creates `BondEntity` for each bond, computing and storing YTM via `update(from:)`.
/// 4. Saves context and logs how many bonds were migrated. Does NOT delete the JSON file, keeping it for backup.
struct MigrationManager {
    /// Call this on first launch after shipping Core Data
    /// - Returns: number of bonds migrated; 0 if already migrated or on failure
    @discardableResult
    static func migrateJSONIfNeeded() -> Int {
        let ctx = PersistenceController.shared.container.viewContext

        // 1. Skip if already migrated
        let countRequest: NSFetchRequest<BondEntity> = BondEntity.fetchRequest()
        let storedCount = (try? ctx.count(for: countRequest)) ?? 0
        guard storedCount == 0 else {
            print("No migration needed: \(storedCount) bonds already in Core Data.")
            return 0
        }

        // 2. Load JSON
        let fileURL = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!
            .appendingPathComponent("bonds.json")

        guard let data = try? Data(contentsOf: fileURL),
              let bonds = try? JSONDecoder().decode([Bond].self, from: data) else {
            print("Failed to load or decode bonds.json")
            return 0
        }

        // 3. Import into Core Data (YTM computed in update)
        for bond in bonds {
            let entity = BondEntity(context: ctx)
            entity.update(from: bond)
        }
        do {
            try ctx.save()
            print("Successfully migrated \(bonds.count) bonds into Core Data.")
        } catch {
            print("Migration save error: \(error)")
            return 0
        }

        // 4. Summary: JSON file retained as backup
        return bonds.count
    }
}