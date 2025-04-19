//  MainTabView.swift
//  BondPortfolioV2
//
//  Created by Olivier on 13/04/2025.
//

import SwiftUI

struct MainTabView: View {
    @StateObject private var viewModel = BondPortfolioViewModel()
    @State private var showingMaturedSheet = false
    @State private var selectedTab = 0

    // your lilac color
    private let lilac = Color(red: 200/255, green: 180/255, blue: 220/255)

    var body: some View {
        TabView(selection: $selectedTab) {
            // ──────────────────────────────────
            // Portfolio Tab
            // ──────────────────────────────────
            NavigationView {
                PortfolioSummaryView(viewModel: viewModel)
                BondTableView(viewModel: viewModel)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                showingMaturedSheet = true
                            } label: {
                                Label("Matured", systemImage: "clock.arrow.circlepath")
                            }
                        }
                    }
                    .sheet(isPresented: $showingMaturedSheet) {
                        MaturedBondsView()
                            .frame(minWidth: 700, minHeight: 400)
                    }
            }
            .tabItem {
                Label("Portfolio", systemImage: "list.bullet")
            }
            .tag(0)

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
            .tag(1)
        }
        // this tint will be applied to the selected tab’s icon & text
        .tint(lilac)
    }
}

struct MainTabView_Previews: PreviewProvider {
    static var previews: some View {
        MainTabView()
    }
}
