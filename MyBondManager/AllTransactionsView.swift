//
//  AllTransactionsView.swift
//  MyBondManager
//
//  Created by Olivier on 21/06/2025.
//


//  AllTransactionsView.swift
//  MyBondManager
//  
//  A SwiftUI view for browsing all capital transactions.

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

    var body: some View {
        VStack {
            Text("Transaction History")
                .font(.title2)
                .padding(.top)

            // 2️⃣ Table/List of transactions
            List {
                ForEach(transactions) { txn in
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
                        Text(txn.amount, format: .currency(code: Locale.current.currency?.identifier ?? "USD"))
                            .frame(width: 100, alignment: .trailing)
                            .foregroundColor(txn.amount >= 0 ? .green : .red)
                    }
                    .padding(.vertical, 2)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
        }
        .padding()
    }
}

