// EditBondView.swift
// MyBondManager
// Added the cashflow calculation
// Updated on 28/04/2025.


import SwiftUI
import CoreData

struct EditBondView: View {
    @Environment(\.managedObjectContext) private var moc
    @Environment(\.dismiss)      private var dismiss

    @ObservedObject var bond: BondEntity

    // Local editable copy of each field
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
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 500)
    }

    private func saveChanges() {
        // 1️⃣ Update text fields
        bond.name       = name
        bond.issuer     = issuer
        bond.isin       = isin
        bond.wkn        = wkn
        bond.depotBank  = depotBank
        bond.acquisitionDate = acquisitionDate
        bond.maturityDate    = maturityDate

        // 2️⃣ Parse numeric inputs (fallback to existing if parsing fails)
        let parVal      = Double(parValue)     ?? bond.parValue
        let pricePaid   = Double(initialPrice) ?? bond.initialPrice
        let couponPct   = Double(couponRate)   ?? bond.couponRate

        bond.parValue     = parVal
        bond.initialPrice = pricePaid
        bond.couponRate   = couponPct

        // 3️⃣ Recalculate YTM
        let couponPayment = parVal * couponPct / 100.0
        let secondsPerYear = 365 * 24 * 3600
        let years = maturityDate.timeIntervalSince(acquisitionDate) / Double(secondsPerYear)

        let newYTM: Double
        if years > 0 {
            let numerator   = couponPayment + (parVal - pricePaid) / years
            let denominator = (parVal + pricePaid) / 2
            newYTM = (numerator / denominator) * 100.0
        } else {
            newYTM = 0
        }
        bond.yieldToMaturity = newYTM

        do {
            // 4️⃣ Regenerate cash flows with updated terms
            let generator = CashFlowGenerator(context: moc)
            try generator.regenerateCashFlows(for: bond)

            // 5️⃣ Save everything in one shot
            try moc.save()
            print("[EditBondView] Saved edits and recalculated YTM (\(String(format: "%.2f", newYTM))%) + cash flows")
        } catch {
            print("[EditBondView] Error saving bond or regenerating cash flows: \(error)")
        }
    }
}
