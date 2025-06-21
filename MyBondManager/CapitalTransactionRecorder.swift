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

  /// Records a redemption (partial or full) of a bond.
  /// - Parameters:
  ///   - bond: the BondEntity being redeemed
  ///   - redeemedValue: the nominal amount redeemed (<= bond.parValue)
  ///   - date: the date of redemption
  func recordBondRedemption(_ bond: BondEntity,
                            redeemedValue: Double,
                            at date: Date) {
    let txn = CapitalTransaction(context: context)
    txn.date   = date
    txn.amount = -redeemedValue
    txn.type   = "BondRedemption"
    txn.bond   = bond
  }

  /// Records the acquisition of an ETF.
  func recordETFAcquisition(_ etf: ETFEntity) {
    let txn = CapitalTransaction(context: context)
    txn.date   = etf.acquisitionDate
    txn.amount = etf.initialInvestment
    txn.type   = "ETFBuy"
    txn.etf    = etf
  }

  /// Records the sale of an ETF.
  func recordETFSale(_ etf: ETFEntity,
                     saleValue: Double,
                     at date: Date) {
    let txn = CapitalTransaction(context: context)
    txn.date   = date
    txn.amount = -saleValue
    txn.type   = "ETFSell"
    txn.etf    = etf
  }

  /// Saves the context (call after batching one or more records).
  func save() throws {
    if context.hasChanges {
      try context.save()
    }
  }
}
