//
//  MainTabView.swift
//  MyBondManager
//  Updated 05/05/2025 – add ETF refresh, sell & export buttons
//

import SwiftUI
import CoreData
import AppKit

@available(macOS 13.0, *)
struct MainTabView: View {
    // MARK: – Environment
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var notifier: LaunchNotifier

    // MARK: – State
    @State private var showingMaturedSheet    = false
    @State private var showingAddBondView     = false
    @State private var showingRecalcAlert     = false
    @State private var showingAddETFView      = false
    @State private var showingSellETFView     = false
    @State private var isRefreshingETF        = false

    var body: some View {
        GeometryReader { geo in
            ZStack {
                AppTheme.panelBackground
                    .ignoresSafeArea()

                TabView {
                    portfolioTab(geo: geo)
                    cashFlowTab(geo: geo)
                    etfTab(geo: geo)
                }
                .toolbarBackground(AppTheme.panelBackground)
                .background(Color.clear)
                .environment(\.managedObjectContext,
                             PersistenceController.shared.container.viewContext)
            }
        }
    }

    /// Toggle the sidebar
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?
            .tryToPerform(#selector(NSSplitViewController.toggleSidebar(_:)), with: nil)
    }

    // MARK: — Portfolio Tab

    @ViewBuilder
    private func portfolioTab(geo: GeometryProxy) -> some View {
        NavigationSplitView {
            PortfolioSummaryView()
                .frame(minWidth: geo.size.width/3)
                .background(AppTheme.panelBackground)
        } detail: {
            BondTableView()
                .background(AppTheme.panelBackground)
        }
        .navigationSplitViewColumnWidth(
            min:   geo.size.width/3,
            ideal: geo.size.width/3,
            max:   geo.size.width*0.5
        )
        .toolbar {
            // ── LEFT SIDE ──
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help("Toggle Sidebar")
            }
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    ExportManager().exportAllWithUserChoice(from: viewContext)
                }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Export JSON…")
            }

            // ── RIGHT SIDE ──
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddBondView = true } label: {
                    Image(systemName: "plus")
                }
                .help("Add a new bond")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingMaturedSheet = true } label: {
                    Label("Matured", systemImage: "clock.arrow.circlepath")
                }
                .help("Show matured bonds")
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
            Label("Bond Portfolio", systemImage: "list.bullet")
        }
    }

    // MARK: — Cash Flow Tab

    @ViewBuilder
    private func cashFlowTab(geo: GeometryProxy) -> some View {
        NavigationSplitView {
            PortfolioSummaryView()
                .frame(minWidth: geo.size.width/3)
                .background(AppTheme.panelBackground)
        } detail: {
            CashFlowView()
                .background(AppTheme.panelBackground)
        }
        .navigationSplitViewColumnWidth(
            min:   geo.size.width/3,
            ideal: geo.size.width/3,
            max:   geo.size.width*0.5
        )
        .toolbar {
            // ── LEFT SIDE ──
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help("Toggle Sidebar")
            }
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    ExportManager().exportAllWithUserChoice(from: viewContext)
                }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Export JSON…")
            }

            // ── RIGHT SIDE ──
            ToolbarItem(placement: .primaryAction) {
                Button { recalculateAllCashFlows() } label: {
                    Label("Recalculate", systemImage: "arrow.clockwise")
                }
                .help("Recalculate cash flows")
            }
        }
        .alert("Cash flows recalculated", isPresented: $showingRecalcAlert) {
            Button("OK", role: .cancel) { }
        }
        .tabItem {
            Label("Bond CashFlows", systemImage: "dollarsign.circle")
        }
    }

    // MARK: — ETF Tab

    @ViewBuilder
    private func etfTab(geo: GeometryProxy) -> some View {
        NavigationSplitView {
            PortfolioSummaryView()
                .frame(minWidth: geo.size.width/3)
                .background(AppTheme.panelBackground)
        } detail: {
            ETFListView()
                .background(AppTheme.panelBackground)
        }
        .navigationSplitViewColumnWidth(
            min:   geo.size.width/3,
            ideal: geo.size.width/3,
            max:   geo.size.width*0.5
        )
        .toolbar {
            // ── LEFT SIDE ──
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help("Toggle Sidebar")
            }
            ToolbarItem(placement: .navigation) {
                Button(action: {
                    ExportManager().exportAllWithUserChoice(from: viewContext)
                }) {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Export JSON…")
            }

            // ── RIGHT SIDE ──
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddETFView = true } label: {
                    Image(systemName: "plus")
                }
                .help("Add a new ETF holding")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        isRefreshingETF = true
                        let updater = ETFPriceUpdater(context: viewContext)
                        do {
                            try await updater.refreshAllPrices()
                        } catch {
                            notifier.alertMessage = """
                                ❗️ Failed refreshing ETF prices:
                                \(error.localizedDescription)
                                """
                        }
                        isRefreshingETF = false
                    }
                } label: {
                    if isRefreshingETF {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise.circle")
                    }
                }
                .help("Refresh all ETF prices")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingSellETFView = true
                } label: {
                    Image(systemName: "minus.circle")
                }
                .help("Sell ETF shares")
            }
        }
        .sheet(isPresented: $showingAddETFView) {
            AddHoldingView()
                .frame(minWidth: 500, minHeight: 400)
        }
        .sheet(isPresented: $showingSellETFView) {
            SellETFView()
                .frame(minWidth: 500, minHeight: 400)
        }
        .alert(
            Text("ETF Refresh Error"),
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
        .tabItem {
            Label("ETF", systemImage: "chart.bar")
        }
    }

    // MARK: — Helper

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
            .environmentObject(
                LaunchNotifier(context:
                    PersistenceController.shared.container.viewContext
                )
            )
    }
}

