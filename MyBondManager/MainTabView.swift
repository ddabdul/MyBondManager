//  MainTabView.swift
//  MyBondManager
//  Updated 15/05/2025 – add ETF tab with “+” button
//

import SwiftUI
import CoreData
import AppKit

@available(macOS 13.0, *)
struct MainTabView: View {
    @State private var showingMaturedSheet   = false
    @State private var showingAddBondView    = false
    @State private var showingRecalcAlert    = false
    @State private var showingAddETFView     = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // Dark-grey panel background
                AppTheme.panelBackground
                    .ignoresSafeArea()

                // Our three-tab TabView
                TabView {
                    portfolioTab(geo: geo)
                    cashFlowTab(geo: geo)
                    etfTab(geo: geo)
                }
                .toolbarBackground(AppTheme.panelBackground)
                .background(Color.clear)
                .environment(
                    \.managedObjectContext,
                    PersistenceController.shared.container.viewContext
                )
            }
        }
    }

    /// Sends the AppKit action to toggle the split-view sidebar
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?
            .tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }

    // MARK: — Portfolio Tab

    @ViewBuilder
    private func portfolioTab(geo: GeometryProxy) -> some View {
        NavigationSplitView {
            PortfolioSummaryView()
                .frame(minWidth: geo.size.width / 3)
                .background(AppTheme.panelBackground)
        } detail: {
            BondTableView()
                .background(AppTheme.panelBackground)
        }
        .navigationSplitViewColumnWidth(
            min:   geo.size.width / 3,
            ideal: geo.size.width / 3,
            max:   geo.size.width * 0.5
        )
        .toolbar {
            // Sidebar toggle
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help("Toggle Sidebar")
            }
            // Add Bond
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddBondView = true } label: {
                    Image(systemName: "plus")
                }
            }
            // Matured Bonds
            ToolbarItem(placement: .primaryAction) {
                Button { showingMaturedSheet = true } label: {
                    Label("Matured", systemImage: "clock.arrow.circlepath")
                }
            }
        }
        .sheet(isPresented: $showingAddBondView) {
            AddBondViewAsync()
        }
        .sheet(isPresented: $showingMaturedSheet) {
            MaturedBondsView()
                .frame(minWidth: 700, minHeight: 400)
        }
        .tabItem {
            Label("Portfolio", systemImage: "list.bullet")
        }
    }

    // MARK: — Cash Flow Tab

    @ViewBuilder
    private func cashFlowTab(geo: GeometryProxy) -> some View {
        NavigationSplitView {
            PortfolioSummaryView()
                .frame(minWidth: geo.size.width / 3)
                .background(AppTheme.panelBackground)
        } detail: {
            CashFlowView()
                .background(AppTheme.panelBackground)
        }
        .navigationSplitViewColumnWidth(
            min:   geo.size.width / 3,
            ideal: geo.size.width / 3,
            max:   geo.size.width * 0.5
        )
        .toolbar {
            // Sidebar toggle
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help("Toggle Sidebar")
            }
            // Recalculate Cash Flows
            ToolbarItem(placement: .primaryAction) {
                Button { recalculateAllCashFlows() } label: {
                    Label("Recalculate", systemImage: "arrow.clockwise")
                }
            }
        }
        .alert("Cash flows recalculated", isPresented: $showingRecalcAlert) {
            Button("OK", role: .cancel) { }
        }
        .tabItem {
            Label("Cash Flow", systemImage: "dollarsign.circle")
        }
    }

    // MARK: — ETF Tab

    @ViewBuilder
    private func etfTab(geo: GeometryProxy) -> some View {
        NavigationSplitView {
            PortfolioSummaryView()
                .frame(minWidth: geo.size.width / 3)
                .background(AppTheme.panelBackground)
        } detail: {
            ETFListView()
                .background(AppTheme.panelBackground)
        }
        .navigationSplitViewColumnWidth(
            min:   geo.size.width / 3,
            ideal: geo.size.width / 3,
            max:   geo.size.width * 0.5
        )
        .toolbar {
            // Sidebar toggle
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help("Toggle Sidebar")
            }
            // Add ETF
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddETFView = true } label: {
                    Image(systemName: "plus")
                }
            }
        }
        .sheet(isPresented: $showingAddETFView) {
            AddHoldingView()
                .frame(minWidth: 500, minHeight: 400)
        }
        .tabItem {
            Label("ETF", systemImage: "chart.bar")
        }
    }

    // MARK: — Helper

    /// Regenerate cash‐flows on a background context, then flip the alert on main
    private func recalculateAllCashFlows() {
        let persistence = PersistenceController.shared
        let context = persistence.backgroundContext

        context.perform {
            let request: NSFetchRequest<BondEntity> = BondEntity.fetchRequest()
            do {
                let bonds = try context.fetch(request)
                let generator = CashFlowGenerator(context: context)
                for bond in bonds {
                    try generator.regenerateCashFlows(for: bond)
                }
                if context.hasChanges {
                    try context.save()
                }
                DispatchQueue.main.async {
                    showingRecalcAlert = true
                }
            } catch {
                print("❗️ Error recalculating cash flows: \(error)")
            }
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environment(
                \.managedObjectContext,
                PersistenceController.shared.container.viewContext
            )
    }
}
