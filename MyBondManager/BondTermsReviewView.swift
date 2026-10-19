import SwiftUI
import CoreData

struct BondTermsReviewNavigation {
    enum Action: Equatable { case close, collectMissing, refresh, manual, reuseApproved }
    private(set) var pending: Action?

    mutating func request(_ action: Action, hasUnsavedChanges: Bool) -> Action? {
        if hasUnsavedChanges { pending = action; return nil }
        pending = nil
        return action
    }
    mutating func cancel() { pending = nil }
}

struct BondTermsReviewInstrument: Identifiable {
    let isin: String
    let purchases: [BondEntity]
    let representative: BondEntity
    var id: String { isin }
    var needsReview: Bool { purchases.contains { !BondTermsStore.isReady($0) } }

    func reviewIssues(from day: MarketDay) -> [String] {
        purchases.compactMap { bond in
            do {
                if try BondTermsStore.validatedPreview(bond, from: day) != nil { return nil }
                return try BondTermsStore.exclusionReason(bond, from: day)
            } catch { return error.localizedDescription }
        }
    }

    static func scoped(_ bonds: [BondEntity], today: MarketDay, requestedIDs: Set<UUID>? = nil,
                       preferredID: UUID? = nil, draftIDs: Set<UUID> = []) -> [Self] {
        let eligible = Set(bonds.filter {
            if let requestedIDs { return requestedIDs.contains($0.id) }
            return BondEligibility.isActive($0, on: today) || $0.id == preferredID
        }.map { ETFPurchase.normalizedISIN($0.isin) })
        return grouped(bonds.filter { eligible.contains(ETFPurchase.normalizedISIN($0.isin)) },
            preferredID: preferredID, draftIDs: draftIDs)
    }

    static func grouped(_ bonds: [BondEntity], preferredID: UUID? = nil, draftIDs: Set<UUID> = []) -> [Self] {
        Dictionary(grouping: bonds, by: { ETFPurchase.normalizedISIN($0.isin) }).map { isin, records in
            let sorted = records.sorted {
                if $0.acquisitionDate != $1.acquisitionDate { return $0.acquisitionDate < $1.acquisitionDate }
                return $0.id.uuidString < $1.id.uuidString
            }
            let representative = sorted.first { $0.id == preferredID } ?? sorted.first { draftIDs.contains($0.id) } ?? sorted[0]
            return Self(isin: isin, purchases: sorted, representative: representative)
        }.sorted {
            if $0.representative.name != $1.representative.name { return $0.representative.name < $1.representative.name }
            return $0.isin < $1.isin
        }
    }
}

struct BondTermsReviewView: View {
    @ObservedObject var review: BondTermsReview
    var initialSelection: UUID? = nil
    var requestedIDs: Set<UUID>? = nil
    var reportRange: ClosedRange<MarketDay>? = nil
    var body: some View {
        BondTermsReviewContent(review: review, initialSelection: initialSelection, requestedIDs: requestedIDs, reportRange: reportRange)
            .environment(\.managedObjectContext, review.container.viewContext)
    }
}

