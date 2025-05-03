//
//  MainTabView.swift
//  MyBondManager
//  Updated 12/05/2025 – use Identifiable wrapper for URL
//

import SwiftUI
import CoreData
import AppKit   // for NSOpenPanel

/// A simple Identifiable wrapper around a URL, to drive SwiftUI’s `sheet(item:)`.
private struct FolderSelection: Identifiable {
    let url: URL
    var id: URL { url }
}

@available(macOS 13.0, *)
struct MainTabView: View {
    // MARK: – Environment
    @Environment(\.managedObjectContext) private var viewContext
    @EnvironmentObject private var notifier: LaunchNotifier

    // MARK: – State for existing sheets & alerts
    @State private var showingAddBond    = false
    @State private var showingMatured    = false
    @State private var showingRecalc     = false
    @State private var showingAddETF     = false
    @State private var showingSellETF    = false
    @State private var isRefreshingETF   = false

    // MARK: – State for export validation sheet
    @State private var validationSelection: FolderSelection?

    var body: some View {
        GeometryReader { geo in
            ZStack {
                AppTheme.panelBackground.ignoresSafeArea()

                TabView {
                    portfolioTab(geo: geo)
                    cashFlowTab(geo: geo)
                    etfTab(geo: geo)
                }
                .toolbarBackground(AppTheme.panelBackground)
                .background(Color.clear)
                .environment(\.managedObjectContext,
                             PersistenceController.shared.container.viewContext)
            }
        }
        // Present the validation view when a folder has been selected and exported
        .sheet(item: $validationSelection) { selection in
            ExportValidationView(folderURL: selection.url)
                .environment(\.managedObjectContext, viewContext)
        }
    }

    // MARK: – Sidebar toggle
    private func toggleSidebar() {
        NSApp.keyWindow?.firstResponder?
            .tryToPerform(
                #selector(NSSplitViewController.toggleSidebar(_:)),
                with: nil
            )
    }

    // MARK: – Folder‐panel helpers

