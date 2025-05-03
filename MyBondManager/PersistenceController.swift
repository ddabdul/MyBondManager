//  PersistenceController.swift
//  MyBondManager
//  Created by Olivier on 11/04/2025.
//  Updated on 02/05/2025.


import CoreData

struct PersistenceController {
    static let shared = PersistenceController()

    let container: NSPersistentContainer
    let backgroundContext: NSManagedObjectContext

    init(inMemory: Bool = false) {
        container = NSPersistentContainer(name: "MyBondManager")
        if inMemory {
            container.persistentStoreDescriptions.first!.url = URL(fileURLWithPath: "/dev/null")
        }
        container.loadPersistentStores { desc, error in
            if let error = error {
                fatalError("Unable to load Core Data store: \(error)")
            }
        }

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

    /// Call this whenever you create or update a BondEntity.
    func saveAndGenerateCashFlows(bond: BondEntity) {
        let viewCtx = container.viewContext
        guard viewCtx.hasChanges else { return }
        do {
            try viewCtx.save()
        } catch {
            fatalError("Failed to save viewContext: \(error)")
        }

        backgroundContext.perform {
            let bgBond = self.backgroundContext.object(with: bond.objectID) as! BondEntity
            do {
                try CashFlowGenerator(context: self.backgroundContext)
                        .regenerateCashFlows(for: bgBond)
            } catch {
                print("⚠️ cashflow regen failed:", error)
            }
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
