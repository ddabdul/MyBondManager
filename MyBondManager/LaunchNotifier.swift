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
        case coupon      = "Coupon"
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
        let now         = Date()
        let defaults    = UserDefaults.standard

        // If we have no saved value, assume one week ago
        let lastLaunch: Date
        if let saved = defaults.object(forKey: "lastLaunchDate") as? Date {
            lastLaunch = saved
        } else {
           lastLaunch = Calendar.current.date(
                byAdding: .day,
                value: -7,
                to: now
            )!
        }

        print("Last launch date: \(lastLaunch)") // Added print statement
        
       // Force lastLaunchDate to a specific past date for testing
       // let testDateComponents = DateComponents(year: 2025, month: 4, day: 20) // Example: April 20, 2025
       // let forcedLastLaunch = Calendar.current.date(from: testDateComponents)!
      //  let lastLaunch: Date = forcedLastLaunch

      //  print("Forced last launch date (for testing): \(lastLaunch)") // Added print statement
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
                    name:     bond.name,
                    bank:     bond.depotBank,
                    kind:     .principal,
                    date:     bond.maturityDate,
                    amount:   bond.parValue
                )
                events.append(e)
            }
        }

        // 2) Find coupon anniversaries
        let allReq = NSFetchRequest<BondEntity>(entityName: "BondEntity")
        let allBonds = (try? moc.fetch(allReq)) ?? []
        let cal     = Calendar.current
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
                    name:     bond.name,
                    bank:     bond.depotBank,
                    kind:     .coupon,
                    date:     couponDate,
                    amount:   amt
                )
                events.append(e)
            }
        }

        // 3) If any events, sort and format alert text
               if !events.isEmpty {
                   events.sort { $0.date < $1.date }

                   _ = Formatters.mediumDate
                   _ = Formatters.currency

                   var messageLines: [String] = ["Since your last visit:"]
                   var lastIssuerBank: (String, String)? = nil
                   var firstEventForIssuer = true // Track if it's the first event for the current issuer

                   for event in events {
                       let issuerBank = (event.name, event.bank)
                                   let formattedDate = Formatters.mediumDate.string(from: event.date) // Global Formatter
                                   let formattedAmount = Formatters.currency.string(from: NSNumber(value: event.amount)) ?? "\(event.amount)" // Global Formatter

                       if let last = lastIssuerBank, last == issuerBank {
                           // Same issuer, append event
                           if firstEventForIssuer {
                               messageLines.append("- \(formattedDate),")
                           }
                           messageLines.append("- \(event.kind.rawValue): \(formattedAmount)")
                           firstEventForIssuer = false // Not the first anymore

                       } else {
                           // New issuer
                           if !messageLines.isEmpty && !(messageLines.last?.starts(with: "Since") ?? false) {
                               messageLines.append("") // Add a blank line between issuers
                           }
                           messageLines.append("\(event.name) at \(event.bank):")
                           messageLines.append("- \(formattedDate),")
                           messageLines.append("- \(event.kind.rawValue): \(formattedAmount)")

                           lastIssuerBank = issuerBank
                           firstEventForIssuer = false // Reset for the new issuer
                       }
                   }

                   alertMessage = messageLines.joined(separator: "\n")
               }

               // 4) Save new last‐launch timestamp
               defaults.set(now, forKey: "lastLaunchDate")
           }
       }
