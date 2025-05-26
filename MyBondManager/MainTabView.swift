//
//  MainTabView.swift
//  MyBondManager
//

import SwiftUI
import CoreData
import AppKit

private struct FolderSelection: Identifiable {
    let url: URL
    var id: URL { url }
}

@available(macOS 13.0, *)
struct MainTabView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var notifier: LaunchNotifier

    @State private var selectedDepotBank: String = "All"
    @State private var selectedTab: Tab = .portfolio
    @State private var validationSelection: FolderSelection?
    @State private var isSidebarVisible: Bool = true

    enum Tab: String, CaseIterable, Identifiable {
        case portfolio, cashflows, etf
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Top bar: picker + action buttons + sidebar toggle
            HStack {
                Picker("View", selection: $selectedTab) {
                    Label("Portfolio", systemImage: "list.bullet").tag(Tab.portfolio)
                    Label("Cash Flows", systemImage: "dollarsign.circle").tag(Tab.cashflows)
                    Label("ETF", systemImage: "chart.bar").tag(Tab.etf)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(maxWidth: 300)

                Spacer()

                HStack(spacing: 12) {
                    Button("Export", action: chooseFolderAndExport)
                    Button("Import", action: chooseFolderAndImport)

                    if selectedTab == .portfolio {
                        Button(action: {}) {
                            Label("Add Bond", systemImage: "plus")
                        }

                        Button(action: {}) {
                            Label("Matured", systemImage: "clock.arrow.circlepath")
                        }
                    }

                    Button(action: toggleSidebar) {
                        Image(systemName: "sidebar.leading")
                    }
                    .help("Toggle Sidebar")
                }
            }
            .padding(.horizontal)
            .padding(.top, 8)

            Divider()

            // Content area: sidebar + main detail
            HStack(spacing: 0) {
                if isSidebarVisible {
                    PortfolioSummaryView(selectedDepotBank: $selectedDepotBank)
                        .frame(minWidth: 280, idealWidth: 320, maxWidth: 360)
                        .background(AppTheme.panelBackground)
                        .transition(.move(edge: .leading))
                }

                Divider()

                detailContent(for: selectedTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.panelBackground)
            }
        }
        .sheet(item: $validationSelection) { selection in
            ExportValidationView(folderURL: selection.url)
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(notifier)
        }
        .environment(\.managedObjectContext, viewContext)
    }

    // MARK: - Detail View Switcher

    @ViewBuilder
    private func detailContent(for tab: Tab) -> some View {
        GeometryReader { geo in
            switch tab {
            case .portfolio:
                PortfolioTabView(
                    geo: geo,
                    selectedDepotBank: $selectedDepotBank,
                    exportAction: chooseFolderAndExport,
                    importAction: chooseFolderAndImport
                )
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(notifier)

            case .cashflows:
                CashFlowTabView(
                    geo: geo,
                    selectedDepotBank: $selectedDepotBank,
                    exportAction: chooseFolderAndExport,
                    importAction: chooseFolderAndImport,
                    recalculateAction: recalculateAllCashFlows
                )
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(notifier)

            case .etf:
                ETFTabView(
                    geo: geo,
                    selectedDepotBank: $selectedDepotBank,
                    exportAction: chooseFolderAndExport,
                    importAction: chooseFolderAndImport
                )
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(notifier)
            }
        }
    }

    // MARK: - Sidebar

    private func toggleSidebar() {
        withAnimation {
            isSidebarVisible.toggle()
        }
    }

    // MARK: - Export / Import

    private func chooseFolderAndExport() {
        let panel = NSOpenPanel()
        panel.title = "Select folder to export JSON"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let folder = panel.url {
            DispatchQueue.global(qos: .userInitiated).async {
                let granted = folder.startAccessingSecurityScopedResource()
                defer { if granted { folder.stopAccessingSecurityScopedResource() } }

                do {
                    try ExportManager().exportAll(to: folder, from: viewContext)
                    DispatchQueue.main.async {
                        validationSelection = FolderSelection(url: folder)
                    }
                } catch {
                    DispatchQueue.main.async {
                        notifier.alertMessage = "Export failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    private func chooseFolderAndImport() {
        let panel = NSOpenPanel()
        panel.title = "Select folder to import JSON"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let folder = panel.url {
            DispatchQueue.global(qos: .userInitiated).async {
                let granted = folder.startAccessingSecurityScopedResource()
                defer { if granted { folder.stopAccessingSecurityScopedResource() } }

                do {
                    try ImportManager().importAll(from: folder, into: viewContext)
                } catch {
                    DispatchQueue.main.async {
                        notifier.alertMessage = "Import failed: \(error.localizedDescription)"
                    }
                }
            }
        }
    }

    // MARK: - Recalculate Cash Flows

    private func recalculateAllCashFlows() {
        let ctx = PersistenceController.shared.backgroundContext
        ctx.perform {
            let req: NSFetchRequest<BondEntity> = BondEntity.fetchRequest()
            do {
                let bonds = try ctx.fetch(req)
                let gen = CashFlowGenerator(context: ctx)
                for b in bonds {
                    try gen.regenerateCashFlows(for: b)
                }
                if ctx.hasChanges {
                    try ctx.save()
                }
            } catch {
                // Handle error
            }
        }
    }
}