    private func chooseFolderAndExport() {
        let panel = NSOpenPanel()
        panel.title                   = "Select folder to export JSON"
        panel.canChooseDirectories    = true
        panel.canChooseFiles          = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let folder = panel.url {
            let granted = folder.startAccessingSecurityScopedResource()
            defer { if granted { folder.stopAccessingSecurityScopedResource() } }

            DispatchQueue.global(qos: .userInitiated).async {
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
        panel.title                   = "Select folder to import JSON"
        panel.canChooseDirectories    = true
        panel.canChooseFiles          = false
        panel.allowsMultipleSelection = false

        if panel.runModal() == .OK, let folder = panel.url {
            let granted = folder.startAccessingSecurityScopedResource()
            defer { if granted { folder.stopAccessingSecurityScopedResource() } }

            DispatchQueue.global(qos: .userInitiated).async {
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

    // MARK: — Portfolio Tab

    @ViewBuilder
    private func portfolioTab(geo: GeometryProxy) -> some View {
        NavigationSplitView {
            PortfolioSummaryView()
                .frame(minWidth: geo.size.width / 3)
                .background(AppTheme.panelBackground)
        } detail: {
            BondTableView()
                .background(AppTheme.panelBackground)
        }
        .navigationSplitViewColumnWidth(
            min: geo.size.width / 3,
            ideal: geo.size.width / 3,
            max: geo.size.width * 0.5
        )
        .toolbar {
            // ── LEFT ──
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help("Toggle Sidebar")
            }
            ToolbarItem(placement: .navigation) {
                Button(action: chooseFolderAndExport) {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Export JSON…")
            }
            ToolbarItem(placement: .navigation) {
                Button(action: chooseFolderAndImport) {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Import JSON…")
            }

            // ── RIGHT ──
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddBond = true } label: {
                    Image(systemName: "plus")
                }
                .help("Add a new bond")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingMatured = true } label: {
                    Label("Matured", systemImage: "clock.arrow.circlepath")
                }
                .help("Show matured bonds")
            }
        }
        .sheet(isPresented: $showingAddBond) {
            AddBondViewAsync()
        }
        .sheet(isPresented: $showingMatured) {
            MaturedBondsView()
                .frame(minWidth: 700, minHeight: 400)
        }
        .tabItem {
            Label("Bond Portfolio", systemImage: "list.bullet")
        }
    }

    // MARK: — Cash Flow Tab

    @ViewBuilder
    private func cashFlowTab(geo: GeometryProxy) -> some View {
        NavigationSplitView {
            PortfolioSummaryView()
                .frame(minWidth: geo.size.width / 3)
                .background(AppTheme.panelBackground)
        } detail: {
            CashFlowView()
                .background(AppTheme.panelBackground)
        }
        .navigationSplitViewColumnWidth(
            min: geo.size.width / 3,
            ideal: geo.size.width / 3,
            max: geo.size.width * 0.5
        )
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help("Toggle Sidebar")
            }
            ToolbarItem(placement: .navigation) {
                Button(action: chooseFolderAndExport) {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Export JSON…")
            }
            ToolbarItem(placement: .navigation) {
                Button(action: chooseFolderAndImport) {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Import JSON…")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { recalculateAllCashFlows() } label: {
                    Label("Recalculate", systemImage: "arrow.clockwise")
                }
                .help("Recalculate cash flows")
            }
        }
        .alert("Cash flows recalculated", isPresented: $showingRecalc) {
            Button("OK", role: .cancel) {}
        }
        .tabItem {
            Label("Bond CashFlows", systemImage: "dollarsign.circle")
        }
    }

    // MARK: — ETF Tab

    @ViewBuilder
    private func etfTab(geo: GeometryProxy) -> some View {
        NavigationSplitView {
            PortfolioSummaryView()
                .frame(minWidth: geo.size.width / 3)
                .background(AppTheme.panelBackground)
        } detail: {
            ETFListView()
                .background(AppTheme.panelBackground)
        }
        .navigationSplitViewColumnWidth(
            min: geo.size.width / 3,
            ideal: geo.size.width / 3,
            max: geo.size.width * 0.5
        )
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button(action: toggleSidebar) {
                    Image(systemName: "sidebar.leading")
                }
                .help("Toggle Sidebar")
            }
            ToolbarItem(placement: .navigation) {
                Button(action: chooseFolderAndExport) {
                    Image(systemName: "square.and.arrow.up")
                }
                .help("Export JSON…")
            }
            ToolbarItem(placement: .navigation) {
                Button(action: chooseFolderAndImport) {
                    Image(systemName: "square.and.arrow.down")
                }
                .help("Import JSON…")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingAddETF = true } label: {
                    Image(systemName: "plus")
                }
                .help("Add a new ETF holding")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    Task {
                        isRefreshingETF = true
                        let updater = ETFPriceUpdater(context: viewContext)
                        do {
                            try await updater.refreshAllPrices()
                        } catch {
                            notifier.alertMessage = """
                                ❗️ Failed refreshing ETF prices:
                                \(error.localizedDescription)
                                """
                        }
                        isRefreshingETF = false
                    }
                } label: {
                    if isRefreshingETF {
                        ProgressView()
                    } else {
                        Image(systemName: "arrow.clockwise.circle")
                    }
                }
                .help("Refresh all ETF prices")
            }
            ToolbarItem(placement: .primaryAction) {
                Button { showingSellETF = true } label: {
                    Image(systemName: "minus.circle")
                }
                .help("Sell ETF shares")
            }
        }
        .sheet(isPresented: $showingAddETF) {
            AddHoldingView()
                .frame(minWidth: 500, minHeight: 400)
        }
        .sheet(isPresented: $showingSellETF) {
            SellETFView()
                .frame(minWidth: 500, minHeight: 400)
        }
        .alert(
            Text("ETF Refresh Error"),
            isPresented: Binding(
                get: { notifier.alertMessage != nil },
                set: { if !$0 { notifier.alertMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                notifier.alertMessage = nil
            }
        } message: {
            Text(notifier.alertMessage ?? "")
                .frame(minWidth: 300, alignment: .leading)
        }
        .tabItem {
            Label("ETF", systemImage: "chart.bar")
        }
    }

    // MARK: — Helper: recalc cash flows

    private func recalculateAllCashFlows() {
        let ctx = PersistenceController.shared.backgroundContext
        ctx.perform {
            let req: NSFetchRequest<BondEntity> = BondEntity.fetchRequest()
            do {
                let bonds = try ctx.fetch(req)
                let gen   = CashFlowGenerator(context: ctx)
                for b in bonds {
                    try gen.regenerateCashFlows(for: b)
                }
                if ctx.hasChanges {
                    try ctx.save()
                }
                DispatchQueue.main.async {
                    showingRecalc = true
                }
            } catch {
                // ignore
            }
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
            .environmentObject(
                LaunchNotifier(context:
                    PersistenceController.shared.container.viewContext
                )
            )
    }
}
