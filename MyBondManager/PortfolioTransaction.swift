import CoreData

struct PortfolioError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum PortfolioTransaction {
    private static let registryGuard = NSLock()
    private static let storeLocks = NSMapTable<NSPersistentStoreCoordinator, NSLock>.weakToStrongObjects()
    private static func lock(for coordinator: NSPersistentStoreCoordinator) -> NSLock {
        registryGuard.lock()
        defer { registryGuard.unlock() }
        if let lock = storeLocks.object(forKey: coordinator) { return lock }
        let lock = NSLock()
        storeLocks.setObject(lock, forKey: coordinator)
        return lock
    }
    static func run<T>(in container: NSPersistentContainer,
                       changes: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        let storeLock = lock(for: container.persistentStoreCoordinator)
        let context = container.newBackgroundContext()
        return try await context.perform {
            storeLock.lock()
            defer { storeLock.unlock() }
            do {
                let result = try changes(context)
                if context.hasChanges { try context.save() }
                return result
            } catch {
                context.rollback()
                throw error
            }
        }
    }
}
