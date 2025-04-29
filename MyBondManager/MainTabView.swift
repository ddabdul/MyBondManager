// MainTabView.swift
// MyBondManager
// Updated on 01/05/2025 to apply consistent panel background

import SwiftUI
import CoreData

struct MainTabView: View {
    @State private var showingMaturedSheet = false
    @State private var showingAddBondView = false
    @State private var showingRecalcAlert = false

    var body: some View {
        GeometryReader { geo in
            TabView {
                // ──────────────────────────────────
                // Portfolio Tab
                // ──────────────────────────────────
                ZStack {
                    // Underlay: same dark-grey panel background
                    AppTheme.panelBackground
                        .ignoresSafeArea()

                    NavigationSplitView {
                        PortfolioSummaryView()
                            .frame(minWidth: geo.size.width / 3)
                            .background(AppTheme.panelBackground)
                    } detail: {
                        BondTableView()
                            .background(AppTheme.panelBackground)
                    }
                }
                .navigationSplitViewColumnWidth(
                    min: geo.size.width / 3,
                    ideal: geo.size.width / 3,
                    max: geo.size.width * 0.5
                )
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showingAddBondView = true }) {
                            Image(systemName: "plus")
                        }
                    }
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showingMaturedSheet = true }) {
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

                // ──────────────────────────────────
                // Cash-Flow Tab
                // ──────────────────────────────────
                ZStack {
                    AppTheme.panelBackground
                        .ignoresSafeArea()

                    NavigationSplitView {
                        PortfolioSummaryView()
                            .frame(minWidth: geo.size.width / 3)
                            .background(AppTheme.panelBackground)
                    } detail: {
                        CashFlowView()
                            .background(AppTheme.panelBackground)
                    }
                }
                .navigationSplitViewColumnWidth(
                    min: geo.size.width / 3,
                    ideal: geo.size.width / 3,
                    max: geo.size.width * 0.5
                )
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            recalculateAllCashFlows()
                        }) {
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
            .environment(
                \.managedObjectContext,
                PersistenceController.shared.container.viewContext
            )
        }
    }

    /// Manually regenerate cash flows for every bond,
    /// ignoring the one-time migration flag.
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
