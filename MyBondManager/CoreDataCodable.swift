//
// CoreDataCodables.swift
// Shared Codable definitions for Export & Import
//  MyBondManager
//
//  Created by Olivier on 03/05/2025.
//




import Foundation

public struct CashFlowCodable: Codable, Equatable, Sendable {
    public let date: Date
    public let amount: Double
    public let nature: String
}

public struct BondCodable: Codable, Equatable, Sendable {
    public let id: UUID
    public let name: String
    public let isin: String
    public let issuer: String
    public let depotBank: String
    public let acquisitionDate: Date
    public let maturityDate: Date
    public let couponRate: Double
    public let parValue: Double
    public let initialPrice: Double
    public let yieldToMaturity: Double
    public let wkn: String
    public let cashFlows: [CashFlowCodable]
}

public struct ETFPriceCodable: Codable, Equatable, Sendable {
    public let id: String
    public let datePrice: Date
    public let price: Double
    public let etfId: UUID
}

public struct ETFHoldingsCodable: Codable, Equatable, Sendable {
    public let id: String
    public let etfId: UUID
    public let acquisitionDate: Date
    public let acquisitionPrice: Double
    public let numberOfShares: Int32
}

public struct ETFEntityCodable: Codable, Equatable, Sendable {
    public let id: UUID
    public let etfName: String
    public let isin: String
    public let issuer: String
    public let wkn: String
    public let lastPrice: Double
    public let priceHistory: [ETFPriceCodable]
    public let holdings: [ETFHoldingsCodable]
}

public struct PositionsPayload: Sendable {
    public let bonds: [BondCodable]
    public let etfs: [ETFEntityCodable]
}
