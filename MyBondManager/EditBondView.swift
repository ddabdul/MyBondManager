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
    @State private var couponRate: String
    @State private var depotBank: String
    @State private var acquisitionDate: Date
    @State private var yieldToMaturity: String
    @State private var maturityDate: Date

    init(bond: BondEntity) {
        print("[EditBondView] init for bond ISIN: \(bond.isin)")
        self.bond = bond
        _name            = State(initialValue: bond.name)
        _issuer          = State(initialValue: bond.issuer)
        _isin            = State(initialValue: bond.isin)
        _wkn             = State(initialValue: bond.wkn)
        _parValue        = State(initialValue: String(bond.parValue))
        _initialPrice    = State(initialValue: String(bond.initialPrice))
        _couponRate      = State(initialValue: String(bond.couponRate))
        _depotBank       = State(initialValue: bond.depotBank)
        _acquisitionDate = State(initialValue: bond.acquisitionDate)
        _yieldToMaturity = State(initialValue: String(bond.yieldToMaturity))
        _maturityDate    = State(initialValue: bond.maturityDate)
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
                TextField("Initial Price", text: $initialPrice)
                TextField("Coupon Rate (%)", text: $couponRate)
                TextField("Yield to Maturity (%)", text: $yieldToMaturity)
                    .disabled(true) // we’ll recalc this
            }

            Section("Dates & Bank") {
                DatePicker("Acquisition Date", selection: $acquisitionDate, displayedComponents: .date)
                DatePicker("Maturity Date",    selection: $maturityDate,    displayedComponents: .date)
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
    }

    private func saveChanges() {
        guard !isSaving, let container = portfolioContainer else {
            errorMessage = "Portfolio store is unavailable."
            return
        }
        guard let nominal = Double(parValue), nominal.isFinite, nominal > 0,
              let cost = Double(initialPrice), cost.isFinite, cost > 0,
              let rate = Double(couponRate), rate.isFinite, rate >= 0,
              acquisitionDate <= maturityDate else {
            errorMessage = "Enter positive nominal and purchase cost, a nonnegative coupon, and valid dates."
            return
        }
        let years = maturityDate.timeIntervalSince(acquisitionDate) / (365 * 24 * 3600)
        let ytm = years > 0 ? ((nominal * rate / 100 + (nominal - cost) / years) / ((nominal + cost) / 2)) * 100 : 0
        let values = BondCodable(id: bond.id, name: name, isin: isin,
            issuer: issuer, depotBank: depotBank, acquisitionDate: acquisitionDate,
            maturityDate: maturityDate, couponRate: rate, parValue: nominal, initialPrice: cost,
            yieldToMaturity: ytm, wkn: wkn, cashFlows: [])
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
            let financialChange = entity.parValue != values.parValue || entity.initialPrice != values.initialPrice
                || entity.couponRate != values.couponRate || entity.depotBank != values.depotBank
                || entity.acquisitionDate != values.acquisitionDate || entity.maturityDate != values.maturityDate
            if financialChange {
                let history = HistoricalValuation.fetchRequest()
                history.predicate = NSPredicate(format:
                    "assetType == %@ AND (eventKey BEGINSWITH %@ OR eventKey == nil OR eventKey == '')",
                    AssetType.bond.rawValue, entity.id.uuidString + "|")
                history.fetchLimit = 1
                guard try context.count(for: history) == 0 else {
                    throw PortfolioError("Financial values, dates and bank cannot be changed while related or unlinked legacy bond history exists. Descriptive fields can still be edited; history corrections need a separate reconciliation.")
                }
            }
            entity.id = values.id; entity.name = values.name; entity.isin = values.isin
            entity.issuer = values.issuer; entity.depotBank = values.depotBank
            entity.acquisitionDate = values.acquisitionDate; entity.maturityDate = values.maturityDate
            entity.couponRate = values.couponRate; entity.parValue = values.parValue
            entity.initialPrice = values.initialPrice; entity.yieldToMaturity = values.yieldToMaturity
            entity.wkn = values.wkn
            try CashFlowGenerator(context: context).regenerateCashFlows(for: entity)
        }
    }

}
