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

    @State private var showingAddBond = false
    @State private var showingMatured = false
    @State private var isRefreshingETF = false
    @State private var showingSellETF = false
    @State private var showingAddETF = false
    @State private var showRecalculatedAlert = false  // ✅ New alert state

    enum Tab: String, CaseIterable, Identifiable {
        case portfolio, cashflows, etf
        var id: String { rawValue }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Global controls
            HStack {
                Picker("", selection: $selectedTab) {
                    Label("Portfolio", systemImage: "list.bullet").tag(Tab.portfolio)
                    Label("Cash Flows", systemImage: "dollarsign.circle").tag(Tab.cashflows)
                    Label("ETF", systemImage: "chart.bar").tag(Tab.etf)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 300)

                Spacer()

                // Dynamic buttons depending on view
                switch selectedTab {
                case .portfolio:
                    Button("Export", action: chooseFolderAndExport)
                    Button("Import", action: chooseFolderAndImport)
                    Button {
                        showingAddBond = true
                    } label: {
                        Label("Add Bond", systemImage: "plus")
                    }
                    Button {
                        showingMatured = true
                    } label: {
                        Label("Matured", systemImage: "clock.arrow.circlepath")
                    }

                case .cashflows:
                    Button {
                        recalculateAllCashFlows()
                    } label: {
                        Label("Recalculate", systemImage: "arrow.clockwise")
                    }

                case .etf:
                    Button {
                        refreshETFPrices()
                    } label: {
                        if isRefreshingETF {
                            ProgressView()
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    Button {
                        showingAddETF = true
                    } label: {
                        Label("Add", systemImage: "plus")
                    }
                    Button {
                        showingSellETF = true
                    } label: {
                        Label("Sell", systemImage: "minus.circle")
                    }
                }
            }
            .padding()
            .background(AppTheme.panelBackground)

            Divider()

            NavigationSplitView {
                PortfolioSummaryView(selectedDepotBank: $selectedDepotBank)
                    .background(AppTheme.panelBackground)
            } detail: {
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
        .sheet(isPresented: $showingAddETF) {
            AddHoldingView()
                .frame(minWidth: 500, minHeight: 400)
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(notifier)
        }
        .sheet(isPresented: $showingSellETF) {
            SellETFView()
                .frame(minWidth: 500, minHeight: 400)
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(notifier)
        }
        .alert("Cash Flows recalculated", isPresented: $showRecalculatedAlert) {
            Button("OK", role: .cancel) {}
        }
        .environment(\.managedObjectContext, viewContext)
    }

    // MARK: – Content

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
            case .cashflows:
                CashFlowTabView(
                    geo: geo,
                    selectedDepotBank: $selectedDepotBank,
                    exportAction: chooseFolderAndExport,
                    importAction: chooseFolderAndImport,
                    recalculateAction: recalculateAllCashFlows
                )
            case .etf:
                ETFTabView(
                    geo: geo,
                    selectedDepotBank: $selectedDepotBank,
                    exportAction: chooseFolderAndExport,
                    importAction: chooseFolderAndImport
                )
            }
        }
    }

    // MARK: – Import / Export

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

    // MARK: – Recalculate

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
                DispatchQueue.main.async {
                    showRecalculatedAlert = true  // ✅ Show success alert
                }
            } catch {
                DispatchQueue.main.async {
                    notifier.alertMessage = "❗️ Recalculation failed: \(error.localizedDescription)"
                }
            }
        }
    }

    // MARK: – Refresh ETF Prices

    private func refreshETFPrices() {
        isRefreshingETF = true
        Task {
            let updater = ETFPriceUpdater(context: viewContext)
            do {
                try await updater.refreshAllPrices()
            } catch {
                DispatchQueue.main.async {
                    notifier.alertMessage = "❗️ Failed refreshing ETF prices: \(error.localizedDescription)"
                }
            }
            DispatchQueue.main.async {
                isRefreshingETF = false
            }
        }
    }
}
