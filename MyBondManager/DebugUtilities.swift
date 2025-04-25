//// DebugUtilities.swift
import Foundation
import CoreData

/// Prints the file path for your Core Data SQLite store.
func logCoreDataStoreURL() {
    if let storeURL = PersistenceController
            .shared
            .container
            .persistentStoreDescriptions
            .first?
            .url {
        print("💾 Core Data store at: \(storeURL.path)")
    } else {
        print("⚠️ No persistent store URL found!")
    }
}

/// Fetches and dumps every BondEntity to the console.
func printAllBonds() {
    let ctx = PersistenceController.shared.container.viewContext
    let req: NSFetchRequest<BondEntity> = BondEntity.fetchRequest()
    do {
        let bonds = try ctx.fetch(req)
        print("🔍 Fetched \(bonds.count) bonds from Core Data")
        bonds.forEach { b in
            print(" • \(b.name) – YTM: \(b.yieldToMaturity)")
        }
    } catch {
        print("❌ Fetch error: \(error)")
    }
}

//  Untitled.swift
//  MyBondManager
//
//  Created by Olivier on 25/04/2025.
//

