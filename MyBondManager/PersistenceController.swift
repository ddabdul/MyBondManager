//
//  PersistenceController.swift
//  MyBondManager
//  Adjusted to CoreData
//  Created by Olivier on 25/04/2025.
//


import CoreData

struct PersistenceController {
    static let shared = PersistenceController()
    
    let container: NSPersistentContainer
    
    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "MyBondManager")
        if inMemory {
            container.persistentStoreDescriptions.first?.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { desc, error in
            if let error = error {
                fatalError("Unable to load Core Data store: \(error)")
            }
        }
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }
    
    func saveContext() {
        let ctx = container.viewContext
        if ctx.hasChanges {
            do {
                try ctx.save()
            } catch {
                fatalError("Failed to save context: \(error)")
            }
        }
    }
}
