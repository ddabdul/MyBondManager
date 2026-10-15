//  MaturedBondsView.swift
//  MyBondManager
//  Updated 06/05/2025 to use panelBackground and explicit column closures

import SwiftUI
import CoreData

struct MaturedBondsView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.portfolioContainer) private var portfolioContainer
    @Environment(\.dismiss) private var dismiss

    /// Bonds with maturityDate before the start of today
    private static var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \BondEntity.maturityDate, ascending: true)
        ],
        animation: .default
    )
    private var bondEntities: FetchedResults<BondEntity>

    /// Summaries grouped by ISIN
    private var summaries: [BondSummary] {
        Dictionary(grouping: bondEntities.filter { !BondEligibility.isActive($0, on: MarketDay(date: Date())) }, by: \.isin)
            .map { isin, entities in
                let first = entities[0]
                return BondSummary(
                    id:           isin,
                    name:         first.name,
                    issuer:       first.issuer,
                    couponRate:   first.couponRate,
                    maturityDate: first.maturityDate,
                    records:      entities
                )
            }
    }

    @State private var summaryToDelete: BondSummary?
    @State private var isDeleting = false
    @State private var deletionError: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Matured Bonds")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding()
            .background(AppTheme.tileBackground)

            if let deletionError { Text(deletionError).foregroundColor(.red).padding() }
            // Table of summaries with inline delete
            Table(summaries) {
                TableColumn("Issuer") { (summary: BondSummary) in
                    Text(summary.issuer)
                        .multilineTextAlignment(.leading)
                }
                .width(min: 120, ideal: 160, max: 240)

                TableColumn("Nominal") { (summary: BondSummary) in
                    Text(summary.formattedTotalNominal)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Coupon") { (summary: BondSummary) in
                    Text(summary.couponFormatted)
                        .multilineTextAlignment(.trailing)
                }
                .width(min: 60, ideal: 80)

                TableColumn("Maturity Date") { (summary: BondSummary) in
                    Text(Formatters.shortDate.string(from: summary.maturityDate))
                        .multilineTextAlignment(.center)
                }
                .width(min: 80)

                TableColumn("Actions") { (summary: BondSummary) in
                    Button(role: .destructive) {
                        summaryToDelete = summary
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(BorderlessButtonStyle())
                }
                .width(min: 60)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            .scrollContentBackground(.hidden)
            .background(AppTheme.panelBackground)
            .alert(item: $summaryToDelete) { summary in
                Alert(
                    title: Text("Delete all entries for \(summary.issuer)?"),
                    message: Text(
                        "This will permanently remove all \(summary.recordCount) bond records " +
                        "maturing on \(Formatters.shortDate.string(from: summary.maturityDate))."
                    ),
                    primaryButton: .destructive(Text("Delete")) {
                        deleteSummary(summary)
                    },
                    secondaryButton: .cancel()
                )
            }

            Divider()

            // Close button
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding()
        }
        .disabled(isDeleting)
        .background(AppTheme.panelBackground)
        .frame(minWidth: 700, minHeight: 400)
    }

    private func deleteSummary(_ summary: BondSummary) {
        guard !isDeleting else { return }
        guard let container = portfolioContainer else {
            deletionError = "Portfolio store is unavailable."
            return
        }
        let ids = summary.records.map(\.objectID)
        isDeleting = true; deletionError = nil
        Task { @MainActor in
            defer { isDeleting = false }
            do {
                try await PortfolioTransaction.run(in: container) { try BondDeletion.stage(ids: ids, context: $0) }
            } catch { deletionError = "Could not delete matured bonds: \(error.localizedDescription)" }
        }
    }
}

struct MaturedBondsView_Previews: PreviewProvider {
    static var previews: some View {
        MaturedBondsView()
            .environment(\.managedObjectContext,
                         PersistenceController.shared.container.viewContext)
    }
}
