//
//  HistoricalSnapshotService.swift
//  MyBondManager
//
//  Created by Olivier on 08/06/2025.
//


//
//  HistoricalSnapshotService.swift
//  MyBondManager
//
//  Created by Olivier on 08/06/2025.
//

import Foundation
import CoreData

final class HistoricalSnapshotService {

    static func snapshotCurrentPortfolio(context: NSManagedObjectContext) throws {
        let date = Date()
        var newSnapshots: [HistoricalValuation] = []

        // === Step 1: Aggregate Bond Holdings by Depot ===
        let bondRequest: NSFetchRequest<BondEntity> = BondEntity.fetchRequest()
        let bonds = try context.fetch(bondRequest)

        let bondsByDepot = Dictionary(grouping: bonds, by: \.depotBank)

        for (depotBank, bonds) in bondsByDepot {
            var investedCapital: Double = 0
            let interestReceived: Double = 0
            let capitalGains: Double = 0

            for bond in bonds {
                investedCapital += bond.parValue
            }

            let snapshot = HistoricalValuation(context: context)
            snapshot.id = UUID()
            snapshot.date = date
            snapshot.assetType = "Bond"
            snapshot.depotBank = depotBank
            snapshot.investedCapital = NSDecimalNumber(value: investedCapital)
            snapshot.interestReceived = NSDecimalNumber(value: interestReceived)
            snapshot.capitalGains = NSDecimalNumber(value: capitalGains)

            newSnapshots.append(snapshot)
        }

        // === Step 2: Aggregate ETF Holdings ===
        let etfRequest: NSFetchRequest<ETFHoldings> = ETFHoldings.fetchRequest()
        let etfHoldings = try context.fetch(etfRequest)

        if !etfHoldings.isEmpty {
            let totalInvested = etfHoldings.reduce(0.0) { $0 + $1.cost }
            let totalProfit = etfHoldings.reduce(0.0) { $0 + $1.profit }

            let etfValuation = HistoricalValuation(context: context)
            etfValuation.id = UUID()
            etfValuation.date = date
            etfValuation.assetType = "ETF"
            etfValuation.depotBank = nil
            etfValuation.investedCapital = NSDecimalNumber(value: totalInvested)
            etfValuation.interestReceived = nil
            etfValuation.capitalGains = NSDecimalNumber(value: totalProfit)

            newSnapshots.append(etfValuation)
        }

        // === Step 3: Save and Print ===
        try context.save()

        print("📈 Historical Snapshots Created:")
        for snapshot in newSnapshots {
            print("""
            • Date: \(snapshot.date)
              Type: \(snapshot.assetType)
              Depot: \(snapshot.depotBank ?? "-")
              Capital Invested: €\(snapshot.investedCapital)
              Interest: €\(snapshot.interestReceived?.stringValue ?? "—")
              Gain: €\(snapshot.capitalGains)
            """)
        }
    }
}
