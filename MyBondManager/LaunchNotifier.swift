//
//  LaunchNotifier.swift
//  MyBondManager
//
//  Created by Olivier on 21/04/2025.
//  Updated on 08/06/2025 to update historical data on events
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

    let id      = UUID()
    let name    : String
    let bank    : String
    let kind    : Kind
    let date    : Date
    let amount  : Double

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
        let now      = Date()
        let defaults = UserDefaults.standard

        // Load when we last launched (or default to one week ago)
        let lastLaunch: Date = {
            if let saved = defaults.object(forKey: "lastLaunchDate") as? Date {
                return saved
            } else {
                return Calendar.current.date(byAdding: .day, value: -7, to: now)!
            }
        }()

        var events: [BondEvent] = []

        // 1) Find matured bonds since last launch
        let matureReq: NSFetchRequest<BondEntity> = BondEntity.fetchRequest()
        matureReq.predicate = NSPredicate(
            format: "maturityDate >= %@ AND maturityDate < %@",
            lastLaunch as NSDate,
            now as NSDate
        )
        if let matured = try? moc.fetch(matureReq) {
            for bond in matured {
                // 1a) record history: bond maturity
                do {
                    try HistoricalDataRecorder.recordBondMaturity(
                        bond: bond,
                        redemptionAmount: bond.parValue,
                        date: bond.maturityDate,
                        context: moc
                    )
                } catch {
                    print("⚠️ Failed to record maturity history for \(bond.name): \(error)")
                }

                // 1b) queue alert event
                let e = BondEvent(
                    name:    bond.name,
                    bank:    bond.depotBank,
                    kind:    .principal,
                    date:    bond.maturityDate,
                    amount:  bond.parValue
                )
                events.append(e)
            }
        }

        // 2) Find coupon payments since last launch
        let allReq: NSFetchRequest<BondEntity> = BondEntity.fetchRequest()
        let allBonds = (try? moc.fetch(allReq)) ?? []
        let cal       = Calendar.current
        let startYear = cal.component(.year, from: lastLaunch)
        let endYear   = cal.component(.year, from: now)

        for bond in allBonds {
            // derive month/day of annual coupon (using maturity date as proxy)
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

                let amt = bond.parValue * bond.couponRate / 100.0

                // 2a) record history: coupon payment
                do {
                    try HistoricalDataRecorder.recordBondInterest(
                        bond: bond,
                        amount: amt,
                        date: couponDate,
                        context: moc
                    )
                } catch {
                    print("⚠️ Failed to record coupon history for \(bond.name): \(error)")
                }

                // 2b) queue alert event
                let e = BondEvent(
                    name:    bond.name,
                    bank:    bond.depotBank,
                    kind:    .coupon,
                    date:    couponDate,
                    amount:  amt
                )
                events.append(e)
            }
        }

        // 3) If any events, build the alert message
        if !events.isEmpty {
            events.sort { $0.date < $1.date }

            var messageLines: [String] = ["Since your last visit:"]
            var lastIssuerBank: (String, String)? = nil
            var firstForIssuer = true

            for event in events {
                let issuerBank    = (event.name, event.bank)
                let dateStr       = Formatters.mediumDate.string(from: event.date)
                let amountStr     = Formatters.currency.string(from: NSNumber(value: event.amount)) ?? "\(event.amount)"

                if let last = lastIssuerBank, last == issuerBank {
                    if firstForIssuer {
                        messageLines.append("- \(dateStr),")
                    }
                    messageLines.append("- \(event.kind.rawValue): \(amountStr)")
                    firstForIssuer = false
                } else {
                    if !messageLines.isEmpty && !(messageLines.last?.starts(with: "Since") ?? false) {
                        messageLines.append("")
                    }
                    messageLines.append("\(event.name) at \(event.bank):")
                    messageLines.append("- \(dateStr),")
                    messageLines.append("- \(event.kind.rawValue): \(amountStr)")
                    lastIssuerBank   = issuerBank
                    firstForIssuer   = false
                }
            }

            alertMessage = messageLines.joined(separator: "\n")
        }

        // 4) Save this launch time for next run
        defaults.set(now, forKey: "lastLaunchDate")
    }
}

