
//  MyBondManagerApp.swift
//  MyBondManager
//  Adjusted to CoreData
//  Created by Olivier on 11/04/2025.
//  Updated on 28/04/2025.

import SwiftUI
import CoreData

@main
struct BondPortfolioManagerApp: App {
    // 1) Your Core Data stack
    let persistenceController = PersistenceController.shared

    // 2) LaunchNotifier as a StateObject so it lives for the app's lifetime
    @StateObject private var notifier: LaunchNotifier

    init() {
        // Initialize the notifier with your viewContext
        let context = persistenceController.container.viewContext
        _notifier = StateObject(wrappedValue: LaunchNotifier(context: context))

        // 3) Run one-off CashFlow migration to seed existing bonds
        //       CashFlowMigration.performIfNeeded()
    }

    var body: some Scene {
        WindowGroup {
            ZStack {
                // Black background for the whole window
                Color.black
                    .ignoresSafeArea()

                MainTabView()
                    // 4) Inject both context and notifier
                    .environment(\.managedObjectContext, persistenceController.container.viewContext)
                    .environmentObject(notifier)
                    // Force dark mode so system text is white-on-black
                    .preferredColorScheme(.dark)
                    // Make buttons, toggles, etc. use white accent
                    .accentColor(.white)
            }
            // 5) Observe notifier and show alert once
            .onReceive(notifier.$alertMessage) { _ in }
            .alert(
                Text("Portfolio Update"),
                isPresented: Binding<Bool>(
                    get: { notifier.alertMessage != nil },
                    set: { if !$0 { notifier.alertMessage = nil } }
                ),
                actions: {
                    Button("OK", role: .cancel) {
                        notifier.alertMessage = nil
                    }
                },
                message: {
                    Text(notifier.alertMessage ?? "")
                        .frame(minWidth: 300, alignment: .leading)
                }
            )
        }
    }
}
