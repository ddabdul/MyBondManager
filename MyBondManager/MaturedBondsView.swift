//
//  MaturedBondsView.swift
//  MyBondManager
//  Adjusted to CoreData
//  Created by Olivier on 17/04/2025.
//  Updated on 26/04/2025.

//

import SwiftUI
import CoreData

struct MaturedBondsView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss)             private var dismiss

    /// Start of today, so “matured” means < this date
    private static var startOfToday: Date {
        Calendar.current.startOfDay(for: Date())
    }

    // Fetch only bonds that matured *before* today
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

    // Copy-and-paste of your summary logic from BondTableView
    @State private var sortOrder: [KeyPathComparator<BondSummary>] = [
        .init(\.maturityDate, order: .forward)
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
            // ———————————
            // Title Bar
            // ———————————
            HStack {
                Text("Matured Bonds")
                    .font(.largeTitle)
                    .foregroundColor(.white)
                Spacer()
            }
            .padding()
            .background(AppTheme.tileBackground)

            // ———————————
            // Table of Summaries
            // ———————————
            Table(sortedSummaries,
                  selection:  $selectedSummaryID,
                  sortOrder:  $sortOrder
            ) {
                // 1) Issuer
                TableColumn("Issuer", value: \.issuer) { s in
                    Text(s.issuer)
                        .multilineTextAlignment(.leading)
                }
                .width(min: 120, ideal: 160, max: 240)

                // 2) Nominal
                TableColumn("Nominal", value: \.totalNominal) { s in
                    HStack(spacing: 4) {
                        if s.recordCount > 1 {
                            Text("+")
                                .font(.caption)
                                .foregroundColor(.purple)
                        }
                        Text(s.formattedTotalParValue)
                            .multilineTextAlignment(.trailing)
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
                .width(min: 80, ideal: 100)

                // 3) Coupon
                TableColumn("Coupon", value: \.couponRate) { s in
                    Text(s.couponFormatted)
                        .multilineTextAlignment(.trailing)
                }
                .width(min: 60, ideal: 80)

                // 4) Maturity Date
                TableColumn("Maturity Date", value: \.maturityDate) { s in
                    Text(Formatters.shortDate.string(from: s.maturityDate))
                        .multilineTextAlignment(.center)
                }
                .width(min: 80)
            }
            .tableStyle(.inset(alternatesRowBackgrounds: true))

            // ———————————
            // Detail Sheet on Selection
            // ———————————
            .sheet(item: Binding<BondSummary?>(
                get: {
                    guard let id = selectedSummaryID else { return nil }
                    return sortedSummaries.first { $0.id == id }
                },
                set: { new in
                    selectedSummaryID = new?.id
                }
            )) { summary in
                BondSummaryDetailView(summary: summary)
            }

            Divider()

            // ———————————
            // Close Button
            // ———————————
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
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
            .environment(
                \.managedObjectContext,
                PersistenceController.shared.container.viewContext
            )
    }
}

