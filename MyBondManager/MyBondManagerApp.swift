
//
//  MyBondManagerApp.swift
//  MyBondManager
//  Adjusted to CoreData + ETF price refresh
//  Created by Olivier on 11/04/2025.
//  Updated on 08/06/2025.
//

import SwiftUI
import CoreData

@main
struct BondPortfolioManagerApp: App {
    let persistenceController: PersistenceController
    private let isTesting: Bool
    @StateObject private var priceUpdater: ETFPriceUpdater
    @StateObject private var notifier: LaunchNotifier
    private let viewContext: NSManagedObjectContext

    init() {
        isTesting = ProcessInfo.processInfo.environment["MYBONDMANAGER_TESTING"] == "1"
            || ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
        persistenceController = isTesting ? PersistenceController(inMemory: true) : .shared
        let context = persistenceController.container.viewContext
        self.viewContext = context
        let notifier = LaunchNotifier()
        _notifier = StateObject(wrappedValue: notifier)
        let updater = ETFPriceUpdater(container: persistenceController.container)
        _priceUpdater = StateObject(wrappedValue: updater)
        if !isTesting { persistenceController.deleteEmptyETFs() }
    }

    var body: some Scene {
        Window("", id: "main") {
            MainTabView()
                .environment(\.managedObjectContext, viewContext)
                .environment(\.portfolioContainer, persistenceController.container)
                .environmentObject(notifier)
                .environmentObject(priceUpdater)
                .preferredColorScheme(.dark)
                .accentColor(.white)
                .background(Color.black)
                .toolbarBackground(.visible, for: .windowToolbar)
                .toolbarBackground(Color.panelBackground, for: .windowToolbar)
                .task {
                    guard !isTesting else { return }
                    await notifier.processLaunch(in: persistenceController.container)
                    do {
                        try await priceUpdater.refreshAllPrices()
                    } catch {
                        let previous = notifier.alertMessage.map { $0 + "\n\n" } ?? ""
                        notifier.alertMessage = previous + "Price refresh failed: \(error.localizedDescription)"
                    }
                }
                .alert(
                    Text("Portfolio Update"),
                    isPresented: Binding<Bool>(
                        get: { notifier.alertMessage != nil },
                        set: { if !$0 { notifier.alertMessage = nil } }
                    )
                ) {
                    Button("OK", role: .cancel) {
                        notifier.alertMessage = nil
                    }
                } message: {
                    Text(notifier.alertMessage ?? "")
                        .frame(minWidth: 300, alignment: .leading)
                }
        }
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)
        .defaultSize(width: 1200, height: 800)
    }

}
