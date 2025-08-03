//
//  CapitalTransactionRecorder.swift
//  MyBondManager
//
//  Created by Olivier on 21/06/2025.
//


import CoreData

/// A simple service for logging capital transactions.
struct CapitalTransactionRecorder {
  let context: NSManagedObjectContext

  /// Records the purchase of a bond.
  func recordBondPurchase(_ bond: BondEntity) {
    let txn = CapitalTransaction(context: context)
    txn.date   = bond.acquisitionDate
    txn.amount = bond.parValue    // nominal value
    txn.type   = "BondPurchase"
    txn.bond   = bond
  }

    /// Records a redemption (partial or full) of a bond, preventing duplicates.
    /// - Parameters:
    ///   - bond: the BondEntity being redeemed
    ///   - redeemedValue: the nominal amount redeemed (<= bond.parValue)
    ///   - date: the date of redemption
    func recordBondRedemption(_ bond: BondEntity,
                              redeemedValue: Double,
                              at date: Date) {
        // 1. Create a fetch request to check for an existing record.
        let fetchRequest = NSFetchRequest<CapitalTransaction>(entityName: "CapitalTransaction")

        // 2. Use a predicate to find a transaction that uniquely matches this event
        //    by checking the bond's unique ID, the transaction type, and the date.
        fetchRequest.predicate = NSPredicate(
            format: "bond.id == %@ AND type == %@ AND date == %@",
            bond.id as CVarArg,
            "BondRedemption",
            date as NSDate
        )

        do {
            // 3. Efficiently check if any such record already exists.
            let count = try context.count(for: fetchRequest)
            if count > 0 {
                // A record already exists, so we do nothing.
                print("INFO: Redemption for bond \(bond.name) (ID: \(bond.id)) on \(date) already recorded. Skipping.")
                return
            }
        } catch {
            print("ERROR: Could not perform fetch to check for duplicate transaction: \(error)")
            // Exit to prevent accidentally creating a duplicate if the check fails.
            return
        }

        // 4. If no existing record was found, create the new one.
        let txn = CapitalTransaction(context: context)
        txn.date   = date
        txn.amount = -redeemedValue
        txn.type   = "BondRedemption"
        txn.bond   = bond // Establish the relationship
    }


  /// Records the acquisition of an ETF.
    /// Records the acquisition of an ETF lot.
      func recordETFAcquisition(from holding: ETFHoldings) {
        let txn = CapitalTransaction(context: context)
        txn.date   = holding.acquisitionDate
        txn.amount = Double(holding.numberOfShares) * holding.acquisitionPrice
        txn.type   = "ETFBuy"
        txn.etf    = holding.holdingtoetf
      }

      /// Records the sale of an ETF lot (if and when you sell it).
    func recordETFSale(from holding: ETFHoldings) {
        // Only saleDate is optional now
        guard let sellDate = holding.saleDate else { return }

        let salePrice = holding.salePrice    // plain Double
        let txn = CapitalTransaction(context: context)
        txn.date   = sellDate
        txn.amount = -Double(holding.numberOfShares) * salePrice
        txn.type   = "ETFSell"
        txn.etf    = holding.holdingtoetf
    }

  /// Saves the context (call after batching one or more records).
  func save() throws {
    if context.hasChanges {
      try context.save()
    }
  }
}
