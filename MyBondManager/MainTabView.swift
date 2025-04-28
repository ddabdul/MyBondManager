// MainTabView.swift
// MyBondManager
// Updated on 28/04/2025 to add manual cash‐flow recalculation

import SwiftUI
import CoreData

struct MainTabView: View {
    @State private var showingMaturedSheet = false
    @State private var showingAddBondView = false
    @State private var showingRecalcAlert = false   // ← new

    var body: some View {
        GeometryReader { geo in
            TabView {
                // ──────────────────────────────────
                // Portfolio Tab
                // ──────────────────────────────────
                NavigationSplitView {
                    PortfolioSummaryView()
                        .frame(minWidth: geo.size.width / 3)
                } detail: {
                    BondTableView()
                }
                .navigationSplitViewColumnWidth(
                    min: geo.size.width / 3,
                    ideal: geo.size.width / 3,
                    max: geo.size.width * 0.5
                )
                .toolbar {
                    // 1) Add-bond button
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: { showingAddBondView = true }) {
                            Image(systemName: "plus")
                        }
                    }
                    // 2) Matured-bonds button
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
                NavigationSplitView {
                    PortfolioSummaryView()
                        .frame(minWidth: geo.size.width / 3)
                } detail: {
                    CashFlowView()
                }
                .navigationSplitViewColumnWidth(
                    min: geo.size.width / 3,
                    ideal: geo.size.width / 3,
                    max: geo.size.width * 0.5
                )
                // ← NEW TOOLBAR ITEM FOR MANUAL RECALC
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button(action: {
                            recalculateAllCashFlows()
                        }) {
                            Label("Recalculate", systemImage: "arrow.clockwise")
                        }
                    }
                }
                // CONFIRMATION ALERT
                .alert("Cash flows recalculated", isPresented: $showingRecalcAlert) {
                    Button("OK", role: .cancel) { }
                }
                .tabItem {
                    Label("Cash Flow", systemImage: "dollarsign.circle")
                }
            }
            // Inject the real viewContext for every child view
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

                // notify success on main thread
                DispatchQueue.main.async {
                    showingRecalcAlert = true
                }
            } catch {
                // you might surface this more gracefully in UI
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
