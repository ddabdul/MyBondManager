//
//  MainTabView.swift
//  MyBondManager
//  Updated 15/05/2025 – add ETF tab
//

import SwiftUI
import CoreData

struct MainTabView: View {
    @State private var showingMaturedSheet  = false
    @State private var showingAddBondView   = false
    @State private var showingRecalcAlert   = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                // 1) Underlay everything with your dark-grey panel background
                AppTheme.panelBackground
                    .ignoresSafeArea()

                // 2) TabView on top, transparent so grey shows through
                TabView {
                    // — Portfolio Tab —
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
                        ToolbarItem(placement: .primaryAction) {
                            Button { showingAddBondView = true } label: {
                                Image(systemName: "plus")
                            }
                        }
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

                    // — Cash-Flow Tab —
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
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                recalculateAllCashFlows()
                            } label: {
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

                    // — ETF Tab —
                    // Replace `ETFView()` with your actual ETF view.
                    NavigationSplitView {
                        PortfolioSummaryView()
                            .frame(minWidth: geo.size.width / 3)
                            .background(AppTheme.panelBackground)
                    } detail: {
                        ETFTestView()  // or whatever detail you need
                            .background(AppTheme.panelBackground)
                    }
                    .navigationSplitViewColumnWidth(
                        min:   geo.size.width / 3,
                        ideal: geo.size.width / 3,
                        max:   geo.size.width * 0.5
                    )
                    .toolbar {
                        // Add any ETF‐specific toolbar items here
                    }
                    .tabItem {
                        Label("ETF", systemImage: "chart.bar")
                    }
                }
                // paint the macOS window toolbar / tab strip grey
                .toolbarBackground(AppTheme.panelBackground)
                .background(Color.clear)
                .environment(
                    \.managedObjectContext,
                    PersistenceController.shared.container.viewContext
                )
            }
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
