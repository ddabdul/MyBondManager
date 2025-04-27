//
//  LaunchNotifier.swift
//  MyBondManager
//
//  Created by Olivier on 27/04/2025.
//


import Foundation
import CoreData
import SwiftUI

/// A single event: either a principal (maturity) payout or a coupon payment.
private struct BondEvent: Identifiable {
    enum Kind: String {
        case principal = "Matured"
        case coupon    = "Coupon"
    }

    let id        = UUID()
    let name      : String
    let bank      : String
    let kind      : Kind
    let date      : Date
    let amount    : Double

    /// Format as e.g. “Bond ABC – Coupon of $123.45 on 12/12/2024 (BankName)”
    var description: String {
        let dateStr = Formatters.mediumDate.string(from: date)
        let amtStr  = Formatters.currency.string(from: NSNumber(value: amount)) ?? "\(amount)"
        return "\(name) – \(kind.rawValue) of \(amtStr) on \(dateStr) (\(bank))"
    }
}

final class LaunchNotifier: ObservableObject {
    @Published var alertMessage: String?

    init(context moc: NSManagedObjectContext) {
        let now        = Date()
        let defaults   = UserDefaults.standard
        let lastLaunch = defaults.object(forKey: "lastLaunchDate") as? Date ?? .distantPast

        var events: [BondEvent] = []

        // 1) Find matured bonds
        let matureReq = NSFetchRequest<BondEntity>(entityName: "BondEntity")
        matureReq.predicate = NSPredicate(
            format: "maturityDate >= %@ AND maturityDate < %@",
            lastLaunch as NSDate,
            now as NSDate
        )
        if let matured = try? moc.fetch(matureReq) {
            for bond in matured {
                let e = BondEvent(
                    name:   bond.name,
                    bank:   bond.depotBank,
                    kind:   .principal,
                    date:   bond.maturityDate,
                    amount: bond.parValue
                )
                events.append(e)
            }
        }

        // 2) Find coupon anniversaries
        let allReq = NSFetchRequest<BondEntity>(entityName: "BondEntity")
        let allBonds = (try? moc.fetch(allReq)) ?? []
        let cal   = Calendar.current
        let startYear = cal.component(.year, from: lastLaunch)
        let endYear   = cal.component(.year, from: now)

        for bond in allBonds {
            let mdComp = cal.dateComponents([.month, .day], from: bond.maturityDate)
            for year in startYear...endYear {
                var dc = DateComponents()
                dc.year  = year
                dc.month = mdComp.month
                dc.day   = mdComp.day
                guard
                    let couponDate = cal.date(from: dc),
                    couponDate > lastLaunch,
                    couponDate <= now,
                    couponDate <= bond.maturityDate
                else { continue }

                let amt = bond.parValue * bond.couponRate / 100
                let e = BondEvent(
                    name:   bond.name,
                    bank:   bond.depotBank,
                    kind:   .coupon,
                    date:   couponDate,
                    amount: amt
                )
                events.append(e)
            }
        }

        // 3) If any events, sort by date and build alert text
        if !events.isEmpty {
            events.sort { $0.date < $1.date }
            let lines = events.map { "- \($0.description)" }
            alertMessage = "Since your last visit:\n" + lines.joined(separator: "\n")
        }

        // 4) Save new last‐launch timestamp
        defaults.set(now, forKey: "lastLaunchDate")
    }
}
