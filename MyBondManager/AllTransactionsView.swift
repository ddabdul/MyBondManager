//
// AllTransactionsview;swift




import SwiftUI
import CoreData

@available(macOS 13.0, *)
struct AllTransactionsView: View {
    // your fetch
    @FetchRequest(
      sortDescriptors: [NSSortDescriptor(keyPath: \CapitalTransaction.date, ascending: false)],
      animation: .default
    )
    private var transactions: FetchedResults<CapitalTransaction>

    @Environment(\.managedObjectContext) private var viewContext
    @Environment(\.dismiss) private var dismiss

    enum TransactionFilter: String, CaseIterable, Identifiable {
        case past = "Past", future = "Future"
        var id: Self { self }
    }
    @State private var filter: TransactionFilter = .past
    @State private var selectedTransactions = Set<CapitalTransaction>()

    var body: some View {
        VStack(spacing: 0) {
            // MARK: – In‐sheet title bar
            HStack {
                Button { dismiss() } label: {
                    Image(systemName: "xmark")
                }
                .buttonStyle(.plain)
                .padding(.leading, 8)

                Spacer()

                Text("All Transactions")
                    .font(.title2).bold()


                Spacer()

                HStack(spacing: 12) {
                    Button(role: .destructive) {
                        deleteSelected()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .disabled(selectedTransactions.isEmpty)
                }
                .padding(.trailing, 8)
            }
            .frame(height: 36)
            .background(AppTheme.tileBackground)
            
            Divider()

            // MARK: – Filter picker
            Picker("Show", selection: $filter) {
                ForEach(TransactionFilter.allCases) { f in
                    Text(f.rawValue).tag(f)
                }
            }
            .pickerStyle(.segmented)
            .padding([.horizontal, .top])

            // MARK: – Transactions list with flexible columns
            List(selection: $selectedTransactions) {
                ForEach(filteredTransactions, id: \.objectID) { txn in
                    HStack(spacing: 16) {
                        // Date (fixed width)
                        Text(txn.date, format: .dateTime.year().month().day())
                            .frame(width: 100, alignment: .leading)

                        // Type (fixed width)
                        Text(txn.type)
                            .frame(width: 120, alignment: .leading)

                        // Bank (fixed width)
                        Text(
                            txn.bond?.depotBank
                            ?? (txn.etf != nil ? "TradeRepublic" : "—")
                        )
                        .frame(width: 120, alignment: .leading)

                        // Instrument (flexible)
                        Text(txn.bond?.name ?? txn.etf?.etfName ?? "—")
                            // this column will take any extra space
                            .frame(minWidth: 180,
                                   maxWidth: .infinity,
                                   alignment: .leading)

                        // Amount (fixed width)
                        Text(txn.amount,
                             format: .currency(code:
                                Locale.current.currency?.identifier ?? "EUR"))
                            .frame(width: 100, alignment: .trailing)
                            .foregroundColor(txn.amount >= 0 ? .green : .red)
                    }
                    .padding(.vertical, 2)
                    .tag(txn as CapitalTransaction)
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            // let the list fill and respond to window resizes
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        // make the sheet/window resizable with a big minimum
        .frame(minWidth: 900, minHeight: 600)
    }

    private var filteredTransactions: [CapitalTransaction] {
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        return transactions.filter { txn in
            let day = cal.startOfDay(for: txn.date)
            return filter == .past ? (day <= today) : (day >= today)
        }
    }

    private func deleteSelected() {
        withAnimation {
            for txn in selectedTransactions {
                viewContext.delete(txn)
            }
            do {
                try viewContext.save()
                selectedTransactions.removeAll()
            } catch {
                print("❗️ Failed to delete:", error)
            }
        }
    }
}
