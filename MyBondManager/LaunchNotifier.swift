//
//  LaunchNotifier.swift
//  MyBondManager
//
//  Created by Olivier on 21/04/2025.
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
    let bond    : BondEntity
    let kind    : Kind
    let date    : Date
    let amount  : Double

    var description: String {
        let name    = bond.name
        let bank    = bond.depotBank
        let dateStr = Formatters.mediumDate.string(from: date)
        let amtStr  = Formatters.currency.string(from: NSNumber(value: amount)) ?? "\(amount)"
        return "\(name) – \(kind.rawValue) of \(amtStr) on \(dateStr) (\(bank))"
    }
}

final class LaunchNotifier: ObservableObject {
    @Published var alertMessage: String?

    init(context moc: NSManagedObjectContext) {
        let now = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let defaults = UserDefaults.standard

        // Determine lastLaunch
        let lastLaunch: Date = {
            if let saved = defaults.object(forKey: "lastLaunchDate") as? Date {
                return saved
            } else {
                return Calendar.current.date(byAdding: .day, value: -7, to: now)!
            }
        }()

        // 0️⃣ Create the recorder
        let recorder = CapitalTransactionRecorder(context: moc)

        var events: [BondEvent] = []

        // 1️⃣ Fetch matured bonds and record principal payout
        let matureReq = NSFetchRequest<BondEntity>(entityName: "BondEntity")
        matureReq.predicate = NSPredicate(
            format: "maturityDate >= %@ AND maturityDate < %@",
            lastLaunch as NSDate,
            now as NSDate
        )
        if let matured = try? moc.fetch(matureReq) {
            for bond in matured {
                let date   = bond.maturityDate
                let amount = bond.parValue

                // — Record only the maturity transaction
                recorder.recordBondRedemption(
                    bond,
                    redeemedValue: amount,
                    at: date
                )

                // — Still enqueue for alert
                events.append(
                    BondEvent(
                        bond: bond,
                        kind: .principal,
                        date: date,
                        amount: amount
                    )
                )
            }
        }

        // 2️⃣ Fetch all bonds for coupon anniversaries (no recording, just alerts)
        let allReq = NSFetchRequest<BondEntity>(entityName: "BondEntity")
        let allBonds = (try? moc.fetch(allReq)) ?? []
        let cal       = Calendar.current
        let startYear = cal.component(.year, from: lastLaunch)
        let endYear   = cal.component(.year, from: now)

        for bond in allBonds {
            let mdComp = cal.dateComponents([.month, .day], from: bond.maturityDate)
            for year in startYear...endYear {
                let dc = DateComponents(year: year,
                                        month: mdComp.month,
                                        day: mdComp.day)
                guard
                    let couponDate = cal.date(from: dc),
                    couponDate > lastLaunch,
                    couponDate <= now,
                    couponDate <= bond.maturityDate
                else { continue }

                let couponAmt = bond.parValue * bond.couponRate / 100

                // — Only enqueue coupon for alert; no recorder call
                events.append(
                    BondEvent(
                        bond: bond,
                        kind: .coupon,
                        date: couponDate,
                        amount: couponAmt
                    )
                )
            }
        }

        // 3️⃣ Save only the maturity transactions
        do {
            try recorder.save()
        } catch {
            print("⚠️ Failed saving maturity transactions: \(error)")
        }

        // 4️⃣ Build and publish alertMessage if there were any events
        if !events.isEmpty {
            // 1. Sort chronologically
            events.sort { $0.date < $1.date }

            // 2. Prepare lines, and a spot to remember last seen issuer+bank
            var messageLines: [String] = ["Since your last visit:"]
            var lastBondBank: (String, String)? = nil

            // 3. Iterate and group
            for event in events {
                let name       = event.bond.name
                let bank       = event.bond.depotBank
                let issuerBank = (name, bank)

                let dateStr = Formatters.mediumDate.string(from: event.date)
                let amtStr  = Formatters.currency
                                  .string(from: NSNumber(value: event.amount))
                            ?? "\(event.amount)"

                if let last = lastBondBank, last == issuerBank {
                    // Same issuer+bank as previous: just append the kind+amount
                    messageLines.append("- \(event.kind.rawValue): \(amtStr)")
                } else {
                    // New issuer+bank: insert a blank line (if not the very first),
                    // then header + date + kind
                    if messageLines.count > 1 {
                        messageLines.append("")
                    }
                    messageLines.append("\(name) at \(bank):")
                    messageLines.append("- \(dateStr),")
                    messageLines.append("- \(event.kind.rawValue): \(amtStr)")

                    lastBondBank = issuerBank
                }
            }

            // 4. Join into one string
            alertMessage = messageLines.joined(separator: "\n")
        }

        // 5️⃣ Update lastLaunchDate
        defaults.set(now, forKey: "lastLaunchDate")
    }
}

