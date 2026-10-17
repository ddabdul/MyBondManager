import CoreData

enum PositionsTransferValidation {
    static func issues(bonds: [BondCodable], etfs: [ETFEntityCodable],
                       context: NSManagedObjectContext) throws -> [String] {
        let input = PositionsPayload(bonds: bonds, etfs: etfs)
        try ImportManager.validate(input)
        let stored = try ExportManager.snapshot(from: context)
        var issues: [String] = []
        let bondGroups = Dictionary(grouping: stored.bonds, by: \.id)
        let etfGroups = Dictionary(grouping: stored.etfs, by: \.id)
        guard bondGroups.values.allSatisfy({ $0.count == 1 }),
              etfGroups.values.allSatisfy({ $0.count == 1 }) else {
            throw PortfolioError("Stored positions contain duplicate identifiers.")
        }
        if Set(bonds.map(\.id)) != Set(stored.bonds.map(\.id)) { issues.append("Bond identifiers differ.") }
        if Set(etfs.map(\.id)) != Set(stored.etfs.map(\.id)) { issues.append("ETF identifiers differ.") }
        for bond in bonds {
            if let match = bondGroups[bond.id]?.first,
               try normalized(bond) != normalized(match) {
                issues.append("Bond fields or cash flows differ: \(bond.name).")
            }
        }
        for etf in etfs {
            if let match = etfGroups[etf.id]?.first,
               try normalized(etf) != normalized(match) {
                issues.append("ETF fields, holdings or prices differ: \(etf.etfName).")
            }
        }
        return issues
    }
    static func bondIssues(_ transfer: PreparedBondTransfer, context: NSManagedObjectContext) throws -> [String] {
        try BondTransfer.validate(transfer)
        let stored = try BondTransfer.snapshot(from: context)
        var issues: [String] = []
        if try stored.bonds.map(normalized).sorted() != transfer.bonds.map(normalized).sorted() {
            issues.append("Bond fields or cash flows differ.")
        }
        if let native = transfer.native {
            let encoder = BondTransfer.encoder(), decoder = BondTransfer.decoder()
            let current = try decoder.decode([BondTermsEntry].self, from: encoder.encode(stored.native!.bonds))
            let byID: (BondTermsEntry, BondTermsEntry) -> Bool = { $0.id.uuidString < $1.id.uuidString }
            if current.sorted(by: byID) != native.bonds.sorted(by: byID) { issues.append("Native bond terms or provenance differ.") }
        }
        return issues
    }

    private static func encoded<T: Encodable>(_ value: T) throws -> String {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .sortedKeys
        return try encoder.encode(value).base64EncodedString()
    }
    static func normalized(_ bond: BondCodable) throws -> String {
        // Nested rows are multisets; serialization normalizes dates to ISO-8601 seconds.
        let flows = try bond.cashFlows.map { try encoded($0) }.sorted()
        let fields = BondCodable(id: bond.id, name: bond.name, isin: bond.isin,
            issuer: bond.issuer, depotBank: bond.depotBank, acquisitionDate: bond.acquisitionDate,
            maturityDate: bond.maturityDate, couponRate: bond.couponRate, parValue: bond.parValue,
            initialPrice: bond.initialPrice, yieldToMaturity: bond.yieldToMaturity,
            wkn: bond.wkn, cashFlows: [])
        return try encoded(fields) + "|" + flows.joined(separator: "|")
    }
    private static func normalized(_ etf: ETFEntityCodable) throws -> String {
        let prices = try etf.priceHistory.map {
            try encoded(ETFPriceCodable(id: "", datePrice: $0.datePrice, price: $0.price, etfId: etf.id))
        }.sorted()
        let holdings = try etf.holdings.map {
            try encoded(ETFHoldingsCodable(id: "", etfId: etf.id, acquisitionDate: $0.acquisitionDate,
                acquisitionPrice: $0.acquisitionPrice, numberOfShares: $0.numberOfShares))
        }.sorted()
        let fields = ETFEntityCodable(id: etf.id, etfName: etf.etfName, isin: etf.isin,
            issuer: etf.issuer, wkn: etf.wkn, lastPrice: etf.lastPrice, priceHistory: [], holdings: [])
        return try encoded(fields) + "|" + prices.joined(separator: "|") + "|" + holdings.joined(separator: "|")
    }
}
