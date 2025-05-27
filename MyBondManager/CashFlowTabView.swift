//
//  CashFlowTabView.swift
//  MyBondManager
//

import SwiftUI
import CoreData

@available(macOS 13.0, *)
struct CashFlowTabView: View {

    // MARK: - Environment
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var notifier: LaunchNotifier

    // MARK: - Passed State/Dependencies
    let geo: GeometryProxy
    @Binding var selectedDepotBank: String

    // MARK: - Actions Passed from Parent
    let exportAction: () -> Void
    let importAction: () -> Void
    let recalculateAction: () -> Void

    // MARK: - Local State
    @State private var showingRecalc = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CashFlowView(selectedDepotBank: $selectedDepotBank)
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(notifier)
                .background(AppTheme.panelBackground)
        }
        .alert("Cash flows recalculated", isPresented: $showingRecalc) {
            Button("OK", role: .cancel) {}
        }
        .padding()
    }
}

