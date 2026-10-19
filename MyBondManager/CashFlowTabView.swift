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
    var reviewTermsAction: (() -> Void)? = nil
    var displayModeSelection: Binding<String>? = nil
    var navigationSelection: Binding<CashFlowCalendarNavigation>? = nil

    // MARK: - Local State
    @State private var showingRecalc = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            CashFlowView(selectedDepotBank: $selectedDepotBank, reviewTerms: reviewTermsAction,
                displayModeSelection: displayModeSelection, navigationSelection: navigationSelection)
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(notifier)
                .background(CashFlowStyle.background)
        }
        .alert("Cash flows recalculated", isPresented: $showingRecalc) {
            Button("OK", role: .cancel) {}
        }
        .background(CashFlowStyle.background)
    }
}

