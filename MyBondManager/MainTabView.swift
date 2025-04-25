//  MainTabView.swift
//  MyBondManager
//
//  Created by Olivier on 13/04/2025.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var viewModel = BondPortfolioViewModel()
    @State private var showingMaturedSheet = false
    @State private var showingAddBondView = false

    var body: some View {
        TabView {
            // ──────────────────────────────────
            // Portfolio Tab
            // ──────────────────────────────────
            NavigationSplitView {
                // Sidebar: ~1/3 width for the summary
                PortfolioSummaryView()
                    .navigationSplitViewColumnWidth(min: 250, ideal: 350, max: 400)
            } detail: {
                // Detail: ~2/3 width for the table
                BondTableView(viewModel: viewModel)
                    .toolbar {
                        // 1) Add-bond button
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                showingAddBondView = true
                            } label: {
                                Image(systemName: "plus")
                            }
                        }
                        // 2) Matured-bonds button
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                showingMaturedSheet = true
                            } label: {
                                Label("Matured", systemImage: "clock.arrow.circlepath")
                            }
                        }
                    }
            }
            // Present modals for adding and matured bonds
            .sheet(isPresented: $showingAddBondView) {
                AddBondViewAsync(viewModel: viewModel)
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
                // Sidebar: ~1/3 width for the summary
                PortfolioSummaryView()
                    .navigationSplitViewColumnWidth(min: 250, ideal: 350, max: 400)
            } detail: {
                CashFlowView(viewModel: viewModel)
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

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
            .environment(
                \.managedObjectContext,
                PersistenceController.shared.container.viewContext
            )
    }
}