private struct BondTermsReviewContent: View {
    @ObservedObject var review: BondTermsReview
    let initialSelection: UUID?
    let requestedIDs: Set<UUID>?
    let reportRange: ClosedRange<MarketDay>?
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \BondEntity.name, ascending: true)]) private var bonds: FetchedResults<BondEntity>
    @State private var selected: Set<String> = []
    @State private var focused: UUID?
    @State private var edited: BondTermsDraft?
    @State private var editorRevision = UUID()
    @State private var message = ""
    @State private var busy = false
    @State private var confirmApproval = false
    @State private var rebuildContext: ProjectionContext?
    @State private var navigation = BondTermsReviewNavigation()

    init(review: BondTermsReview, initialSelection: UUID?, requestedIDs: Set<UUID>?, reportRange: ClosedRange<MarketDay>?) {
        self.review = review; self.initialSelection = initialSelection; self.requestedIDs = requestedIDs; self.reportRange = reportRange
        _focused = State(initialValue: initialSelection)
        _edited = State(initialValue: initialSelection.flatMap { review.drafts[$0] })
    }

    private var instruments: [BondTermsReviewInstrument] {
        BondTermsReviewInstrument.scoped(Array(bonds), today: review.today, requestedIDs: requestedIDs,
            preferredID: initialSelection, draftIDs: Set(review.drafts.keys))
    }
    private func needsReview(_ instrument: BondTermsReviewInstrument) -> Bool {
        if let reportRange { return !instrument.reviewIssues(from: reportRange.lowerBound).isEmpty }
        return instrument.needsReview
    }
    private var visibleBonds: [BondEntity] { instruments.map(\.representative) }
    private var selectedIDs: [UUID] { instruments.filter { selected.contains($0.isin) }.map { $0.representative.id } }
    private var focusedPurchases: [BondEntity] { instruments.first { $0.purchases.contains { $0.id == focused } }?.purchases ?? [] }
    private var dirty: Bool { edited != focused.flatMap { review.drafts[$0] } }
    private var canApply: Bool { !selected.isEmpty && !dirty }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Review Bond Terms").font(.title2)
                Spacer()
                Button("Close") { request(.close) }.keyboardShortcut(.cancelAction).disabled(busy || review.isWorking)
            }
            Text("Review each instrument once for all purchases. Successful changes are saved; instruments needing attention remain open.")
                .foregroundStyle(.secondary)
            if requestedIDs != nil {
                Text(reportRange.map { "Reviewing expected payments from \($0.lowerBound.rawValue) to \($0.upperBound.rawValue). Checks use this historical period." }
                    ?? "Reviewing instruments excluded from the past report. All report instruments start selected.")
                    .font(.caption).foregroundStyle(.orange)
            }
            HStack {
                Button("Select unresolved") { selected = Set(instruments.filter { needsReview($0) }.map(\.isin)) }
                Button("Collect missing terms") { request(.collectMissing) }
                Button("Refresh selected from ING") { request(.refresh) }
                Button("Enter terms manually") { request(.manual) }
                Spacer()
                Text("\(instruments.filter { needsReview($0) }.count) ISINs need review")
            }.disabled(busy || review.isWorking)
            DisclosureGroup("Market data for rebuilding approved floating forecasts") {
                MarketSnapshotPicker(context: $rebuildContext)
                Button("Rebuild selected approved forecasts") { rebuildForecasts() }
                    .disabled(rebuildContext == nil || selected.isEmpty || dirty || busy || review.isWorking)
            }
            if review.isWorking || busy { ProgressView() }
            if !message.isEmpty { Text(message).foregroundStyle(.orange).textSelection(.enabled) }
            if !review.errors.isEmpty {
                ScrollView {
                    VStack(alignment: .leading) {
                        ForEach(review.errors.keys.sorted(), id: \.self) { key in Text(key + ": " + (review.errors[key] ?? "")).foregroundStyle(.red).textSelection(.enabled) }
                    }.frame(maxWidth: .infinity, alignment: .leading)
                }.frame(maxHeight: 120)
            }
            HSplitView {
                List {
                    ForEach(instruments) { instrument in
                        let bond = instrument.representative
                        HStack {
                            Toggle("", isOn: Binding(get: { selected.contains(instrument.isin) }, set: {
                                if $0 { selected.insert(instrument.isin) } else { selected.remove(instrument.isin) }
                            })).toggleStyle(.checkbox).labelsHidden()
                            Button { focus(bond.id) } label: {
                                VStack(alignment: .leading) {
                                    Text(bond.name)
                                    Text(instrument.isin + " · \(instrument.purchases.count) purchases").font(.caption).foregroundStyle(.secondary)
                                    Text(needsReview(instrument) ? "Needs review" : "Ready").font(.caption).foregroundStyle(needsReview(instrument) ? .orange : .green)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(minWidth: 230, idealWidth: 280, maxWidth: 340)
                ScrollView { editor.padding() }.frame(minWidth: 500)
            }
            HStack {
                Button("Revert local edits") { refreshEditor(); message = "" }.disabled(!dirty || busy)
                Button("Reuse approved terms") { request(.reuseApproved) }.disabled(selected.isEmpty || busy || review.isWorking)
                Spacer()
                Button("Save draft and preview") { saveDraft() }.disabled(edited == nil || busy || review.isWorking)
                Button("Apply Selected ISINs (\(selected.count))") { confirmApproval = true }.disabled(!canApply || busy || review.isWorking)
            }
        }
        .padding().frame(minWidth: 960, minHeight: 720)
        .background(AppTheme.panelBackground)
        .interactiveDismissDisabled(dirty || busy || review.isWorking)
        .alert("Discard unsaved local edits?", isPresented: Binding(
            get: { navigation.pending != nil },
            set: { if !$0 { navigation.cancel() } }
        ), presenting: navigation.pending) { action in
            Button("Discard local edits and continue", role: .destructive) {
                navigation.cancel()
                refreshEditor(); message = ""
                perform(action)
            }
            Button("Keep editing", role: .cancel) { navigation.cancel() }
        } message: { _ in
            Text("Only unsaved changes in this editor will be discarded. Saved drafts, approved terms and financial history are kept.")
        }
        .confirmationDialog("Apply terms for \(selected.count) ISINs?", isPresented: $confirmApproval) {
            Button("Apply Terms") { apply() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apply each saved instrument draft to all purchases of its ISIN. Successful ISINs are saved; failed ones remain selected for correction. Trade inputs and recorded history stay unchanged. Automatic payments activate prospectively; past and earlier-today receipts are not recorded.")
        }
        .task {
            do {
                try await review.load()
                focused = initialSelection ?? visibleBonds.first?.id
                if let initialSelection, let group = instruments.first(where: { $0.purchases.contains { $0.id == initialSelection } }) {
                    focused = group.representative.id; selected = [group.isin]
                }
                if requestedIDs != nil { selected = Set(instruments.map(\.isin)) }
                refreshEditor()
            } catch { message = error.localizedDescription }
        }
    }
    @ViewBuilder private var editor: some View {
        if let reportRange, let instrument = instruments.first(where: { $0.purchases.contains { $0.id == focused } }) {
            VStack(alignment: .leading, spacing: 8) {
                Text(instrument.representative.name).font(.headline)
                Text("Historical report: " + reportRange.lowerBound.rawValue + " to " + reportRange.upperBound.rawValue).font(.caption)
                Text("Saved terms need attention").font(.callout).foregroundStyle(.secondary)
                ForEach(Array(instrument.reviewIssues(from: reportRange.lowerBound).enumerated()), id: \.offset) { _, issue in
                    Text(issue).foregroundStyle(.orange)
                }
                if edited == nil {
                    Button("Edit saved terms") { manualReview() }.disabled(busy || review.isWorking)
                    Text("Correct the missing or inconsistent terms, then save the draft and apply. Collection from ING is optional.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
        }
        if let draft = edited {
            VStack(alignment: .leading, spacing: 12) {
                Text(draft.baseline.name).font(.headline)
                Text("Current holding: coupon \(draft.baseline.rate)% · maturity \(Formatters.shortDate.string(from: draft.baseline.maturity))")
                Text("Shared instrument terms for \(focusedPurchases.count) purchases. Each purchase has its own preview below.").font(.caption)
                Text("Legacy date interpretation: " + draft.legacyDateZone).font(.caption).foregroundStyle(.secondary)
                BondTermsFields(terms: Binding(get: { edited?.proposed ?? draft.proposed }, set: { edited?.proposed = $0 }), resetID: editorRevision)
                if [.floating, .fixedToFloating].contains(draft.proposed.structure) {
                    MarketSnapshotPicker(context: Binding(get: { edited?.projectionContext }, set: { edited?.projectionContext = $0 })).id(editorRevision)
                }
                if let reportRange {
                    Divider()
                    Text("Historical payment preview").font(.headline)
                    purchasePreviewForReport(draft, range: reportRange)
                }
                Divider()
                Text("Preview from " + draft.previewDay.rawValue).font(.headline)
                if draft.previewDay != review.today { Text("The preview day changed. Save the draft to refresh its preview before applying.").foregroundStyle(.orange) }
                ForEach(focusedPurchases, id: \.objectID) { bond in
                    purchasePreview(bond, terms: draft.proposed, from: draft.previewDay)
                    Divider()
                }
            }.disabled(busy || review.isWorking)
        } else if reportRange == nil {
            Text("Select an instrument and collect missing terms, or enter them manually. Collection only runs when you request it.")
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
        }
    }
    @ViewBuilder private func purchasePreviewForReport(_ draft: BondTermsDraft, range: ClosedRange<MarketDay>) -> some View {
        ForEach(focusedPurchases, id: \.objectID) { bond in
            switch Result(catching: { try BondSchedule.preview(trade: BondTermsStore.trade(bond), terms: draft.proposed,
                from: range.lowerBound, context: draft.projectionContext) }) {
            case .success(let preview):
                if preview.assessment.supported {
                    ForEach(preview.payments.filter { range.contains($0.paymentDay) }, id: \.identity) { payment in
                        Text(payment.paymentDay.rawValue + " | " + (payment.kind == .interest ? "Coupon" : "Redemption") + " | "
                            + (Formatters.paymentCurrency.string(from: NSNumber(value: payment.amount)) ?? String(payment.amount)))
                    }
                } else { ForEach(preview.assessment.reasons, id: \.self) { Text($0).foregroundStyle(.orange) } }
            case .failure(let error): Text(error.localizedDescription).foregroundStyle(.red)
            }
        }
    }
    @ViewBuilder private func purchasePreview(_ bond: BondEntity, terms: BondTerms, from day: MarketDay) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(bond.depotBank + " · " + bond.parValueFormatted + " nominal · " + bond.acquisitionPriceFormatted + " cost").font(.headline)
            Text("Acquired: " + bond.acquisitionDateFormatted).font(.caption)
                switch Result(catching: { try BondSchedule.preview(trade: BondTermsStore.trade(bond), terms: terms, from: day, context: edited?.projectionContext) }) {
                case .success(let preview):
                    if preview.assessment.supported {
                        Text("Supported preview; approval is required.").foregroundStyle(.green)
                        ForEach(preview.assessment.warnings, id: \.self) { Text($0).foregroundStyle(.orange) }
                        if let date = preview.redemptionDay { Text("Redemption payment: " + date.rawValue) }
                        if let yield = preview.estimatedYTM { Text(String(format: "Estimated YTM at purchase: %.3f%%", yield)) }
                        ForEach(Array(preview.payments.enumerated()), id: \.offset) { _, payment in
                            HStack {
                                Text(payment.kind == .interest ? "Coupon" : "Redemption")
                                if let source = payment.rateSource, payment.kind == .interest {
                                    Text(source == .projected ? "Projected" : (source == .publishedFixing ? "Published fixing" : "Fixed")).font(.caption).foregroundStyle(.secondary)
                                }
                                Text(payment.paymentDay.rawValue)
                                Spacer()
                                Text(Formatters.paymentCurrency.string(from: NSNumber(value: payment.amount)) ?? String(payment.amount))
                            }
                        }
                    } else { ForEach(preview.assessment.reasons, id: \.self) { Text($0).foregroundStyle(.orange) } }
                case .failure(let error): Text(error.localizedDescription).foregroundStyle(.red)
                }
        }
    }
    private func request(_ action: BondTermsReviewNavigation.Action) {
        if let immediate = navigation.request(action, hasUnsavedChanges: dirty) { perform(immediate) }
    }
    private func perform(_ action: BondTermsReviewNavigation.Action) {
        switch action {
        case .close: dismiss()
        case .collectMissing: collect(refresh: false)
        case .refresh: collect(refresh: true)
        case .manual: manualReview()
        case .reuseApproved: apply(reuse: true)
        }
    }
    private func refreshEditor() {
        edited = focused.flatMap { review.drafts[$0] }
        editorRevision = UUID()
    }
    private func focus(_ id: UUID) {
        guard !dirty else { message = "Save or revert the current draft before switching holdings."; return }
        focused = id; refreshEditor()
    }
    private func collect(refresh: Bool) {
        let ids = selectedIDs.filter { id in refresh || (review.drafts[id] == nil && instruments.contains { $0.representative.id == id && needsReview($0) }) }
        guard !ids.isEmpty else { message = "Select ISINs without a draft, or use Refresh for a new collection."; return }
        Task { await review.collect(ids: Array(ids)); refreshEditor() }
    }
    private func manualReview() {
        guard !selected.isEmpty else { message = "Select at least one ISIN."; return }
        let ids = selectedIDs
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do { try await review.beginManualReview(ids: ids); if focused == nil { focused = ids.first }; refreshEditor() }
            catch { message = error.localizedDescription }
        }
    }
    private func saveDraft() {
        guard var draft = edited else { return }
        draft.previewDay = review.today; busy = true
        Task { @MainActor in
            defer { busy = false }
            do { try await review.edit(draft); refreshEditor(); message = "Draft saved. Review the updated payments, then apply selected terms when ready." }
            catch { message = error.localizedDescription }
        }
    }
    private func rebuildForecasts() {
        guard let context = rebuildContext else { return }
        let ids = selectedIDs; busy = true
        Task { @MainActor in
            defer { busy = false }
            do { finishApply(try await review.refreshForecasts(ids: ids, context: context, reportFrom: reportRange?.lowerBound)) }
            catch { message = error.localizedDescription }
        }
    }
    private func apply(reuse: Bool = false) {
        let ids = selectedIDs; busy = true
        Task { @MainActor in
            defer { busy = false }
            do {
                let report = try await (reuse ? review.reuseApproved(ids: ids, reportFrom: reportRange?.lowerBound) : review.apply(ids: ids, reportFrom: reportRange?.lowerBound))
                finishApply(report)
            } catch {
                if let report = review.lastApplyReport { finishApply(report) }
                else { message = error.localizedDescription }
            }
        }
    }
    private func finishApply(_ report: BondTermsApplyReport) {
        selected.subtract(report.appliedISINs)
        if focused.map({ report.appliedHoldingIDs.contains($0) }) == true {
            focused = instruments.first { selected.contains($0.isin) }?.representative.id
        }
        refreshEditor(); message = report.summary + " Financial history was preserved."
    }

}
