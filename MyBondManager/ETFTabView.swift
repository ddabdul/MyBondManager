// ETFTabView.swift
// MyBondManager
//

import SwiftUI
import CoreData // Needed for Core Data operations (ETFListView, price updater)

@available(macOS 13.0, *)
struct ETFTabView: View {

    // MARK: - Environment
    @Environment(\.managedObjectContext) private var viewContext // Needed for ETFListView, AddHoldingView, SellETFView, price updater
    @EnvironmentObject private var notifier: LaunchNotifier // Used for refresh error alerts

    // MARK: - Passed State/Dependencies
    let geo: GeometryProxy // Passed from MainTabView for layout calculations
    // Note: selectedDepotBank is passed down to PortfolioSummaryView,
    // even if ETFListView itself doesn't use it for filtering.
    @Binding var selectedDepotBank: String

    // MARK: - Actions Passed from Parent (MainTabView)
    // These actions control shared features like sidebar, export, import
    let toggleSidebarAction: () -> Void
    let exportAction: () -> Void
    let importAction: () -> Void

    // MARK: - State specific to this tab
    @State private var showingAddETF = false
    @State private var showingSellETF = false
    @State private var isRefreshingETF = false // Controls the refresh button indicator

    // Note: validationSelection and its sheet remain in MainTabView
    // because the export action (which triggers validationSelection)
    // is initiated from the parent or via passed action.

    var body: some View {
        // This NavigationSplitView represents the content of the ETF tab
        NavigationSplitView {
            // Sidebar View (using the shared selectedDepotBank binding)
            PortfolioSummaryView(selectedDepotBank: $selectedDepotBank)
                .frame(minWidth: geo.size.width / 3) // Use passed geometry
                .background(AppTheme.panelBackground)
                // Pass environment context if needed by PortfolioSummaryView
                 .environment(\.managedObjectContext, viewContext)
                 .environmentObject(notifier) // Pass environment objects if needed
        } detail: {
            // Detail View (ETF specific)
            ETFListView()
                .background(AppTheme.panelBackground)
                // Pass environment context if needed by ETFListView
                 .environment(\.managedObjectContext, viewContext)
                 .environmentObject(notifier) // Pass environment objects if needed
        }
        // Apply split view width settings using passed geometry
        .navigationSplitViewColumnWidth(
            min: geo.size.width / 3,
            ideal: geo.size.width / 3,
            max: geo.size.width * 0.5
        )
        // Define the toolbar specifically for this tab's NavigationView context
        .toolbar {
            // ── LEFT (Navigation) ──
            // Use passed actions for common toolbar items
           // ToolbarItem(placement: .navigation) {
           //     Button(action: toggleSidebarAction) {
           //         Image(systemName: "sidebar.leading")
            //    }
            //    .help("Toggle Sidebar")
          //  }
            ToolbarItem(placement: .navigation) {
                Button(action: exportAction) {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Export JSON…")
            }
            ToolbarItem(placement: .navigation) {
                Button(action: importAction) {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Import JSON…")
            }

            // ── RIGHT (Primary Actions specific to ETF) ──
            // Use local state for tab-specific actions
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddETF = true } label: {
                    Image(systemName: "plus")
                }
                .help("Add a new ETF holding")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    // Trigger the async price refresh
                    Task {
                        isRefreshingETF = true // Show progress indicator
                        let updater = ETFPriceUpdater(context: viewContext) // Requires access to viewContext
                        do {
                            try await updater.refreshAllPrices()
                        } catch {
                            // Update notifier alert message on the main queue
                            DispatchQueue.main.async {
                                notifier.alertMessage = """
                                ❗️ Failed refreshing ETF prices:
                                \(error.localizedDescription)
                                """
                            }
                        }
                        // Hide progress indicator on the main queue
                        DispatchQueue.main.async {
                             isRefreshingETF = false
                        }
                    }
                } label: {
                    // Show progress view or refresh icon based on state
                    if isRefreshingETF {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise.circle")
                    }
                }
                .help("Refresh all ETF prices")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingSellETF = true } label: {
                    Image(systemName: "minus.circle")
                }
                .help("Sell ETF shares")
            }
        }
        // Sheets specific to the ETF tab
        .sheet(isPresented: $showingAddETF) {
            AddHoldingView()
                .frame(minWidth: 500, minHeight: 400)
                 // Sheets presented from this view need access to the context
                .environment(\.managedObjectContext, viewContext)
                 .environmentObject(notifier) // Pass environment objects if needed
        }
        .sheet(isPresented: $showingSellETF) {
            SellETFView()
                .frame(minWidth: 500, minHeight: 400)
                 // Sheets presented from this view need access to the context
                .environment(\.managedObjectContext, viewContext)
                 .environmentObject(notifier) // Pass environment objects if needed
        }
        // Alert tied to the EnvironmentObject's alertMessage
        .alert(
            Text("ETF Refresh Error"), // Use a static title for clarity
            isPresented: Binding( // Use a binding derived from the notifier's state
                get: { notifier.alertMessage != nil },
                set: { if !$0 { notifier.alertMessage = nil } } // Clear message when alert is dismissed
            )
        ) {
            Button("OK", role: .cancel) {
                notifier.alertMessage = nil // Ensure message is cleared on OK
            }
        } message: {
            Text(notifier.alertMessage ?? "") // Display the message from the notifier
                 .frame(minWidth: 300, alignment: .leading) // Optional styling
        }
        // Note: The .tabItem modifier is placed on the instance
        // of this view within the parent TabView.
    }
}

