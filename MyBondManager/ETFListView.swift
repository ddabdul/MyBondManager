//
//  ETFListView.swift
//  MyBondManager
//
//  Created by Olivier on 30/04/2025.
//


import SwiftUI
import CoreData

@available(macOS 13.0, *)
struct ETFListView: View {
    @Environment(\.managedObjectContext) private var viewContext
    @FetchRequest(
        sortDescriptors: [NSSortDescriptor(keyPath: \ETFEntity.etfName, ascending: true)],
        animation: .default)
    private var etfs: FetchedResults<ETFEntity>
    
    var body: some View {
        Table(etfs) {
            // 1) ETF Name
            TableColumn("ETF Name", value: \.etfName)
            
            // 2) Number of Holdings
            TableColumn("Holdings") { etf in
                Text("\(etf.numberOfHoldings)")
            }
            
            // 3) Total Shares
            TableColumn("Total Shares") { etf in
                Text("\(etf.totalShares)")
            }
            
            // 4) Last Price
            TableColumn("Last Price") { etf in
                // you can hook up NumberFormatter or use `.format(...)` if you like
                Text(String(format: "%.2f", etf.lastPrice))
            }
            
            // 5) Total Value = lastPrice * totalShares
            TableColumn("Total Value") { etf in
                Text(String(format: "%.2f", etf.totalValue))
            }
        }
        .frame(minWidth: 700, minHeight: 400)
    }
}

// MARK: – Convenience computed properties on ETFEntity

extension ETFEntity {
    /// Turn the NSSet into a Swift Set
    private var holdingsSet: Set<ETFHoldings> {
        (etftoholding as? Set<ETFHoldings>) ?? []
    }

    /// How many distinct holdings (by acquisition date) this ETF has
    var numberOfHoldings: Int {
        holdingsSet.count
    }
    
    /// Sum of shares across all holdings
    var totalShares: Int {
        holdingsSet.reduce(0) { $0 + Int($1.numberOfShares) }
    }
    
    /// Market value of all shares at the lastPrice
    var totalValue: Double {
        lastPrice * Double(totalShares)
    }
}
