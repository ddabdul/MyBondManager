import SwiftUI
import CoreData

private struct PortfolioContainerKey: EnvironmentKey {
    static let defaultValue: NSPersistentContainer? = nil
}
extension EnvironmentValues {
    var portfolioContainer: NSPersistentContainer? {
        get { self[PortfolioContainerKey.self] }
        set { self[PortfolioContainerKey.self] = newValue }
    }
}
