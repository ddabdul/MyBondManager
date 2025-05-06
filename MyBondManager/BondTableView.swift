//
//  BondTableView.swift
//  MyBondManager
//
//  Updated 05/05/2025 to use panelBackground throughout
//

import SwiftUI
import CoreData

// —————————————————————————————
// MARK: – BondEntity + Formatters + Expected Profit
// —————————————————————————————
extension BondEntity {
    var acquisitionPriceFormatted: String {
        Formatters.currency.string(from: NSNumber(value: initialPrice)) ?? "–"
    }

    var parValueFormatted: String {
        Formatters.currency.string(from: NSNumber(value: parValue)) ?? "–"
    }

    var couponFormatted: String {
        String(format: "%.2f%%", couponRate)
    }

    var ytmFormatted: String {
        String(format: "%.2f%%", yieldToMaturity)
    }

    var acquisitionDateFormatted: String {
        Formatters.shortDate.string(from: acquisitionDate)
    }

    /// Grab the bond’s “expectedProfit” cash-flow event, if any
    var expectedProfit: Double {
        let flows = cashFlows ?? []
        return flows
            .first(where: { $0.natureEnum == .expectedProfit })?
            .amount ?? 0
    }

    var expectedProfitFormatted: String {
        Formatters.currency.string(from: NSNumber(value: expectedProfit)) ?? "–"
    }
}

// —————————————————————————————
// MARK: – BondSummary Model (with Expected Profit)
// —————————————————————————————
struct BondSummary: Identifiable {
    let id: String
    let name: String
    let issuer: String
    let couponRate: Double
    let maturityDate: Date
    let records: [BondEntity]

    var recordCount: Int { records.count }

    var totalNominal: Double {
        records.reduce(0) { $0 + $1.parValue }
    }
    var formattedTotalNominal: String {
        Formatters.currency.string(from: NSNumber(value: totalNominal)) ?? "–"
    }

    var couponFormatted: String {
        String(format: "%.2f%%", couponRate)
    }

    var expectedProfit: Double {
        records.reduce(0) { $0 + $1.expectedProfit }
    }
    var expectedProfitFormatted: String {
        Formatters.currency.string(from: NSNumber(value: expectedProfit)) ?? "–"
    }
}

// —————————————————————————————
// MARK: – BondTableView
// —————————————————————————————
struct BondTableView: View {
    @Binding var selectedDepotBank: String
    @Environment(\.managedObjectContext) private var moc

