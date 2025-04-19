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
            NavigationView {
                PortfolioSummaryView(viewModel: viewModel)
                BondTableView(viewModel: viewModel)
            }
            .toolbar {
                // 1) Add‑bond button
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddBondView = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                // 2) Matured‑bonds button
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingMaturedSheet = true
                    } label: {
                        Label("Matured", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            // Present AddBondView when you tap the “+”
            .sheet(isPresented: $showingAddBondView) {
                AddBondView(viewModel: viewModel)
            }
            // Present MaturedBondsView when you tap the clock
            .sheet(isPresented: $showingMaturedSheet) {
                MaturedBondsView()
                    .frame(minWidth: 700, minHeight: 400)
            }
            .tabItem {
                Label("Portfolio", systemImage: "list.bullet")
            }

            // ──────────────────────────────────
            // Cash‑Flow Tab
            // ──────────────────────────────────
            NavigationView {
                PortfolioSummaryView(viewModel: viewModel)
                CashFlowMonthlyView(viewModel: viewModel)
            }
            .tabItem {
                Label("Cash Flow", systemImage: "dollarsign.circle")
            }
        }
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
