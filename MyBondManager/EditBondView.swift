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
                TextField("Coupon Rate", text: $couponRate)
                TextField("Yield to Maturity", text: $yieldToMaturity)
            }

            Section("Dates & Bank") {
                DatePicker("Acquisition Date", selection: $acquisitionDate, displayedComponents: .date)
                DatePicker("Maturity Date",    selection: $maturityDate,    displayedComponents: .date)
                TextField("Depot Bank", text: $depotBank)
            }

            HStack {
                Spacer()
                Button("Cancel") {
                    print("[EditBondView] Cancel tapped")
                    dismiss()
                }
                Button("Save") {
                    print("[EditBondView] Save tapped")
                    saveChanges()
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(minWidth: 400, minHeight: 500)
        .onAppear {
            print("[EditBondView] onAppear for bond ISIN: \(bond.isin)")
        }
        .onDisappear {
            print("[EditBondView] onDisappear for bond ISIN: \(bond.isin)")
        }
    }

    private func saveChanges() {
        print("[EditBondView] saveChanges() begin for bond ISIN: \(bond.isin)")

        // 1️⃣ Update the bond’s properties
        bond.name            = name
        bond.issuer          = issuer
        bond.isin            = isin
        bond.wkn             = wkn
        bond.parValue        = Double(parValue)       ?? bond.parValue
        bond.initialPrice    = Double(initialPrice)   ?? bond.initialPrice
        bond.couponRate      = Double(couponRate)     ?? bond.couponRate
        bond.yieldToMaturity = Double(yieldToMaturity) ?? bond.yieldToMaturity
        bond.depotBank       = depotBank
        bond.acquisitionDate = acquisitionDate
        bond.maturityDate    = maturityDate

        do {
            // 2️⃣ Regenerate all cash‐flow events for this bond
            let generator = CashFlowGenerator(context: moc)
            try generator.regenerateCashFlows(for: bond)

            // 3️⃣ Save both the bond changes and its new cash flows
            try moc.save()
            print("[EditBondView] Successfully saved bond and regenerated cash flows")
        } catch {
            print("[EditBondView] Error saving or regenerating cash flows: \(error)")
        }
    }
}
