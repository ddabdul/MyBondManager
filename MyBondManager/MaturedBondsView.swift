//
//  MaturedBondsView.swift
//  MyBondManager
//  Adjusted to CoreData
//  Created by Olivier on 17/04/2025.
//  Updated on 30/04/2025: content-only TableColumns to fix generic overload and avoid layout recursion
//

import SwiftUI
import CoreData

struct MaturedBondsView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss) private var dismiss

    /// “Matured” means maturityDate < start of today
    private static var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \BondEntity.maturityDate, ascending: true)
        ],
        predicate: NSPredicate(format: "maturityDate < %@", Self.startOfToday as NSDate),
        animation: .default
    )
    private var bondEntities: FetchedResults<BondEntity>

    /// Tracks which ISIN has been selected
    @State private var selectedISIN: String?

    /// Build summaries grouped by ISIN
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

    var body: some View {
        VStack(spacing: 0) {
            // Title Bar
            HStack {
                Text("Matured Bonds")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding()
            .background(AppTheme.tileBackground)

            // Table of summaries (unsorted)
            Table(summaries, selection: $selectedISIN) {
                TableColumn("Issuer") { summary in
                    Text(summary.issuer)
                        .multilineTextAlignment(.leading)
                }
                .width(min: 120, ideal: 160, max: 240)

                TableColumn("Nominal") { summary in
                    Text(summary.formattedTotalParValue)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 80, ideal: 100)

                TableColumn("Coupon") { summary in
                    Text(summary.couponFormatted)
                        .multilineTextAlignment(.trailing)
                }
                .width(min: 60, ideal: 80)

                TableColumn("Maturity Date") { summary in
                    Text(Formatters.shortDate.string(from: summary.maturityDate))
                        .multilineTextAlignment(.center)
                }
                .width(min: 80)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))
            // Popover for details
            .popover(item: Binding(
    get: {
        guard let isin = selectedISIN else { return nil }
        return summaries.first { $0.id == isin }
    },
    set: { _, _ in selectedISIN = nil }
), arrowEdge: .top) { (summary: BondSummary) in
                BondSummaryDetailView(summary: summary)
                    .environment(\.managedObjectContext, moc)
                    .frame(minWidth: 400, minHeight: 300)
            }

            Divider()

            // Close Button
            HStack {
                Spacer()
                Button("Close") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Spacer()
            }
            .padding()
        }
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
