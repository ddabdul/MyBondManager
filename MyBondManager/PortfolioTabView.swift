//
//  PortfolioTabView.swift
//  MyBondManager
//

import SwiftUI
import CoreData

@available(macOS 13.0, *)
struct PortfolioTabView: View {

    // MARK: - Environment
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var notifier: LaunchNotifier

    // MARK: - Passed State
    let geo: GeometryProxy
    @Binding var selectedDepotBank: String

    // MARK: - Actions Passed from Parent
    let exportAction: () -> Void
    let importAction: () -> Void

    // MARK: - Local State
    @State private var showingAddBond = false
    @State private var showingMatured = false

    var body: some View {
        VStack(spacing: 0) {
            // Table content area
            BondTableView(selectedDepotBank: $selectedDepotBank)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(notifier)
                .background(AppTheme.panelBackground)
        }
        .sheet(isPresented: $showingAddBond) {
            AddBondViewAsync()
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(notifier)
        }
        .sheet(isPresented: $showingMatured) {
            MaturedBondsView()
                .frame(minWidth: 700, minHeight: 400)
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(notifier)
        }
        .onReceive(NotificationCenter.default.publisher(for: .addBondTapped)) { _ in
            showingAddBond = true
        }
        .onReceive(NotificationCenter.default.publisher(for: .maturedTapped)) { _ in
            showingMatured = true
        }
    }
}
