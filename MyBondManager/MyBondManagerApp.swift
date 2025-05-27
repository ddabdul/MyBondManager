
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
        persistenceController.deleteEmptyETFs()
    }

    var body: some Scene {
        // ✅ Use `.window` for macOS 14+ customization
        Window("", id: "main") {
            MainTabView()
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(notifier)
                .preferredColorScheme(.dark)
                .accentColor(.white)
                .background(Color.black) // Ensures consistent background
                .toolbarBackground(.visible, for: .windowToolbar)
                .toolbarBackground(Color.panelBackground, for: .windowToolbar)
                .task {
                    let updater = ETFPriceUpdater(context: viewContext)
                    do {
                        try await updater.refreshAllPrices()
                    } catch {
                        // optionally set notifier.alertMessage
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
        .windowStyle(.titleBar) // ✅ keep traffic lights
        .windowToolbarStyle(.unifiedCompact)
        .windowResizability(.contentSize)
        .defaultSize(width: 1200, height: 800)
    }
}
