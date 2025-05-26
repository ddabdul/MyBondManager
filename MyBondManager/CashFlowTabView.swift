//
//  CashFlowTabView.swift
//  MyBondManager
//
//  Created by Olivier on 11/05/2025.
//


// CashFlowTabView.swift
// MyBondManager
//

import SwiftUI
import CoreData // Needed for Core Data operations

@available(macOS 13.0, *)
struct CashFlowTabView: View {

    // MARK: - Environment
    @Environment(\.managedObjectContext) private var viewContext // Needed for CashFlowView and recalculation
    @EnvironmentObject private var notifier: LaunchNotifier // Assuming notifier might be used

    // MARK: - Passed State/Dependencies
    let geo: GeometryProxy // Passed from MainTabView for layout calculations
    @Binding var selectedDepotBank: String // Shared state binding for filtering views

    // MARK: - Actions Passed from Parent (MainTabView)
    // These actions control shared features and the recalculation process
    let toggleSidebarAction: () -> Void
    let exportAction: () -> Void
    let importAction: () -> Void
    let recalculateAction: () -> Void // Action to trigger the cash flow recalculation

    // MARK: - State specific to this tab
    @State private var showingRecalc = false // Controls the "Recalculated" alert

    var body: some View {
        // This NavigationSplitView represents the content of the Cash Flow tab
        NavigationSplitView {
            // Sidebar View (using the shared selectedDepotBank binding)
            PortfolioSummaryView(selectedDepotBank: $selectedDepotBank)
                .frame(minWidth: geo.size.width / 3) // Use passed geometry
                .background(AppTheme.panelBackground)
                // Pass environment context if needed by PortfolioSummaryView
                 .environment(\.managedObjectContext, viewContext)
                 .environmentObject(notifier) // Pass environment objects if needed
        } detail: {
            // Detail View (using the shared selectedDepotBank binding)
            CashFlowView(selectedDepotBank: $selectedDepotBank)
                .background(AppTheme.panelBackground)
                // Pass environment context if needed by CashFlowView
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
          //  ToolbarItem(placement: .navigation) {
          //      Button(action: toggleSidebarAction) {
          //          Image(systemName: "sidebar.leading")
          //      }
          //      .help("Toggle Sidebar")
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

            // ── RIGHT (Primary Action specific to Cash Flow) ──
            // Use the passed recalculate action and local state for the alert
            ToolbarItem(placement: .primaryAction) {
                Button {
                    recalculateAction() // Call the action passed from the parent
                    showingRecalc = true // Set state to show the alert
                } label: {
                    Label("Recalculate", systemImage: "arrow.clockwise")
                }
                .help("Recalculate cash flows")
            }
        }
        // Alert specific to the Cash Flow tab's recalculation action
        .alert("Cash flows recalculated", isPresented: $showingRecalc) {
            Button("OK", role: .cancel) {}
        }
        // Note: The .tabItem modifier is placed on the instance
        // of this view within the parent TabView.
    }
}

