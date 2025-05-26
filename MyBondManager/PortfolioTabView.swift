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
        VStack(alignment: .leading, spacing: 16) {
            // Top Action Buttons (replaces old .toolbar)
            HStack {
                Button(action: exportAction) {
                    Label("Export", systemImage: "square.and.arrow.up")
                }
                Button(action: importAction) {
                    Label("Import", systemImage: "square.and.arrow.down")
                }

                Spacer()

                Button(action: { showingAddBond = true }) {
                    Label("Add Bond", systemImage: "plus")
                }

                Button(action: { showingMatured = true }) {
                    Label("Matured", systemImage: "clock.arrow.circlepath")
                }
            }
            .padding(.horizontal)

            Divider()

            BondTableView(selectedDepotBank: $selectedDepotBank)
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
        .padding()
    }
}
