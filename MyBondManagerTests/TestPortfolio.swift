import CoreData
import XCTest
@testable import MyBondManager

enum TestPortfolio {
    static let model = PersistenceController.managedObjectModel
    static func make() throws -> NSPersistentContainer {
        let container = NSPersistentContainer(name: "MyBondManager", managedObjectModel: model)
        let description = NSPersistentStoreDescription()
        description.type = NSInMemoryStoreType
        description.shouldAddStoreAsynchronously = false
        container.persistentStoreDescriptions = [description]
        var loadError: Error?
        container.loadPersistentStores { _, error in loadError = error }
        if let loadError { throw loadError }
        container.viewContext.automaticallyMergesChangesFromParent = true
        return container
    }
    static func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
    static func bond(in context: NSManagedObjectContext, cost: Double = 1100,
                     par: Double = 1000) -> BondEntity {
        let bond = BondEntity(context: context)
        bond.id = UUID(); bond.name = "Fixture"; bond.issuer = "Issuer"
        bond.isin = "DE0000000001"; bond.wkn = "TEST01"; bond.depotBank = "Bank"
        bond.initialPrice = cost; bond.parValue = par; bond.couponRate = 0
        bond.yieldToMaturity = 0
        bond.acquisitionDate = date("2025-01-01T00:00:00Z")
        bond.maturityDate = date("2027-01-01T00:00:00Z")
        return bond
    }
    static func holding(in context: NSManagedObjectContext, shares: Int32 = 10,
                        price: Double = 90, etf: ETFEntity? = nil) -> ETFHoldings {
        let instrument = etf ?? ETFEntity(context: context)
        if etf == nil {
            instrument.id = UUID(); instrument.etfName = "ETF fixture"
            instrument.isin = "DE0000000002"; instrument.wkn = "TEST02"
            instrument.issuer = "Issuer"; instrument.lastPrice = 100
        }
        let holding = ETFHoldings(context: context)
        holding.holdingtoetf = instrument; holding.numberOfShares = shares
        holding.acquisitionPrice = price
        holding.acquisitionDate = date("2025-01-01T00:00:00Z")
        return holding
    }
}

extension TestPortfolio {
    static func legacyBond(in context: NSManagedObjectContext, cost: Double = 1100, par: Double = 1000) -> BondEntity {
        bond(in: context, cost: cost, par: par)
    }
    static func readyBond(in context: NSManagedObjectContext, terms: BondTerms, now: Date,
                          nominal: Double = 1000, cost: Double = 900) throws -> BondEntity {
        let bond = bond(in: context, cost: cost, par: nominal)
        bond.acquisitionDate = date("2026-02-01T00:00:00Z")
        var approved = terms; approved.approvedAt = terms.approvedAt ?? now
        let day = try MarketDay("2026-02-01")
        let trade = BondTrade(id: bond.id, isin: bond.isin, nominal: nominal, cost: cost, acquisitionDay: day, bank: bond.depotBank)
        let preview = try BondSchedule.preview(trade: trade, terms: approved, from: MarketDay(date: now))
        guard preview.assessment.supported else { throw PortfolioError(preview.assessment.reasons.joined(separator: "\n")) }
        try BondTermsStore.replaceProjections(for: bond, terms: approved, preview: preview, now: now,
            acquisitionDay: day, legacyDateZone: "Europe/Berlin", context: context)
        return bond
    }
}
