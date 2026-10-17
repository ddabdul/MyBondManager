import SwiftUI

struct FloatingTermsFields: View {
    @Binding var terms: FloatingBondTerms
    @State private var text: [String: String] = [:]
    private let required = ["indexTenorMonths", "spreadBps", "gearing", "resetLagTARGETDays", "resetTiming", "resetAnchor", "dayCount", "frequency", "accrualAdjustment", "paymentAdjustment", "roll", "payoff"]
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Floating phase contract").font(.headline)
            integer("EURIBOR tenor (months)", "indexTenorMonths", \.indexTenorMonths)
            number("Spread (basis points)", "spreadBps", \.spreadBps)
            number("Gearing", "gearing", \.gearing)
            integer("Reset lag (TARGET business days)", "resetLagTARGETDays", \.resetLagTARGETDays)
            choice("Reset timing", "resetTiming", \.resetTiming, [("inAdvance","In advance"),("inArrears","In arrears (unsupported)")])
            choice("Reset anchor", "resetAnchor", \.resetAnchor, [("contractualAccrualStart","Contractual accrual start"),("adjustedAccrualStart","Adjusted accrual start")])
            choice("Floating day count", "dayCount", \.dayCount, [("actual360","Actual/360"),("actual365Fixed","Actual/365 Fixed (unsupported)"),("actualActualICMA","Actual/Actual ICMA (unsupported)")])
            integer("Floating payments per year (1, 2, 4 or 12)", "frequency", \.frequency)
            choice("Accrual adjustment", "accrualAdjustment", \.accrualAdjustment, [("unadjusted","Unadjusted"),("modifiedFollowing","Modified Following")])
            choice("Floating payment adjustment", "paymentAdjustment", \.paymentAdjustment, [("following","Following"),("modifiedFollowing","Modified Following")])
            choice("Floating coupon roll", "roll", \.roll, [("dayOfMonth","Day of month"),("endOfMonth","End of month")])
            choice("Coupon payoff", "payoff", \.payoff, [("plain","Plain, no cap or floor"),("cappedOrFloored","Capped or floored (unsupported)"),("other","Other (unsupported)")])
            TextField("First floating coupon (YYYY-MM-DD, when irregular)", text: Binding(get: {
                text["firstFloatingCoupon"] ?? terms.firstFloatingCoupon?.rawValue ?? ""
            }, set: { value in
                guard value != (text["firstFloatingCoupon"] ?? terms.firstFloatingCoupon?.rawValue ?? "") else { return }
                text["firstFloatingCoupon"] = value
                terms.firstFloatingCoupon = try? MarketDay(value)
                if value.isEmpty { terms.confirmedFields.remove("firstFloatingCoupon") }
                else { terms.confirmedFields.insert("firstFloatingCoupon") }
            }))
            Button("Confirm entered floating terms") { terms.confirmedFields.formUnion(required) }
            Text("Confirm the contract facts, including absence of caps/floors. No floating convention is silently assumed. EURIBOR 1M/12M curves require matching imported quotes.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func integer(_ label: String, _ key: String, _ path: WritableKeyPath<FloatingBondTerms, Int?>) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption)
            TextField("Required", text: Binding(get: { text[key] ?? terms[keyPath: path].map(String.init) ?? "" }, set: { value in
                guard value != (text[key] ?? terms[keyPath: path].map(String.init) ?? "") else { return }
                text[key] = value; terms[keyPath: path] = Int(value); terms.confirmedFields.insert(key)
            }))
        }
    }
    private func number(_ label: String, _ key: String, _ path: WritableKeyPath<FloatingBondTerms, Double?>) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption)
            TextField("Required", text: Binding(get: { text[key] ?? terms[keyPath: path].map { String($0) } ?? "" }, set: { value in
                guard value != (text[key] ?? terms[keyPath: path].map { String($0) } ?? "") else { return }
                text[key] = value; terms[keyPath: path] = Double(value); terms.confirmedFields.insert(key)
            }))
        }
    }
    private func choice<T: RawRepresentable>(_ label: String, _ key: String, _ path: WritableKeyPath<FloatingBondTerms, T?>,
                                             _ choices: [(String,String)]) -> some View where T.RawValue == String {
        Picker(label, selection: Binding(get: { terms[keyPath: path]?.rawValue ?? "unknown" }, set: { value in
            guard value != (terms[keyPath: path]?.rawValue ?? "unknown") else { return }
            terms[keyPath: path] = T(rawValue: value); terms.confirmedFields.insert(key)
        })) {
            Text("Unknown / unconfirmed").tag("unknown")
            ForEach(choices.indices, id: \.self) { index in Text(choices[index].1).tag(choices[index].0) }
        }
    }
}

struct MarketSnapshotPicker: View {
    @Binding var context: ProjectionContext?
    @State private var snapshots: [MarketDataSnapshot] = []
    @State private var selectedID = "none"
    @State private var dayText = ""
    @State private var error: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Picker("Frozen market snapshot", selection: Binding(get: { selectedID }, set: { selectedID = $0; update() })) {
                Text("Select dated market inputs").tag("none")
                ForEach(snapshots, id: \.id) { snapshot in
                    Text("EURIBOR \(snapshot.payload.quotes.indexTenorMonths)M · \(snapshot.payload.quotes.quoteDay.rawValue) · \(snapshot.id.prefix(8))").tag(snapshot.id)
                }
            }
            TextField("Valuation day (YYYY-MM-DD)", text: Binding(get: { dayText }, set: { dayText = $0; update() }))
            if let error { Text(error).font(.caption).foregroundStyle(.orange) }
            Text("Missing a snapshot? Open Market Data to refresh or import dated inputs. Selecting here changes this draft only.").font(.caption).foregroundStyle(.secondary)
        }.onAppear {
            do {
                snapshots = try MarketDataStore().list()
                if let pinned = context?.marketData, !snapshots.contains(where: { $0.id == pinned.id }) { snapshots.insert(pinned, at: 0) }
                selectedID = context?.marketData.id ?? "none"
                dayText = context?.valuationDay.rawValue ?? MarketDay(date: Date()).rawValue
            } catch { self.error = error.localizedDescription }
        }
    }
    private func update() {
        guard let snapshot = snapshots.first(where: { $0.id == selectedID }) else { context = nil; return }
        do {
            let value = try ProjectionContext(valuationDay: MarketDay(dayText), marketData: snapshot)
            try value.validate(); context = value; error = nil
        } catch { context = nil; self.error = error.localizedDescription }
    }
}
