// EditBondView.swift
// MyBondManager
// Added the cashflow calculation
// Updated on 28/04/2025.


import SwiftUI
import CoreData

struct EditBondView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.portfolioContainer) private var portfolioContainer
    @State private var isSaving = false
    @State private var termsReview: BondTermsReview?
    @Environment(\.dismiss)      private var dismiss

    @ObservedObject var bond: BondEntity

    // Local editable copy of each field
    @State private var errorMessage = ""
    @State private var name: String
    @State private var issuer: String
    @State private var isin: String
    @State private var wkn: String
    @State private var parValue: String
    @State private var initialPrice: String
    @State private var depotBank: String
    @State private var acquisitionDate: Date

    init(bond: BondEntity) {
        print("[EditBondView] init for bond ISIN: \(bond.isin)")
        self.bond = bond
        _name            = State(initialValue: bond.name)
        _issuer          = State(initialValue: bond.issuer)
        _isin            = State(initialValue: bond.isin)
        _wkn             = State(initialValue: bond.wkn)
        _parValue        = State(initialValue: String(bond.parValue))
        _initialPrice    = State(initialValue: String(bond.initialPrice))
        _depotBank       = State(initialValue: bond.depotBank)
        _acquisitionDate = State(initialValue: bond.acquisitionDate)
    }

    var body: some View {
        Form {
            if !errorMessage.isEmpty { Text(errorMessage).foregroundColor(.red) }
            Section("Identifiers") {
                TextField("Name", text: $name)
                TextField("Issuer", text: $issuer)
                TextField("ISIN", text: $isin)
                TextField("WKN", text: $wkn)
            }

            Section("Financials") {
                TextField("Par Value", text: $parValue)
                TextField("Clean Purchase Cost", text: $initialPrice)
                Text("Coupon: " + bond.couponFormatted)
                Text("Estimated YTM at purchase: " + bond.ytmFormatted)
                BondTermsStatus(bond: bond)
                Button("Review instrument terms") { openTermsReview() }
            }

            Section("Dates & Bank") {
                DatePicker("Acquisition Date", selection: $acquisitionDate, displayedComponents: .date)
                Text("Contractual maturity: " + bond.contractualMaturityFormatted)
                TextField("Depot Bank", text: $depotBank)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    dismiss()
                }
                Button("Save") {
                    saveChanges()
                }
                .disabled(isSaving)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 500)
        .sheet(item: $termsReview) { review in
            BondTermsReviewView(review: review, initialSelection: bond.id)
        }
    }
    private func openTermsReview() {
        guard let container = portfolioContainer else { errorMessage = "Portfolio store is unavailable."; return }
        Task { @MainActor in
            do { termsReview = try await Self.prepareTermsReview(in: container) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    @MainActor
    static func prepareTermsReview(in container: NSPersistentContainer) async throws -> BondTermsReview {
        let review = BondTermsReview(container: container)
        try await review.load()
        return review
    }

    private func saveChanges() {
        guard !isSaving, let container = portfolioContainer else {
            errorMessage = "Portfolio store is unavailable."
            return
        }
        let rate = bond.couponRate, maturityDate = bond.maturityDate
        guard !ETFPurchase.normalizedISIN(isin).isEmpty, let nominal = Double(parValue), nominal.isFinite, nominal > 0,
              let cost = Double(initialPrice), cost.isFinite, cost > 0,
              rate.isFinite, rate >= 0,
              acquisitionDate <= maturityDate else {
            errorMessage = "Enter positive nominal and purchase cost, a nonnegative coupon, and valid dates."
            return
        }
        let values = BondCodable(id: bond.id, name: name, isin: isin,
            issuer: issuer, depotBank: depotBank, acquisitionDate: acquisitionDate,
            maturityDate: maturityDate, couponRate: rate, parValue: nominal, initialPrice: cost,
            yieldToMaturity: bond.yieldToMaturity, wkn: wkn, cashFlows: [])
        let bondID = bond.objectID
        isSaving = true; errorMessage = ""
        Task { @MainActor in
            defer { isSaving = false }
            do {
                try await Self.persistChanges(bondID: bondID, values: values, in: container)
                dismiss()
            } catch { errorMessage = "Could not save bond: \(error.localizedDescription)" }
        }
    }

    static func persistChanges(bondID: NSManagedObjectID, values: BondCodable,
                               in container: NSPersistentContainer) async throws {
        try await PortfolioTransaction.run(in: container) { context in
            guard let entity = try context.existingObject(with: bondID) as? BondEntity else {
                throw PortfolioError("The bond no longer exists.")
            }
            guard entity.id == values.id else { throw PortfolioError("The bond identity cannot be changed.") }
            let identityChanged = ETFPurchase.normalizedISIN(entity.isin) != ETFPurchase.normalizedISIN(values.isin)
            let acquisitionChanged = entity.acquisitionDate != values.acquisitionDate
            let previousDay = entity.termsAcquisitionDay
            let previousZone = entity.termsLegacyDateZone
            let previousTerms = try BondTermsStore.readDraft(entity)?.proposed ?? BondTermsStore.read(entity)
            let instrumentChanged = identityChanged || entity.couponRate != values.couponRate || entity.maturityDate != values.maturityDate
            let instrumentApproval = instrumentChanged ? nil : entity.termsData
            let financialChange = identityChanged || entity.parValue != values.parValue || entity.initialPrice != values.initialPrice
                || entity.couponRate != values.couponRate || entity.depotBank != values.depotBank
                || entity.acquisitionDate != values.acquisitionDate || entity.maturityDate != values.maturityDate
            if financialChange {
                let history = HistoricalValuation.fetchRequest()
                history.predicate = NSPredicate(format:
                    "assetType == %@ AND (eventKey BEGINSWITH %@ OR eventKey == nil OR eventKey == '')",
                    AssetType.bond.rawValue, entity.id.uuidString + "|")
                history.fetchLimit = 1
                guard try context.count(for: history) == 0 else {
                    throw PortfolioError("Instrument identity, financial values, dates and bank cannot be changed while related or unlinked legacy bond history exists. Descriptive fields can still be edited; history corrections need a separate reconciliation.")
                }
            }
            let localAliases = identityChanged ? [:] : try BondTermsStore.captureLegacyAliases(entity)
            if financialChange {
                BondTermsStore.clear(entity)
                // Keep the approved instrument terms while invalidating this purchase's projections.
                entity.termsData = instrumentApproval
            }
            entity.id = values.id; entity.name = values.name; entity.isin = values.isin
            entity.issuer = values.issuer; entity.depotBank = values.depotBank
            entity.acquisitionDate = values.acquisitionDate; entity.maturityDate = values.maturityDate
            entity.couponRate = values.couponRate; entity.parValue = values.parValue
            entity.initialPrice = values.initialPrice; entity.yieldToMaturity = values.yieldToMaturity
            entity.wkn = values.wkn
            if financialChange {
                entity.yieldToMaturity = 0
                let zone = acquisitionChanged ? TimeZone.current.identifier : (previousZone ?? TimeZone.current.identifier)
                var calendar = MarketDay.calendar; calendar.timeZone = TimeZone(identifier: zone)!
                let day = try (!acquisitionChanged ? previousDay : nil).map(MarketDay.init) ?? MarketDay(date: values.acquisitionDate, calendar: calendar)
                entity.termsAcquisitionDay = day.rawValue; entity.termsLegacyDateZone = zone
                entity.legacyEventAliasesData = try BondTermsStore.encode(localAliases)
                var proposed = identityChanged ? BondTerms() : (previousTerms ?? BondTerms())
                proposed.isin = ETFPurchase.normalizedISIN(values.isin); proposed.approvedAt = nil
                proposed.couponRate = values.couponRate
                if proposed.maturity == nil || proposed.maturity?.instant != values.maturityDate { proposed.maturity = MarketDay(date: values.maturityDate, calendar: calendar) }
                let draft = try BondTermsDraft(baseline: BondBaseline.capture(entity), trade: BondTermsStore.trade(entity),
                    legacyDateZone: zone, proposed: proposed, previewDay: MarketDay(date: Date()))
                try BondTermsStore.stageDraft(draft, for: entity)
                entity.termsIssue = "Needs review after a trade change."
            } else { try CashFlowGenerator(context: context).regenerateCashFlows(for: entity) }
        }
    }

}