    static private var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \BondEntity.maturityDate, ascending: true)],
        predicate: NSPredicate(format: "maturityDate >= %@", Self.startOfToday as NSDate),
        animation: .default
    )
    private var bondEntities: FetchedResults<BondEntity>

    @State private var sortOrder: [KeyPathComparator<BondSummary>] = [
        .init(\BondSummary.maturityDate, order: .forward)
    ]
    @State private var selectedSummaryID: String?

    // Filter bondEntities by the selected depot bank
    private var filteredEntities: [BondEntity] {
        guard selectedDepotBank != "All" else {
            return Array(bondEntities)
        }
        return bondEntities.filter { $0.depotBank == selectedDepotBank }
    }

    private var summaries: [BondSummary] {
        Dictionary(grouping: filteredEntities, by: \.isin).map { isin, ents in
            let first = ents[0]
            return BondSummary(
                id:           isin,
                name:         first.name,
                issuer:       first.issuer,
                couponRate:   first.couponRate,
                maturityDate: first.maturityDate,
                records:      ents
            )
        }
    }

    private var sortedSummaries: [BondSummary] {
        summaries.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            bondTable
        }
        .background(AppTheme.panelBackground)
        .frame(minWidth: 800, minHeight: 400)
        .sheet(item: Binding<BondSummary?>(
            get: { sortedSummaries.first { $0.id == selectedSummaryID } },
            set: { selectedSummaryID = $0?.id }
        )) { summary in
            BondSummaryDetailView(summary: summary)
                .environment(\.managedObjectContext, moc)
        }
    }

    private var titleBar: some View {
        HStack {
            Text("My Bond Portfolio")
                .font(.system(.largeTitle, design: .rounded))
                .foregroundColor(.white)
            Spacer()
        }
        .padding()
        .background(AppTheme.tileBackground)
    }

    private var bondTable: some View {
        Table(
            sortedSummaries,
            selection: $selectedSummaryID,
            sortOrder: $sortOrder
        ) {
            TableColumn("Issuer", value: \.issuer) { s in
                Text(s.issuer)
                    .multilineTextAlignment(.leading)
            }
            .width(min: 120, ideal: 160, max: 240)

            TableColumn("Nominal", value: \.totalNominal) { s in
                HStack(spacing: 4) {
                    if s.recordCount > 1 {
                        Text("+")
                            .font(.caption)
                            .foregroundColor(.purple)
                    }
                    Text(s.formattedTotalNominal)
                        .multilineTextAlignment(.trailing)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Exp Profit", value: \BondSummary.expectedProfit) { s in
                Text(s.expectedProfitFormatted)
                    .multilineTextAlignment(.trailing)
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Coupon", value: \.couponRate) { s in
                Text(s.couponFormatted)
                    .multilineTextAlignment(.trailing)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Maturity Date", value: \.maturityDate) { s in
                Text(Formatters.shortDate.string(from: s.maturityDate))
                    .multilineTextAlignment(.center)
            }
            .width(min: 80)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
        .scrollContentBackground(.hidden)
        .background(AppTheme.panelBackground)
    }
}

// —————————————————————————————
// MARK: – Detail View for Summarized Bond
// —————————————————————————————
struct BondSummaryDetailView: View {
    let summary: BondSummary
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss) private var dismiss

    @State private var editingBond: BondEntity?
    @State private var showDeleteAlert = false
    @State private var bondToDelete: BondEntity?

    var body: some View {
        VStack(spacing: 0) {
            // Title Bar
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title3)
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)

                Text(summary.name)
                    .font(.headline)
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer()
                    .frame(width: 30)
            }
            .padding()
            .background(Color(.windowBackgroundColor))

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Divider()

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Issuer: \(summary.issuer)")
                        Text("Coupon: \(summary.couponFormatted)")
                        Text("Maturity: \(Formatters.shortDate.string(from: summary.maturityDate))")
                        Text("Total Nominal: \(summary.formattedTotalNominal)")
                        Text("Expected Profit: \(summary.expectedProfitFormatted)")
                            .fontWeight(.semibold)
                        if summary.recordCount > 1 {
                            Text("(Summarized \(summary.recordCount) records)")
                                .font(.footnote)
                                .foregroundColor(.secondary)
                        }
                    }

                    Divider()

                    Text("Details:")
                        .font(.headline)

                    ForEach(summary.records.filter { !$0.isDeleted }, id: \.objectID) { bond in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Nominal: \(bond.parValueFormatted)")
                                Text("Price:   \(bond.acquisitionPriceFormatted)")
                                Text("Acquisition: \(bond.acquisitionDateFormatted)")
                                Text("Bank: \(bond.depotBank)")
                                Text("YTM: \(bond.ytmFormatted)")
                            }
                            Spacer()
                            Button("Edit") { editingBond = bond }
                                .buttonStyle(BorderlessButtonStyle())
                            Button(role: .destructive) {
                                bondToDelete = bond
                                showDeleteAlert = true
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(BorderlessButtonStyle())
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }

                    Spacer()
                }
                .padding()
            }
        }
        .frame(minWidth: 400, minHeight: 300)
        .popover(item: $editingBond, arrowEdge: .top) { bond in
            EditBondView(bond: bond)
                .environment(\.managedObjectContext, moc)
                .frame(minWidth: 400, minHeight: 500)
                .onDisappear { editingBond = nil }
        }
        .alert("Delete this record?", isPresented: $showDeleteAlert, presenting: bondToDelete) { bond in
            Button("Delete", role: .destructive) {
                dismiss()
                DispatchQueue.main.async {
                    moc.delete(bond)
                    try? moc.save()
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: { bond in
            Text("This will permanently remove the bond acquired on \(Formatters.shortDate.string(from: bond.acquisitionDate)).")
        }
    }
}

// —————————————————————————————
// MARK: – Preview
// —————————————————————————————
struct BondTableView_Previews: PreviewProvider {
    static var previews: some View {
        BondTableView(selectedDepotBank: .constant("All"))
            .environment(\.managedObjectContext,
                         PersistenceController.shared.container.viewContext)
    }
}
