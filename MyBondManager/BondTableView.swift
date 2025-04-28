//
//  BondTableView.swift
//  MyBondManager
//
//  Created by Olivier on 19/04/2025.
//  Updated on 27/04/2025.
//  Revised on 27/04/2025 to align with non-optional Core Data properties and fix delete crash
//

import SwiftUI
import CoreData

// —————————————————————————————
// MARK: – BondEntity + Formatters
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

    /// Formatter for the non-optional acquisitionDate
    var acquisitionDateFormatted: String {
        Formatters.shortDate.string(from: acquisitionDate)
    }
}

// —————————————————————————————
// MARK: – BondSummary Model
// —————————————————————————————
struct BondSummary: Identifiable {
    let id: String
    let name: String
    let issuer: String
    let couponRate: Double
    let maturityDate: Date
    let records: [BondEntity]

    var recordCount: Int { records.count }
    var totalNominal: Double { records.reduce(0) { $0 + $1.parValue } }
    var formattedTotalParValue: String {
        Formatters.currency.string(from: NSNumber(value: totalNominal)) ?? "–"
    }
    var couponFormatted: String {
        String(format: "%.2f%%", couponRate)
    }
}

// —————————————————————————————
// MARK: – BondTableView
// —————————————————————————————
struct BondTableView: View {
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

    private var summaries: [BondSummary] {
        Dictionary(grouping: bondEntities, by: \.isin)
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

    private var sortedSummaries: [BondSummary] {
        summaries.sorted(using: sortOrder)
    }

    var body: some View {
        VStack(spacing: 0) {
            titleBar
            bondTable
        }
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
                .font(.largeTitle)
                .foregroundColor(.white)
            Spacer()
        }
        .padding()
        .background(AppTheme.tileBackground)
    }

    private var bondTable: some View {
        Table(sortedSummaries,
              selection:  $selectedSummaryID,
              sortOrder:  $sortOrder
        ) {
            TableColumn("Issuer", value: \BondSummary.issuer) { s in
                Text(s.issuer).multilineTextAlignment(.leading)
            }
            .width(min: 120, ideal: 160, max: 240)

            TableColumn("Nominal", value: \BondSummary.totalNominal) { s in
                HStack(spacing: 4) {
                    if s.recordCount > 1 {
                        Text("+").font(.caption).foregroundColor(.purple)
                    }
                    Text(s.formattedTotalParValue)
                        .multilineTextAlignment(.trailing)
                }
                .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .width(min: 80, ideal: 100)

            TableColumn("Coupon", value: \BondSummary.couponRate) { s in
                Text(s.couponFormatted).multilineTextAlignment(.trailing)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Maturity Date", value: \BondSummary.maturityDate) { s in
                Text(Formatters.shortDate.string(from: s.maturityDate))
                    .multilineTextAlignment(.center)
            }
            .width(min: 80)
        }
        .tableStyle(.inset(alternatesRowBackgrounds: true))
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
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header + Close
                HStack {
                    Text(summary.name)
                        .font(.title2)
                        .bold()
                    Spacer()
                    Button("Close") { dismiss() }
                        .keyboardShortcut(.cancelAction)
                }
                Divider()

                // Summary Info
                VStack(alignment: .leading, spacing: 8) {
                    Text("Issuer: \(summary.issuer)")
                    Text("Coupon: \(summary.couponFormatted)")
                    Text("Maturity: \(Formatters.shortDate.string(from: summary.maturityDate))")
                    Text("Total Nominal: \(summary.formattedTotalParValue)")
                    if summary.recordCount > 1 {
                        Text("(Summarized \(summary.recordCount) records)")
                            .font(.footnote)
                            .foregroundColor(.secondary)
                    }
                }
                Divider()

                // Detailed Records
                Text("Details:")
                    .font(.headline)

                ForEach(summary.records.filter { !$0.isDeleted }, id: \.objectID) { bond in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Nominal: \(bond.parValueFormatted)")
                            Text("Price:   \(bond.acquisitionPriceFormatted)")
                            Text("Date:    \(bond.acquisitionDateFormatted)")
                            Text("Bank:    \(bond.depotBank)")
                            Text("YTM:     \(bond.ytmFormatted)")
                        }
                        Spacer()

                        Button("Edit") {
                            DispatchQueue.main.async {
                                editingBond = bond
                            }
                        }
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
        .frame(minWidth: 400, minHeight: 300)

        .popover(item: $editingBond, arrowEdge: .top) { bond in
            EditBondView(bond: bond)
                .environment(\.managedObjectContext, moc)
                .frame(minWidth: 400, minHeight: 500)
                .onDisappear { editingBond = nil }
        }

        .alert("Delete this record?", isPresented: $showDeleteAlert, presenting: bondToDelete) { bond in
            Button("Delete", role: .destructive) {
                // 1) dismiss immediately
                dismiss()
                // 2) then delete and save
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
        BondTableView()
            .environment(\.managedObjectContext, PersistenceController.shared.container.viewContext)
    }
}
