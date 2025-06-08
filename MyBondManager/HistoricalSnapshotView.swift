//
//  HistoricalSnapshotView.swift
//  MyBondManager
//
//  Created by Olivier on 08/06/2025.
//  Updated on 08/06/2025.
//

import SwiftUI
import CoreData

@available(macOS 13.0, *)
struct HistoricalSnapshotView: View {
    // MARK: – Environment
    @Environment(\.managedObjectContext) private var viewContext

    // MARK: – Passed State
    let geo: GeometryProxy
    @Binding var selectedDepotBank: String

    // 1. Fetch all snapshots, newest first
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \HistoricalValuation.date, ascending: false),
            NSSortDescriptor(keyPath: \HistoricalValuation.assetType, ascending: true)
        ],
        animation: .default
    )
    private var allSnapshots: FetchedResults<HistoricalValuation>

    var body: some View {
        // 2. Filter by depot bank
        let filtered = allSnapshots.filter { snap in
            selectedDepotBank == "All" ||
                (snap.depotBank ?? "") == selectedDepotBank
        }

        // 3. Group by date (just the day portion)
        let grouped = Dictionary(
            grouping: filtered,
            by: { Calendar.current.startOfDay(for: $0.date) }
        )
        // Sort the groups by date descending
        let sortedDates = grouped.keys.sorted(by: >)

        VStack(alignment: .leading, spacing: 12) {
            Text("All Historical Snapshots")
                .font(.headline)
                .padding(.bottom, 4)

            List {
                ForEach(sortedDates, id: \.self) { day in
                    Section(header: Text(sectionDateFormatter.string(from: day))) {
                        ForEach(grouped[day] ?? [], id: \.id) { snap in
                            HStack {
                                Text(snap.assetType)
                                    .frame(width: 60, alignment: .leading)
                                Text(snap.depotBank ?? "—")
                                    .frame(width: 80, alignment: .leading)
                                Spacer()
                                Text("Invested: €\(snap.investedCapital.stringValue)")
                                Text("Interest: €\(snap.interestReceived?.stringValue ?? "0")")
                                Text("Gains: €\(snap.capitalGains.stringValue)")
                            }
                            .font(.system(.body, design: .monospaced))
                        }
                    }
                }
            }
            .listStyle(SidebarListStyle())
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .padding()
    }

    // Shows just the date (no time)
    private var sectionDateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .none
        return df
    }
}
