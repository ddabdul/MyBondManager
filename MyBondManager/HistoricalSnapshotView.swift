//
//  HistoricalSnapshotView.swift
//  MyBondManager
//
//  Created by Olivier on 08/06/2025.
//


import SwiftUI
import CoreData

struct HistoricalSnapshotView: View {
    @Environment(\.managedObjectContext) private var viewContext

    // 1. Fetch all snapshots, newest first
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \HistoricalValuation.date, ascending: false)],
        animation: .default)
    private var allSnapshots: FetchedResults<HistoricalValuation>

    var body: some View {
        // 2. Determine the “latest” snapshot date
        let latestDate = allSnapshots.first?.date

        // 3. Filter only entries matching that date
        let latestSnapshots = allSnapshots.filter { $0.date == latestDate }

        VStack(alignment: .leading, spacing: 12) {
            if let date = latestDate {
                Text("Snapshot at \(dateFormatter.string(from: date))")
                    .font(.headline)
            } else {
                Text("No snapshots yet")
                    .font(.headline)
            }

            // 4. Display numeric values in a simple list
            List(latestSnapshots, id: \.id) { snap in
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
            .listStyle(PlainListStyle())
        }
        .padding()
    }

    // Reusable DateFormatter
    private var dateFormatter: DateFormatter {
        let df = DateFormatter()
        df.dateStyle = .medium
        df.timeStyle = .short
        return df
    }
}
