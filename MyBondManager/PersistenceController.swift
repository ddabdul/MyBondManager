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

    /// Call this whenever you create or update a BondEntity.
    func saveAndGenerateCashFlows(bond: BondEntity) {
        // 1) Persist your bond edits on the viewContext
        let viewCtx = container.viewContext
        guard viewCtx.hasChanges else { return }
        do {
            try viewCtx.save()
        } catch {
            fatalError("Failed to save viewContext: \(error)")
        }

        // 2) Propagate changes to bg context (if you’re using NSPersistentStoreRemoteChangeNotifications,
        //    or simply refetch the Bond object in the bgContext)
        backgroundContext.perform {
            // If your BondEntity has an objectID, you can get its bgContext instance:
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

