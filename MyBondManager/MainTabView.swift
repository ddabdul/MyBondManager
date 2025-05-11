//
// MainTabView.swift
// MyBondManager
// Updated 12/05/2025 – use Identifiable wrapper for URL
//
// Updated 15/05/2025 - Refactored tabs into separate views

import SwiftUI
import CoreData
import AppKit   // for NSOpenPanel

/// A simple Identifiable wrapper around a URL, to drive SwiftUI’s `sheet(item:)`.
private struct FolderSelection: Identifiable {
   let url: URL
   var id: URL { url }
}

@available(macOS 13.0, *)
struct MainTabView: View {
    // MARK: – Environment
    // These environment objects are shared across the app
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var notifier: LaunchNotifier

    // MARK: – Shared State
    // State that affects multiple tabs or is controlled at the top level
    @State private var validationSelection: FolderSelection? // For the export validation sheet
    @State private var selectedDepotBank: String = "All" // Shared filter state

    // MARK: - Local State (Only keep state *not* moved to tab views)
    // The sheet/alert states (showingAddBond, showingMatured, showingRecalc, etc.)
    // have been moved into their respective tab views.
    // The refresh state (isRefreshingETF) has moved to ETFTabView.


    var body: some View {
        GeometryReader { geo in
            ZStack {
    AppTheme.panelBackground.ignoresSafeArea()

                // The main TabView containing instances of the separate tab views
                TabView {
                    // Instantiate Portfolio Tab View
                    PortfolioTabView(
                        geo: geo, // Pass geometry down
                        selectedDepotBank: $selectedDepotBank, // Pass shared binding
                        toggleSidebarAction: toggleSidebar, // Pass actions as closures
                        exportAction: chooseFolderAndExport,
                        importAction: chooseFolderAndImport
                    )
                    .tabItem {
                        Label("Bond Portfolio", systemImage: "list.bullet")
                    }

                    // Instantiate Cash Flow Tab View
                    CashFlowTabView(
                        geo: geo,
                        selectedDepotBank: $selectedDepotBank,
                        toggleSidebarAction: recalculateAllCashFlows, // Pass tab-specific action (defined here)
                        exportAction: toggleSidebar,
                        importAction: chooseFolderAndExport,
                        recalculateAction: chooseFolderAndImport
                    )
                                                  .tabItem {
                                                      Label("Bond CashFlows", systemImage: "dollarsign.circle")
                                                  }

                    // Instantiate ETF Tab View
                    ETFTabView(
                        geo: geo,
                        selectedDepotBank: $selectedDepotBank, // Pass shared binding (used by PortfolioSummaryView within this tab)
                        toggleSidebarAction: toggleSidebar,
                        exportAction: chooseFolderAndExport,
                        importAction: chooseFolderAndImport
                    )
                      .tabItem {
                          Label("ETF", systemImage: "chart.bar")
                      }
                }
                                          .toolbarBackground(AppTheme.panelBackground)
                                   .background(Color.clear)
                // Optional: Keep environment context here or set higher up in the App
                // Keeping it here matches the original code's placement.
                                                 .environment(\.managedObjectContext,
                                                               PersistenceController.shared.container.viewContext)

                // Optional: Keep the notifier alert here if it's for app-wide errors,
                // or move specific alerts (like ETF refresh) to their tabs.
                // The ETF refresh alert was moved, so this might only be needed
                // if 'notifier.alertMessage' is used for other high-level issues.
                // If not, this alert can be removed. Let's assume the ETF alert
                // is the primary use case and remove this one.
                /*
                .alert(
                     Text("App Error"),
                     isPresented: Binding(
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
                 */
            }
        }
        // Present the shared validation view when a folder has been selected and exported
         .sheet(item: $validationSelection) { selection in
            ExportValidationView(folderURL: selection.url)
            .environment(\.managedObjectContext, viewContext) // Ensure context is passed to the sheet
                .environmentObject(notifier) // Pass environment objects if needed by the sheet
        }
        // Other top-level sheets or alerts that are not specific to a single tab would go here
    }

    // MARK: – Shared Helper Actions
    // These methods are called by buttons in the tab views via closures

    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?
        .tryToPerform(
    #selector(NSSplitViewController.toggleSidebar(_:)),
         with: nil
        )
    }

    private func chooseFolderAndExport() {
        let panel = NSOpenPanel()
        panel.title                   = "Select folder to export JSON"
        panel.canChooseDirectories    = true
        panel.canChooseFiles          = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let folder = panel.url {
            // Perform export on a background queue
            DispatchQueue.global(qos: .userInitiated).async {
                let granted = folder.startAccessingSecurityScopedResource() // Access needs to happen on the queue performing file ops
                defer { if granted { folder.stopAccessingSecurityScopedResource() } }

                do {
                try ExportManager().exportAll(to: folder, from: viewContext)
                    DispatchQueue.main.async {
                        // Update UI state on the main queue after success
                        validationSelection = FolderSelection(url: folder)
                    }
                } catch {
                    DispatchQueue.main.async {
                        // Update notifier alert message on the main queue after error
                        notifier.alertMessage = "Export failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func chooseFolderAndImport() {
        let panel = NSOpenPanel()
        panel.title = "Select folder to import JSON"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let folder = panel.url {
            // Perform import on a background queue
            DispatchQueue.global(qos: .userInitiated).async {
                let granted = folder.startAccessingSecurityScopedResource() // Access needs to happen on the queue performing file ops
                defer { if granted { folder.stopAccessingSecurityScopedResource() } }

                do {
                try ImportManager().importAll(from: folder, into: viewContext) // Requires viewContext
                } catch {
                    DispatchQueue.main.async {
                        // Update notifier alert message on the main queue after error
                        notifier.alertMessage = "Import failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    // MARK: – Helper: recalc cash flows
    // This method is called by the CashFlowTabView via a closure

    private func recalculateAllCashFlows() {
        // Use a background context for lengthy operations
          let ctx = PersistenceController.shared.backgroundContext
        ctx.perform {
        let req: NSFetchRequest<BondEntity> = BondEntity.fetchRequest()
            do {
            let bonds = try ctx.fetch(req)
                let gen   = CashFlowGenerator(context: ctx) // Requires context
                for b in bonds {
                try gen.regenerateCashFlows(for: b)
                }
                if ctx.hasChanges {
                    try ctx.save()
                }
                // The alert state (showingRecalc) is now in CashFlowTabView.
                // That view sets its local state *after* calling this action.
                // No need to update state here anymore.
            } catch {
                // Handle error, e.g., log or show a global alert if needed,
                // but specific recalculation errors might be handled within the tab.
            }
        }
    }
}

// MARK: - Preview

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
        // Provide required environment objects for the preview
        .environment(
            \.managedObjectContext,
                                 PersistenceController.shared.container.viewContext // Use a temporary or mock context
        )
        .environmentObject(
            LaunchNotifier(context:
                    PersistenceController.shared.container.viewContext
                          ) // Mock Notifier
        )
    }
}
