import CoreData

struct PortfolioError: LocalizedError {
    let message: String
    init(_ message: String) { self.message = message }
    var errorDescription: String? { message }
}

enum PortfolioTransaction {
    static func run<T>(in container: NSPersistentContainer,
                       changes: @escaping (NSManagedObjectContext) throws -> T) async throws -> T {
        let context = container.newBackgroundContext()
        return try await context.perform {
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
