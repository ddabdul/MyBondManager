//  PersistenceController.swift
//  MyBondManager
//  Created by Olivier on 11/04/2025.
//  Updated on 02/05/2025.


import CoreData

struct PersistenceController {
    static let shared = PersistenceController()
    static let managedObjectModel = NSPersistentContainer(name: "MyBondManager").managedObjectModel

    let container: NSPersistentContainer
    let backgroundContext: NSManagedObjectContext

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "MyBondManager", managedObjectModel: Self.managedObjectModel)
        if inMemory {
            container.persistentStoreDescriptions.first!.type = NSInMemoryStoreType
        }
        for description in container.persistentStoreDescriptions {
            description.shouldMigrateStoreAutomatically = true
            description.shouldInferMappingModelAutomatically = true
        }
        container.loadPersistentStores { desc, error in
            if let error = error {
                fatalError("Unable to load Core Data store: \(error)")
            }
        }

        container.viewContext.automaticallyMergesChangesFromParent = true

        // configure contexts
        container.viewContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
        backgroundContext = container.newBackgroundContext()
        backgroundContext.mergePolicy = NSMergeByPropertyObjectTrumpMergePolicy
    }

    /// Deletes any ETFEntity whose holding set is empty (i.e. totalShares == 0)
    func deleteEmptyETFs() {
        let ctx = container.viewContext
        let req: NSFetchRequest<ETFEntity> = ETFEntity.fetchRequest()
        req.predicate = NSPredicate(format: "etftoholding.@count == 0")

        do {
            let empty = try ctx.fetch(req)
            for etf in empty {
                ctx.delete(etf)
            }
            if ctx.hasChanges {
                try ctx.save()
            }
        } catch {
            print("❗️ Failed cleaning empty ETFs:", error)
        }
    }

    /// Legacy two-phase helper. Active forms use PortfolioTransaction for a single save.
    @MainActor
    func saveAndGenerateCashFlows(bond: BondEntity) async throws {
        let viewContext = container.viewContext
        if viewContext.hasChanges { try viewContext.save() }
        let bondID = bond.objectID
        try await PortfolioTransaction.run(in: container) { context in
            guard let stored = try context.existingObject(with: bondID) as? BondEntity else {
                throw PortfolioError("The bond no longer exists.")
            }
            try CashFlowGenerator(context: context).regenerateCashFlows(for: stored)
        }
    }

    /// A generic save for other parts of the app.
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
