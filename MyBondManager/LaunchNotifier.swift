import SwiftUI
import CoreData

@MainActor
final class LaunchNotifier: ObservableObject {
    @Published var alertMessage: String?
    private let defaults: UserDefaults
    private var isProcessing = false

    init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    func processLaunch(in container: NSPersistentContainer, now: Date = Date(),
                       stage: ((NSManagedObjectContext, Date, Date) throws -> [String])? = nil) async {
        guard !isProcessing else { return }
        isProcessing = true
        defer { isProcessing = false }
        let since = defaults.object(forKey: "lastLaunchDate") as? Date
            ?? Calendar.current.date(byAdding: .day, value: -7, to: now)!
        do {
            guard since <= now else { throw PortfolioError("The last launch date is in the future.") }
            let processor = stage ?? LaunchEventProcessor.stage
            let messages = try await PortfolioTransaction.run(in: container) { context in
                try processor(context, since, now)
            }
            defaults.set(now, forKey: "lastLaunchDate")
            if !messages.isEmpty { alertMessage = "Since your last visit:\n" + messages.joined(separator: "\n") }
        } catch {
            alertMessage = "Could not record portfolio events: \(error.localizedDescription). Events will be retried next launch."
        }
    }
}
