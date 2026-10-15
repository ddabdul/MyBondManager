//
//  MainTabView.swift
//  MyBondManager
//

import SwiftUI
import CoreData
import AppKit

private struct FolderSelection: Identifiable {
    let url: URL
    var bondOnly = false
    var excludedCount = 0
    var id: URL { url }
}

@available(macOS 13.0, *)
struct MainTabView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.portfolioContainer) private var portfolioContainer
    @EnvironmentObject private var priceUpdater: ETFPriceUpdater
    @EnvironmentObject private var notifier: LaunchNotifier

    @State private var selectedDepotBank: String = "All"
    @State private var selectedTab: Tab = .portfolio
    @State private var validationSelection: FolderSelection?

    @State private var pendingImport: PositionsPayload?
    @State private var showingImportConfirmation = false
    @State private var isTransferring = false

    @State private var showingAddBond = false
    @State private var showingMatured = false
    @State private var showingSellETF = false
    @State private var showingAddETF = false
    @State private var showRecalculatedAlert = false  // ✅ New alert state

    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \BondEntity.name, ascending: true)]) private var allBonds: FetchedResults<BondEntity>
    @State private var reviewModel: BondTermsReview?
    @State private var showingTermsReview = false
    @State private var pendingBondImport: PreparedBondTransfer?
    @State private var expectedBondIDs: Set<UUID> = []
    @State private var showingBondImportConfirmation = false
    @State private var recalculationMessage = ""
    private var unresolvedCount: Int { BondEligibility.excludedCount(Array(allBonds), on: MarketDay(date: Date())) }

    enum Tab: String, CaseIterable, Identifiable {
        case portfolio, cashflows, etf, history
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
                    Label("History", systemImage: "clock.arrow.circlepath").tag(Tab.history)
                    
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 300)

                Spacer()

                // Dynamic buttons depending on view
                switch selectedTab {
                case .portfolio:
                    Menu("Export", systemImage: "square.and.arrow.up") {
                        Button("Export Bonds (webapp + Mac)") { chooseExport(bondOnly: true) }
                        Button("Export All Positions", action: chooseFolderAndExport)
                    }.disabled(isTransferring)
                    Menu("Import", systemImage: "square.and.arrow.down") {
                        Button("Import Bonds") { chooseImport(bondOnly: true) }
                        Button("Import All Positions", action: chooseFolderAndImport)
                    }.disabled(isTransferring)
                    Button("Review Terms (\(unresolvedCount))", action: openTermsReview).disabled(isTransferring)
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
                        if priceUpdater.isRefreshing {
                            ProgressView()
                        } else {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                    .disabled(priceUpdater.isRefreshing)
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
                case .history:
                                    // No buttons needed for snapshot view
                                    EmptyView()
                }
            }
            .padding()
            .background(AppTheme.panelBackground)

            Divider()

            HSplitView {
                PortfolioSummaryView(selectedDepotBank: $selectedDepotBank)
                    .frame(minWidth: 260, idealWidth: 300, maxWidth: 360)
                    .background(AppTheme.panelBackground)

                detailContent(for: selectedTab)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(AppTheme.panelBackground)
            }
        }
        .sheet(item: $validationSelection) { selection in
            ExportValidationView(folderURL: selection.url, bondOnly: selection.bondOnly, excludedSchedules: selection.excludedCount)
                .environment(\.managedObjectContext, viewContext)
                .environmentObject(notifier)
        }
        .sheet(isPresented: $showingTermsReview) {
            if let reviewModel { BondTermsReviewView(review: reviewModel) }
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
        } message: { Text(recalculationMessage) }
        .alert("Replace the bond category?", isPresented: $showingBondImportConfirmation) {
            Button("Replace Bonds", role: .destructive) { applyPendingBondImport() }
            Button("Cancel", role: .cancel) { pendingBondImport = nil }
        } message: {
            if let transfer = pendingBondImport { Text(BondTermsPresentation.importSummary(transfer, existingIDs: expectedBondIDs)) }
        }
        .alert("Replace current positions?", isPresented: $showingImportConfirmation) {
            Button("Replace", role: .destructive) { applyPendingImport() }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("This replaces all current bond and ETF positions (\(pendingImport?.bonds.count ?? 0) bonds, \(pendingImport?.etfs.count ?? 0) ETFs). Existing history is kept; this transfer does not restore history. These legacy files do not restore approved native bond terms: imported bonds need review.")
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
                
            case .history:
                HistoricalSnapshotView(
                    geo: geo,
                    selectedDepotBank: $selectedDepotBank,
    //                exportAction: chooseFolderAndExport,
   //                 importAction: chooseFolderAndImport
                )
            }
        }
    }

    // MARK: – Import / Export

    private func chooseFolderAndExport() { chooseExport(bondOnly: false) }
    private func chooseExport(bondOnly: Bool) {
        guard !isTransferring else { return }
        let panel = NSOpenPanel()
        panel.title = "Select folder to export current positions (history is excluded)"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        isTransferring = true
        Task { @MainActor in
            defer { isTransferring = false }
            do {
                if bondOnly {
                    let published = try await ExportManager().exportBonds(to: folder, from: viewContext)
                    validationSelection = FolderSelection(url: published, bondOnly: true)
                } else {
                    let result = try await ExportManager().exportAllWithReport(to: folder, from: viewContext)
                    validationSelection = FolderSelection(url: result.folder, excludedCount: result.excludedCount)
                }
            } catch { notifier.alertMessage = "Export failed: \(error.localizedDescription)" }
        }
    }

    private func chooseFolderAndImport() { chooseImport(bondOnly: false) }
    private func chooseImport(bondOnly: Bool) {
        guard !isTransferring else { return }
        let panel = NSOpenPanel()
        panel.title = "Select positions transfer folder (history is excluded)"
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let folder = panel.url else { return }
        isTransferring = true
        Task { @MainActor in
            defer { isTransferring = false }
            do {
                if bondOnly {
                    let prepared = try await ImportManager().prepareBonds(from: folder)
                    expectedBondIDs = Set(try viewContext.fetch(BondEntity.fetchRequest()).map(\.id))
                    pendingBondImport = prepared; showingBondImportConfirmation = true
                } else {
                    pendingImport = try await ImportManager().prepare(from: folder)
                    showingImportConfirmation = true
                }
            } catch { notifier.alertMessage = "Import failed: \(error.localizedDescription)" }
        }
    }

    private func openTermsReview() {
        guard let container = portfolioContainer else { notifier.alertMessage = "Portfolio store is unavailable."; return }
        reviewModel = BondTermsReview(container: container); showingTermsReview = true
    }
    private func applyPendingBondImport() {
        guard let container = portfolioContainer, let transfer = pendingBondImport else { notifier.alertMessage = "Portfolio store or prepared transfer is unavailable."; return }
        let identities = expectedBondIDs; isTransferring = true
        Task { @MainActor in
            defer { isTransferring = false }
            do {
                try await ImportManager().applyBonds(transfer, into: container, expectedDestinationIDs: identities)
                pendingBondImport = nil
                notifier.alertMessage = "Bonds imported. ETFs and financial history were kept. \(transfer.unresolvedCount) holdings need terms review."
            } catch { notifier.alertMessage = "Bond import failed: \(error.localizedDescription)" }
        }
    }

    private func applyPendingImport() {
        guard let container = portfolioContainer, let payload = pendingImport else {
            notifier.alertMessage = "Portfolio store is unavailable."
            return
        }
        isTransferring = true
        Task { @MainActor in
            defer { isTransferring = false }
            do {
                try await ImportManager().apply(payload, into: container)
                pendingImport = nil
                notifier.alertMessage = "Positions imported. Existing history was kept."
            } catch { notifier.alertMessage = "Import failed: \(error.localizedDescription)" }
        }
    }

    private func recalculateAllCashFlows() {
        guard let container = portfolioContainer else {
            notifier.alertMessage = "Portfolio store is unavailable."
            return
        }
        Task { @MainActor in
            do {
                let excluded = try await PortfolioTransaction.run(in: container) { context in
                    let bonds = try context.fetch(BondEntity.fetchRequest())
                    let generator = CashFlowGenerator(context: context)
                    for bond in bonds { try generator.regenerateCashFlows(for: bond) }
                    return bonds.filter { !BondTermsStore.isReady($0) }.count
                }
                recalculationMessage = BondTermsPresentation.exclusions(excluded) ?? "Approved schedules were recalculated from saved terms."
                showRecalculatedAlert = true
            } catch { notifier.alertMessage = "Recalculation failed: \(error.localizedDescription)" }
        }
    }

    // MARK: – Refresh ETF Prices

    private func refreshETFPrices() {
        Task { @MainActor in
            do { try await priceUpdater.refreshAllPrices() }
            catch { notifier.alertMessage = "Price refresh failed: \(error.localizedDescription)" }
        }
    }
}
