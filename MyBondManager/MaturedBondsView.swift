//  MaturedBondsView.swift
//  MyBondManager
//  Updated 06/05/2025 to use panelBackground and explicit column closures

import SwiftUI
import CoreData

struct MaturedBondsView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss) private var dismiss

    /// Bonds with maturityDate before the start of today
    private static var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \BondEntity.maturityDate, ascending: true)
        ],
        predicate: NSPredicate(
            format: "maturityDate < %@",
            Self.startOfToday as NSDate
        ),
        animation: .default
    )
    private var bondEntities: FetchedResults<BondEntity>

    /// Summaries grouped by ISIN
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

    @State private var summaryToDelete: BondSummary?

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
                        summary.records.forEach { bond in
                            moc.delete(bond)
                        }
                        try? moc.save()
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
        .background(AppTheme.panelBackground)
        .frame(minWidth: 700, minHeight: 400)
    }
}

struct MaturedBondsView_Previews: PreviewProvider {
    static var previews: some View {
        MaturedBondsView()
            .environment(\.managedObjectContext,
                         PersistenceController.shared.container.viewContext)
    }
}
