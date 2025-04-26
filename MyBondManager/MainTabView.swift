//
//  MainTabView.swift
//  MyBondManager
//
//  Created by Olivier on 13/04/2025.
//  Updated on 26/04/2025.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var viewModel = BondPortfolioViewModel()
    @State private var showingMaturedSheet = false
    @State private var showingAddBondView = false

    var body: some View {
        GeometryReader { geo in
            TabView {
                // ──────────────────────────────────
                // Portfolio Tab
                // ──────────────────────────────────
                NavigationSplitView {
                    PortfolioSummaryView()
                        // Force at least 1/3 of the window width
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
