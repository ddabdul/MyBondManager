//
//  HistoricalDataRecorder.swift
//  MyBondManager
//
//  Created by Olivier on 08/06/2025.
//

import Foundation
import CoreData

enum AssetType: String {
    case bond = "Bond"
    case etf  = "ETF"
}

final class HistoricalDataRecorder {
    
    /// Generic recorder for any change in historical valuation.
    /// - Parameters:
    ///   - assetType: .bond or .etf
    ///   - depotBank: for bonds, nil for ETFs
    ///   - investedDelta: positive for acquisition, negative for sale/maturity principal
    ///   - interestDelta: amount of interest received (nil if not applicable)
    ///   - gainsDelta: capital gains (sale price – cost basis) or 0 if none
    ///   - date: timestamp of the event (defaults to now)
    ///   - context: your NSManagedObjectContext
    static func recordChange(
        assetType: AssetType,
        depotBank: String? = nil,
        investedDelta: Double,
        interestDelta: Double?,
        gainsDelta: Double,
        date: Date = Date(),
        context: NSManagedObjectContext
    ) throws {
        let hist = HistoricalValuation(context: context)
        hist.id               = UUID()
        hist.date             = date
        hist.assetType        = assetType.rawValue
        hist.depotBank        = depotBank
        hist.investedCapital  = NSDecimalNumber(value: investedDelta)
        hist.interestReceived = interestDelta.map { NSDecimalNumber(value: $0) }
        hist.capitalGains     = NSDecimalNumber(value: gainsDelta)
        
        try context.save()
    }
    
    // MARK: – Convenience Methods
    
    /// Call after creating a new BondEntity to record its nominal as starting point.
    static func recordBondAcquisition(
        bond: BondEntity,
        context: NSManagedObjectContext
    ) throws {
        try recordChange(
            assetType: .bond,
            depotBank: bond.depotBank,
            investedDelta: bond.parValue,
            interestDelta: 0,
            gainsDelta: 0,
            date: bond.acquisitionDate,
            context: context
        )
    }
    
    /// Call when a bond pays a coupon.
    static func recordBondInterest(
        bond: BondEntity,
        amount: Double,
        date: Date = Date(),
        context: NSManagedObjectContext
    ) throws {
        try recordChange(
            assetType: .bond,
            depotBank: bond.depotBank,
            investedDelta: 0,
            interestDelta: amount,
            gainsDelta: 0,
            date: date,
            context: context
        )
    }
    
    /// Call when a bond matures or is redeemed.
    /// - Parameters:
    ///   - bond: the matured bond
    ///   - redemptionAmount: amount you receive at maturity (principal + any redemption gain)
    static func recordBondMaturity(
        bond: BondEntity,
        redemptionAmount: Double,
        date: Date = Date(),
        context: NSManagedObjectContext
    ) throws {
        // principal outflow = –parValue
        let principalDelta = -bond.parValue
        // any capital gain = redemptionAmount – parValue
        let gainDelta = redemptionAmount - bond.parValue
        
        try recordChange(
            assetType: .bond,
            depotBank: bond.depotBank,
            investedDelta: principalDelta,
            interestDelta: 0,
            gainsDelta: gainDelta,
            date: date,
            context: context
        )
    }
    
    /// Call after creating a new ETFHolding to record its cost as starting point.
    static func recordETFAcquisition(
        holding: ETFHoldings,
        context: NSManagedObjectContext
    ) throws {
        try recordChange(
            assetType: .etf,
            depotBank: nil,
            investedDelta: holding.cost,
            interestDelta: nil,
            gainsDelta: 0,
            date: holding.acquisitionDate,
            context: context
        )
    }
    
    /// Call when selling an ETF lot.
    /// - Parameters:
    ///   - holding: the original holding
    ///   - soldShares: number of shares sold
    ///   - pricePerShare: sale price per share
    static func recordETFSale(
        holding: ETFHoldings,
        soldShares: Int,
        pricePerShare: Double,
        date: Date = Date(),
        context: NSManagedObjectContext
    ) throws {
        let costBasis    = Double(soldShares) * holding.acquisitionPrice
        let saleProceeds = Double(soldShares) * pricePerShare
        let principalDelta = -costBasis
        let gainDelta      = saleProceeds - costBasis
        
        try recordChange(
            assetType: .etf,
            depotBank: nil,
            investedDelta: principalDelta,
            interestDelta: nil,
            gainsDelta: gainDelta,
            date: date,
            context: context
        )
    }
}
