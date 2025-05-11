//
//  PortfolioTabView.swift
//  MyBondManager
//
//  Created by Olivier on 11/05/2025.
//


// PortfolioTabView.swift
// MyBondManager
//

import SwiftUI
import CoreData // Needed for Core Data interactions and passing context
// AppKit is not needed directly here unless child views require it

@available(macOS 13.0, *)
struct PortfolioTabView: View {

    // MARK: - Environment
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var notifier: LaunchNotifier // Assuming notifier might be used by subviews or sheets

    // MARK: - Passed State/Dependencies
    let geo: GeometryProxy // Passed from MainTabView for layout calculations
    @Binding var selectedDepotBank: String // Shared state binding

    // MARK: - Actions Passed from Parent (MainTabView)
    // These actions control the shared features like sidebar, export, import
    let toggleSidebarAction: () -> Void
    let exportAction: () -> Void
    let importAction: () -> Void

    // MARK: - State specific to this tab
    @State private var showingAddBond = false
    @State private var showingMatured = false

    // Note: validationSelection and its sheet remain in MainTabView
    // because the export action (which triggers validationSelection)
    // is initiated from the parent or via passed action.

    var body: some View {
        // This NavigationSplitView represents the content of this specific tab
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
            BondTableView(selectedDepotBank: $selectedDepotBank)
                .background(AppTheme.panelBackground)
                // Pass environment context if needed by BondTableView
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
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebarAction) {
                    Image(systemName: "sidebar.leading")
                }
                .help("Toggle Sidebar")
            }
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

            // ── RIGHT (Primary Actions specific to Portfolio) ──
            // Use local state for tab-specific actions
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddBond = true } label: {
                    Image(systemName: "plus")
                }
                .help("Add a new bond")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingMatured = true } label: {
                    Label("Matured", systemImage: "clock.arrow.circlepath")
                }
                .help("Show matured bonds")
            }
        }
        // Sheets specific to the Portfolio tab
        .sheet(isPresented: $showingAddBond) {
            AddBondViewAsync()
                 // Sheets presented from this view need access to the context
                .environment(\.managedObjectContext, viewContext)
                 .environmentObject(notifier) // Pass environment objects if needed
        }
        .sheet(isPresented: $showingMatured) {
            MaturedBondsView()
                .frame(minWidth: 700, minHeight: 400)
                 // Sheets presented from this view need access to the context
                .environment(\.managedObjectContext, viewContext)
                 .environmentObject(notifier) // Pass environment objects if needed
        }
        // Note: The .tabItem modifier is placed on the instance
        // of this view within the parent TabView.
    }
}

