import SwiftUI

enum BondTermsPresentation {
    static func status(assessment: TermsAssessment, approved: Bool) -> String { approved && assessment.supported ? "Ready" : "Needs review" }
    static func exclusions(_ count: Int) -> String? {
        guard count > 0 else { return nil }
        return count == 1 ? "Forecast excludes 1 holding needing review." : "Forecast excludes \(count) holdings needing review."
    }
    static func callWarning(_ terms: BondTerms) -> String? { terms.callable == true ? "Early redemption is not modeled." : nil }
    static func importSummary(_ transfer: PreparedBondTransfer, existingIDs: Set<UUID>) -> String {
        let removed = existingIDs.subtracting(transfer.bonds.map(\.id)).count
        let mode = transfer.native == nil ? "Legacy positions: all imported holdings need Needs review approval." : "Native terms: \(transfer.unresolvedCount) holdings need review."
        let empty = transfer.bonds.isEmpty ? " This removes all bond positions." : ""
        return "\(transfer.bonds.count) incoming bonds; \(removed) removed; \(existingIDs.count) current bonds replaced.\(empty) \(mode) ETFs and existing financial history are kept. This is not a history backup."
    }
}

struct BondTermsFields: View {
    @Binding var terms: BondTerms
    @State private var text: [String: String] = [:]
    @State private var errors: [String: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Currency", text: Binding(get: { terms.currency ?? "" }, set: {
                    terms.currency = $0.isEmpty ? nil : $0.uppercased(); terms.confirmedFields.insert("currency")
                }))
                Picker("Structure", selection: Binding(get: { terms.structure.rawValue }, set: {
                    terms.structure = BondStructure(rawValue: $0) ?? .unknown; terms.confirmedFields.insert("structure")
                })) {
                    Text("Unknown").tag("unknown"); Text("Fixed").tag("fixed"); Text("Zero coupon").tag("zero")
                }
            }
            if let raw = terms.rawStructure { Text("Provider structure: " + raw).font(.caption).foregroundStyle(.secondary) }
            Picker("Payments per year", selection: Binding(get: { terms.frequency.map(String.init) ?? "unknown" }, set: {
                terms.frequency = Int($0); terms.confirmedFields.insert("frequency")
            })) {
                Text("Unknown").tag("unknown"); Text("Annual").tag("1"); Text("Semiannual").tag("2"); Text("Quarterly").tag("4")
                if let value = terms.frequency, ![1,2,4].contains(value) { Text("Unsupported: \(value)").tag(String(value)) }
            }
            if terms.structure == .zero { Text("Zero-coupon instruments pay redemption only; frequency and next-coupon metadata are ignored.").font(.caption).foregroundStyle(.secondary) }
            numberField("Annual coupon (%)", key: "couponRate", path: \.couponRate)
            numberField("Redemption (%)", key: "redemptionPercent", path: \.redemptionPercent)
            dateField("Contractual maturity", key: "maturity", path: \.maturity)
            dateField("Accrual start", key: "accrualStart", path: \.accrualStart)
            dateField("Issue date", key: "issueDay", path: \.issueDay)
            dateField("Next contractual coupon", key: "nextCoupon", path: \.nextCoupon)
            dateField("Checkpoint observed on", key: "checkpointObservedOn", path: \.checkpointObservedOn)
            Picker("Coupon roll", selection: Binding(get: { terms.roll?.rawValue ?? "unknown" }, set: {
                terms.roll = CouponRoll(rawValue: $0); terms.confirmedFields.insert("roll")
            })) {
                Text("Unconfirmed").tag("unknown"); Text("Day of month").tag("dayOfMonth"); Text("End of month").tag("endOfMonth")
            }
            Picker("Callable before maturity", selection: Binding(get: { terms.callable.map { $0 ? "yes" : "no" } ?? "unknown" }, set: {
                terms.callable = $0 == "unknown" ? nil : $0 == "yes"; terms.confirmedFields.insert("callable")
            })) { Text("Unknown").tag("unknown"); Text("Yes").tag("yes"); Text("No").tag("no") }
            if let warning = BondTermsPresentation.callWarning(terms) { Text(warning).foregroundStyle(.orange) }
            Divider()
            convention("Coupon day count", key: "dayCount", path: \.dayCount)
            convention("Payment calendar", key: "calendar", path: \.calendar)
            convention("Payment adjustment", key: "adjustment", path: \.adjustment)
            Text("Only Actual/Actual (ICMA), TARGET and Following are calculated. Other conventions need review. Payment delays add no interest.")
                .font(.caption).foregroundStyle(.secondary)
            if !terms.restrictions.isEmpty { Text("Provider restrictions: " + terms.restrictions.joined(separator: "; ")).foregroundStyle(.orange) }
            Text("Source: \(terms.collectedAt == nil ? "current holding / manual entry" : "ING"). Edited fields are confirmed; untouched convention defaults remain assumed.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
    private func numberField(_ label: String, key: String, path: WritableKeyPath<BondTerms, Double?>) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("Value", text: Binding(get: { text[key] ?? terms[keyPath: path].map { String($0) } ?? "" }, set: { value in
                text[key] = value; terms.confirmedFields.insert(key)
                let parsed = Double(value); terms[keyPath: path] = parsed
                errors[key] = !value.isEmpty && (parsed == nil || parsed?.isFinite == false) ? "Enter a finite number." : nil
            }))
            if let error = errors[key] { Text(error).font(.caption).foregroundStyle(.red) }
            if terms.confirmedFields.contains(key) { Text("Confirmed").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func dateField(_ label: String, key: String, path: WritableKeyPath<BondTerms, MarketDay?>) -> some View {
        VStack(alignment: .leading) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField("YYYY-MM-DD", text: Binding(get: { text[key] ?? terms[keyPath: path]?.rawValue ?? "" }, set: { value in
                text[key] = value; terms.confirmedFields.insert(key)
                if value.isEmpty { terms[keyPath: path] = nil; errors[key] = nil; return }
                do {
                    terms[keyPath: path] = try MarketDay(value); errors[key] = nil
                    if key == "nextCoupon" {
                        terms.checkpointObservedOn = MarketDay(date: Date())
                        text["checkpointObservedOn"] = terms.checkpointObservedOn?.rawValue
                    }
                } catch { terms[keyPath: path] = nil; errors[key] = error.localizedDescription }
            }))
            if let error = errors[key] { Text(error).font(.caption).foregroundStyle(.red) }
            if terms.confirmedFields.contains(key) { Text("Confirmed").font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func convention(_ label: String, key: String, path: WritableKeyPath<BondConventions, String>) -> some View {
        let choices: [(String, String)]
        switch key {
        case "dayCount": choices = [("actualActualICMA", "Actual/Actual (ICMA)"), ("actual360", "Actual/360 (needs review)"), ("actual365Fixed", "Actual/365 Fixed (needs review)"), ("thirty360", "30/360 (needs review)")]
        case "calendar": choices = [("TARGET", "TARGET"), ("weekendsOnly", "Weekends only (needs review)"), ("none", "No holiday calendar (needs review)")]
        default: choices = [("following", "Following"), ("modifiedFollowing", "Modified Following (needs review)"), ("unadjusted", "Unadjusted (needs review)"), ("preceding", "Preceding (needs review)")]
        }
        return HStack {
            Picker(label, selection: Binding(get: { terms.conventions[keyPath: path] }, set: {
                terms.conventions[keyPath: path] = $0; terms.conventions.sources[key] = .confirmed
            })) {
                ForEach(choices.indices, id: \.self) { index in Text(choices[index].1).tag(choices[index].0) }
                if !choices.contains(where: { $0.0 == terms.conventions[keyPath: path] }) {
                    Text("Unsupported: " + terms.conventions[keyPath: path]).tag(terms.conventions[keyPath: path])
                }
            }
            Toggle("Confirmed", isOn: Binding(get: { terms.conventions.sources[key] == .confirmed }, set: {
                terms.conventions.sources[key] = $0 ? .confirmed : .assumed
            })).toggleStyle(.checkbox)
        }
    }
}

struct BondTermsStatus: View {
    @ObservedObject var bond: BondEntity
    private var terms: Result<BondTerms?, Error> {
        Result { try BondTermsStore.read(bond) ?? BondTermsStore.readDraft(bond)?.proposed }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(BondTermsStore.isReady(bond) ? "Ready" : "Needs review").foregroundStyle(BondTermsStore.isReady(bond) ? .green : .orange)
            if let issue = bond.termsIssue, !issue.isEmpty { Text(issue).font(.caption).foregroundStyle(.orange) }
            switch terms {
            case .success(let value):
                if let value {
                    Text("\(value.currency ?? "Unknown currency") / \(value.structure == .zero ? "Redemption only" : (value.frequency.map { "\($0) payments per year" } ?? "Unknown frequency"))").font(.caption)
                    Text("Contractual maturity: \(value.maturity?.rawValue ?? "Unknown") / Payment: \(bond.redemptionPaymentDate.map { MarketDay(date: $0).rawValue } ?? "Unverified")").font(.caption)
                    Text("Day count: \(value.conventions.dayCount == "actualActualICMA" ? "Actual/Actual (ICMA)" : value.conventions.dayCount) (\(value.conventions.sources["dayCount"]?.rawValue ?? "assumed"))").font(.caption)
                    Text("Calendar: \(value.conventions.calendar) (\(value.conventions.sources["calendar"]?.rawValue ?? "assumed")); adjustment: \(value.conventions.adjustment.capitalized) (\(value.conventions.sources["adjustment"]?.rawValue ?? "assumed"))").font(.caption)
                    if let warning = BondTermsPresentation.callWarning(value) { Text(warning).font(.caption).foregroundStyle(.orange) }
                    if !BondTermsStore.isReady(bond) {
                        switch Result(catching: { try BondSchedule.preview(trade: BondTermsStore.trade(bond), terms: value, from: MarketDay(date: Date())) }) {
                        case .success(let preview):
                            if preview.assessment.supported { Text("Awaiting approval of this trade and schedule.").font(.caption) }
                            else { Text(preview.assessment.reasons.joined(separator: " ")).font(.caption).foregroundStyle(.orange) }
                        case .failure(let error): Text(error.localizedDescription).font(.caption).foregroundStyle(.red)
                        }
                    }
                } else { Text("Review instrument terms before including payments in forecasts.").font(.caption) }
            case .failure(let error): Text(error.localizedDescription).font(.caption).foregroundStyle(.red)
            }
        }
    }
}
