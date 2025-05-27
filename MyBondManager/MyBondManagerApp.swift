
//  MyBondManagerApp.swift
//  MyBondManager
//  Adjusted to CoreData + ETF price refresh
//  Created by Olivier on 11/04/2025.
//  Updated on 02/05/2025.

import SwiftUI
import CoreData

@main
struct BondPortfolioManagerApp: App {
    let persistenceController = PersistenceController.shared
    @StateObject private var notifier: LaunchNotifier
    private let viewContext: NSManagedObjectContext

    init() {
        let context = persistenceController.container.viewContext
        self.viewContext = context
        _notifier = StateObject(wrappedValue: LaunchNotifier(context: context))
        // Cleanup any ETFs with no holdings
        persistenceController.deleteEmptyETFs()
    }

    var body: some Scene {
        // ✅ Use Window instead of WindowGroup for macOS 14+
        Window("", id: "main") {
            ZStack {
                Color.black.ignoresSafeArea() // Full background fill

                MainTabView()
                    .environment(\.managedObjectContext, viewContext)
                    .environmentObject(notifier)
                    .preferredColorScheme(.dark)
                    .accentColor(.white)
            }
            .task {
                let updater = ETFPriceUpdater(context: viewContext)
                do {
                    try await updater.refreshAllPrices()
                } catch {
                    // Optionally show alert
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
        // ✅ Scene modifiers (only work with Window, not WindowGroup)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)
  //      .windowTitleHidden(true)
    }
}
