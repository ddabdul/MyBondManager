import CoreData

enum BondDeletion {
    static func stage(ids: [NSManagedObjectID], context: NSManagedObjectContext) throws {
        for id in ids {
            guard let bond = try context.existingObject(with: id) as? BondEntity else {
                throw PortfolioError("A selected bond no longer exists. Refresh the portfolio and try again.")
            }
            context.delete(bond)
        }
    }
}
