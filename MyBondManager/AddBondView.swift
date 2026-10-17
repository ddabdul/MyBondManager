import SwiftUI
import CoreData

struct AddBondViewAsync: View {
    @Environment(\.portfolioContainer) private var portfolioContainer
    @Environment(\.dismiss) private var dismiss
    @StateObject private var collection = BondCollection()
    @State private var positionID = UUID()
    @State private var acquisitionDate = Date()
    @State private var parValueStr = ""
    @State private var acquisitionPrice = ""
    @State private var depotBank = ""
    @State private var terms = BondTerms()
    @State private var previewDay = MarketDay(date: Date())
    @State private var approve = false
    @State private var projectionContext: ProjectionContext?
    @State private var isSaving = false
    @State private var errorMessage = ""

    private var preview: Result<BondSchedulePreview, Error> {
        Result {
            guard let nominal = Double(parValueStr), let cost = Double(acquisitionPrice) else { throw PortfolioError("Enter nominal and acquisition cost to preview payments.") }
            return try BondSchedule.preview(trade: BondTrade(id: positionID, isin: ETFPurchase.normalizedISIN(collection.isin),
                nominal: nominal, cost: cost, acquisitionDay: MarketDay(date: acquisitionDate, calendar: .current), bank: depotBank), terms: terms, from: previewDay, context: projectionContext)
        }
    }
    private var supported: Bool { if case .success(let value) = preview { return value.assessment.supported }; return false }
    var body: some View {
        VStack(spacing: 12) {
            Text("Add New Bond").font(.headline).frame(maxWidth: .infinity).padding().background(AppTheme.tileBackground)
            ScrollView {
                Form {
                    Section("Purchase") {
                        TextField("ISIN", text: $collection.isin)
                        DatePicker("Acquisition Date", selection: $acquisitionDate, displayedComponents: .date)
                        TextField("Par Value", text: $parValueStr)
                        TextField("Acquisition Price", text: $acquisitionPrice)
                        TextField("Depot Bank", text: $depotBank)
                        Button("Collect Data") {
                            Task {
                                await collection.collect()
                                if let collected = collection.details?.terms { terms = collected; approve = false; previewDay = MarketDay(date: Date()) }
                            }
                        }.disabled(collection.isLoading || collection.isin.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                    }
                    if let details = collection.details {
                        Section("Collected instrument") {
                            Text(details.name); Text(details.issuer + " / " + details.wkn)
                            BondTermsFields(terms: $terms).id(ETFPurchase.normalizedISIN(collection.isin) + String(describing: terms.collectedAt))
                        }
                        if [.floating, .fixedToFloating].contains(terms.structure) { Section("Frozen market data") { MarketSnapshotPicker(context: $projectionContext) } }
                        Section("Payment Preview") {
                            switch preview {
                            case .success(let result):
                                ForEach(result.assessment.reasons, id: \.self) { Text($0).foregroundStyle(.orange) }
                                ForEach(Array(result.payments.enumerated()), id: \.offset) { _, payment in
                                    Text("\(payment.paymentDay.rawValue) - \(payment.kind.rawValue): \(String(format: "%.2f", payment.amount)) EUR")
                                }
                                if let yield = result.estimatedYTM { Text(String(format: "Estimated YTM: %.3f%%", yield)) }
                            case .failure(let error): Text(error.localizedDescription).foregroundStyle(.secondary)
                            }
                            Toggle("I reviewed these terms, conventions and payments.", isOn: $approve).disabled(!supported)
                            if !supported { Text("Save as Needs review to retain the holding without unverified forecast payments.").foregroundStyle(.secondary) }
                        }
                    }
                }.padding()
            }
            if !errorMessage.isEmpty { Text(errorMessage).foregroundStyle(.red) }
            if !collection.errorMessage.isEmpty { Text(collection.errorMessage).foregroundStyle(.red) }
            if collection.isLoading || isSaving { ProgressView() }
            HStack {
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(approve ? "Save Approved Bond" : "Save as Needs Review", action: saveBond)
                    .disabled(isSaving || collection.isLoading || collection.details == nil)
                    .keyboardShortcut(.defaultAction)
            }.padding()
        }
        .frame(minWidth: 650, minHeight: 650).background(AppTheme.panelBackground)
        .onChange(of: projectionContext) { _, _ in approve = false }
        .onChange(of: terms) { _, _ in approve = false }
        .onChange(of: collection.isin) { _, _ in terms = BondTerms(); approve = false }
        .onChange(of: parValueStr) { _, _ in resetPreview() }
        .onChange(of: acquisitionPrice) { _, _ in resetPreview() }
        .onChange(of: acquisitionDate) { _, _ in resetPreview() }
        .onChange(of: depotBank) { _, _ in resetPreview() }
    }
    private func resetPreview() { approve = false; previewDay = MarketDay(date: Date()) }
    private func saveBond() {
        guard !isSaving, let container = portfolioContainer else { errorMessage = "Portfolio store is unavailable."; return }
        let rate = terms.couponRate ?? 0
        guard let details = collection.details, rate.isFinite, rate >= 0,
              let maturity = terms.maturity, acquisitionDate <= maturity.instant,
              let nominal = Double(parValueStr), nominal.isFinite, nominal > 0,
              let cost = Double(acquisitionPrice), cost.isFinite, cost > 0,
              !depotBank.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            errorMessage = "Enter positive nominal/cost, a bank, a valid coupon and contractual maturity."; return
        }
        guard !approve || (supported && previewDay == MarketDay(date: Date())) else { errorMessage = "Refresh and review today's payment preview before approving."; resetPreview(); return }
        let values = BondCodable(id: positionID, name: details.name, isin: ETFPurchase.normalizedISIN(collection.isin),
            issuer: details.issuer, depotBank: depotBank, acquisitionDate: acquisitionDate, maturityDate: maturity.instant,
            couponRate: rate, parValue: nominal, initialPrice: cost, yieldToMaturity: 0, wkn: details.wkn, cashFlows: [])
        var savedTerms = terms; savedTerms.approvedAt = approve ? Date() : nil
        isSaving = true; errorMessage = ""
        Task { @MainActor in
            defer { isSaving = false }
            do {
                _ = try await BondTermsReview(container: container).saveNew(values: values, terms: savedTerms, legacyDateZone: TimeZone.current.identifier, projectionContext: projectionContext)
                dismiss()
            } catch { errorMessage = "Could not save bond: " + error.localizedDescription }
        }
    }
}
