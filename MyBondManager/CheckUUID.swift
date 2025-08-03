//
//  CheckUUID.swift
//  MyBondManager
//
//  Created by Olivier on 03/08/2025.
//

import CoreData

/// Checks all BondEntity objects in the persistent store and prints details
/// of any that are missing a UUID.
///
/// - Parameter context: The NSManagedObjectContext to fetch from.
func checkForMissingBondUUIDs(in context: NSManagedObjectContext) {
    // 1. Create a fetch request for BondEntity.
    let fetchRequest = NSFetchRequest<BondEntity>(entityName: "BondEntity")
    
    // 2. Set a predicate to find only bonds where the 'id' attribute is nil.
    fetchRequest.predicate = NSPredicate(format: "id == nil")
    
    do {
        // 3. Execute the fetch request.
        let bondsWithoutUUID = try context.fetch(fetchRequest)
        
        if bondsWithoutUUID.isEmpty {
            print("✅ SUCCESS: All BondEntity objects have a UUID.")
        } else {
            print("⚠️ WARNING: Found \(bondsWithoutUUID.count) BondEntity objects without a UUID.")
            for bond in bondsWithoutUUID {
                // Print some identifying info to help you find it.
                let name = bond.name
                let isin = bond.isin
                print("- Bond: '\(name)' (ISIN: \(isin)), acquired on \(bond.acquisitionDate)")
            }
        }
    } catch {
        print("❌ ERROR: Could not fetch bonds to check for missing UUIDs: \(error)")
    }
}

// Example of how to call it:
// let yourManagedObjectContext = ...
// checkForMissingBondUUIDs(in: yourManagedObjectContext)
