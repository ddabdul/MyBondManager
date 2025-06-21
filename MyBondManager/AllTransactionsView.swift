//  AllTransactionsView.swift
//  MyBondManager
//
//  Created by Olivier on 21/06/2025.
//  Updated to add a close button and filtering.
//

import SwiftUI
import CoreData

@available(macOS 13.0, *)
struct AllTransactionsView: View {
    // 1️⃣ Fetch all CapitalTransaction objects, sorted by date descending
    @FetchRequest(
        sortDescriptors: [
            NSSortDescriptor(keyPath: \CapitalTransaction.date, ascending: false)
        ],
        animation: .default
    )
    private var transactions: FetchedResults<CapitalTransaction>

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss   // to close the sheet

    // 2️⃣ Filter state
    enum TransactionFilter: String, CaseIterable, Identifiable {
        case past  = "Past"
        case future = "Future"
        var id: Self { self }
    }
    @State private var filter: TransactionFilter = .past

    var body: some View {
        VStack(spacing: 0) {
            // Header with Close button
            HStack {
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.headline)
                        .padding(8)
                }
                .buttonStyle(.plain)

                Spacer()

                Text("Transaction History")
                    .font(.title2)
                    .bold()

                Spacer()

                // dummy spacer to balance the close button
                Color.clear.frame(width: 32, height: 32)
            }
            .background(AppTheme.panelBackground)
            .padding(.bottom, 4)

            Divider()

            // 3️⃣ Filter picker
            Picker("Show", selection: $filter) {
                ForEach(TransactionFilter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(SegmentedPickerStyle())
            .padding([.horizontal, .top])

            // 4️⃣ Filtered list
            List(filteredTransactions) { txn in
                HStack {
                    // Date
                    Text(txn.date, format: .dateTime.year().month().day())
                        .frame(width: 100, alignment: .leading)

                    // Type
                    Text(txn.type)
                        .frame(width: 120, alignment: .leading)

                    // Instrument (bond name or ETF name)
                    Text(txn.bond?.name ?? txn.etf?.etfName ?? "—")
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // Amount, colored green/red
                    Text(txn.amount,
                         format: .currency(code:
                             Locale.current.currency?.identifier ?? "EUR"))
                        .frame(width: 100, alignment: .trailing)
                        .foregroundColor(txn.amount >= 0 ? .green : .red)
                }
                .padding(.vertical, 2)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .frame(minWidth: 600, minHeight: 400)
        .padding(.top, 4)
    }

    /// Applies the selected filter to the full fetch
    private var filteredTransactions: [CapitalTransaction] {
        let calendar = Calendar.current
        let startOfToday = calendar.startOfDay(for: Date())

        return transactions.filter { txn in
            let txnDay = calendar.startOfDay(for: txn.date)
            switch filter {
            case .past:
                return txnDay <= startOfToday
            case .future:
                return txnDay >= startOfToday
            }
        }
    }
}

