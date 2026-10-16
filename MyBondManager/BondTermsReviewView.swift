import SwiftUI
import CoreData

struct BondTermsReviewView: View {
    @ObservedObject var review: BondTermsReview
    var initialSelection: UUID? = nil
    var body: some View {
        BondTermsReviewContent(review: review, initialSelection: initialSelection)
            .environment(\.managedObjectContext, review.container.viewContext)
    }
}

private struct BondTermsReviewContent: View {
    @ObservedObject var review: BondTermsReview
    let initialSelection: UUID?
    @Environment(\.dismiss) private var dismiss
    @FetchRequest(sortDescriptors: [NSSortDescriptor(keyPath: \BondEntity.name, ascending: true)]) private var bonds: FetchedResults<BondEntity>
    @State private var selected: Set<UUID> = []
    @State private var focused: UUID?
    @State private var edited: BondTermsDraft?
    @State private var editorRevision = UUID()
    @State private var message = ""
    @State private var busy = false
    @State private var confirmApproval = false

    init(review: BondTermsReview, initialSelection: UUID?) {
        self.review = review; self.initialSelection = initialSelection
        _focused = State(initialValue: initialSelection)
        _edited = State(initialValue: initialSelection.flatMap { review.drafts[$0] })
    }

    private var visibleBonds: [BondEntity] { bonds.filter { BondEligibility.isActive($0, on: review.today) || $0.id == initialSelection } }
    private var dirty: Bool { edited != focused.flatMap { review.drafts[$0] } }
    private var canApply: Bool {
        !selected.isEmpty && !dirty && selected.allSatisfy { id in
            guard let draft = review.drafts[id], draft.previewDay == review.today else { return false }
            do { return try review.preview(draft).assessment.supported } catch { return false }
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Review Bond Terms").font(.title2)
                Spacer()
                Button("Close") {
                    if dirty { message = "Save the draft or revert your edits before closing." } else { dismiss() }
                }.keyboardShortcut(.cancelAction).disabled(busy || review.isWorking)
            }
            Text("Review existing holdings once, at your pace. Saved drafts resume here. Only approved payments enter forecasts; financial history is preserved and automatic recording starts prospectively.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Select unresolved") { selected = Set(visibleBonds.filter { !BondTermsStore.isReady($0) }.map(\.id)) }
                Button("Collect missing terms") { collect(refresh: false) }
                Button("Refresh selected from ING") { collect(refresh: true) }
                Button("Enter terms manually") { manualReview() }
                Spacer()
                Text("\(visibleBonds.filter { !BondTermsStore.isReady($0) }.count) holdings need review")
            }.disabled(busy || review.isWorking || dirty)
            if review.isWorking || busy { ProgressView() }
            if !message.isEmpty { Text(message).foregroundStyle(.orange).textSelection(.enabled) }
            ForEach(review.errors.keys.sorted(), id: \.self) { key in Text(key + ": " + (review.errors[key] ?? "")).foregroundStyle(.red) }
            HSplitView {
                List {
                    ForEach(visibleBonds, id: \.objectID) { bond in
                        HStack {
                            Toggle("", isOn: Binding(get: { selected.contains(bond.id) }, set: {
                                if $0 { selected.insert(bond.id) } else { selected.remove(bond.id) }
                            })).toggleStyle(.checkbox).labelsHidden()
                            Button { focus(bond.id) } label: {
                                VStack(alignment: .leading) {
                                    Text(bond.name)
                                    Text(bond.isin + " · " + bond.depotBank).font(.caption).foregroundStyle(.secondary)
                                    Text(BondTermsStore.isReady(bond) ? "Ready" : "Needs review").font(.caption).foregroundStyle(BondTermsStore.isReady(bond) ? .green : .orange)
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }
                }.frame(minWidth: 230, idealWidth: 280, maxWidth: 340)
                ScrollView { editor.padding() }.frame(minWidth: 500)
            }
            HStack {
                Button("Revert local edits") { refreshEditor() }.disabled(!dirty || busy)
                Spacer()
                Button("Save draft and preview") { saveDraft() }.disabled(edited == nil || busy || review.isWorking)
                Button("Apply Selected Terms (\(selected.count))") { confirmApproval = true }.disabled(!canApply || busy || review.isWorking)
            }
        }
        .padding().frame(minWidth: 960, minHeight: 720)
        .background(AppTheme.panelBackground)
        .interactiveDismissDisabled(dirty || busy || review.isWorking)
        .confirmationDialog("Apply reviewed terms to \(selected.count) holdings?", isPresented: $confirmApproval) {
            Button("Apply Terms") { apply() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Apply the saved dated previews, including any contractual maturity changes shown in the review. Trade inputs and recorded history stay unchanged. Automatic payments activate from this local approval; past or earlier-today receipts are not recorded.")
        }
        .task {
            do {
                try await review.load()
                focused = initialSelection ?? visibleBonds.first?.id
                if let initialSelection { selected = [initialSelection] }
                refreshEditor()
            } catch { message = error.localizedDescription }
        }
    }
    @ViewBuilder private var editor: some View {
        if let draft = edited {
            VStack(alignment: .leading, spacing: 12) {
                Text(draft.baseline.name).font(.headline)
                Text("Current holding: coupon \(draft.baseline.rate)% · maturity \(Formatters.shortDate.string(from: draft.baseline.maturity))")
                Text("Trade: \(draft.trade.nominal) nominal · \(draft.trade.cost) cost · acquired \(draft.trade.acquisitionDay.rawValue) · \(draft.trade.bank)").font(.caption)
                Text("Legacy date interpretation: " + draft.legacyDateZone).font(.caption).foregroundStyle(.secondary)
                BondTermsFields(terms: Binding(get: { edited?.proposed ?? draft.proposed }, set: { edited?.proposed = $0 }), resetID: editorRevision)
                Divider()
                Text("Preview from " + draft.previewDay.rawValue).font(.headline)
                if draft.previewDay != review.today { Text("The preview day changed. Save the draft to refresh its preview before applying.").foregroundStyle(.orange) }
                switch Result(catching: { try review.preview(draft) }) {
                case .success(let preview):
                    if preview.assessment.supported {
                        Text("Supported preview; approval is required.").foregroundStyle(.green)
                        if let date = preview.redemptionDay { Text("Redemption payment: " + date.rawValue) }
                        if let yield = preview.estimatedYTM { Text(String(format: "Estimated YTM: %.3f%%", yield)) }
                        ForEach(Array(preview.payments.enumerated()), id: \.offset) { _, payment in
                            HStack {
                                Text(payment.kind == .interest ? "Coupon" : "Redemption")
                                Text(payment.paymentDay.rawValue)
                                Spacer()
                                Text(Formatters.paymentCurrency.string(from: NSNumber(value: payment.amount)) ?? String(payment.amount))
                            }
                        }
                    } else { ForEach(preview.assessment.reasons, id: \.self) { Text($0).foregroundStyle(.orange) } }
                case .failure(let error): Text(error.localizedDescription).foregroundStyle(.red)
                }
            }.disabled(busy || review.isWorking)
        } else {
            Text("Select holdings and collect missing terms, or enter them manually. Collection only runs when you request it.")
                .foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
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
        let ids = selected.filter { id in refresh || (review.drafts[id] == nil && !bonds.contains { $0.id == id && BondTermsStore.isReady($0) }) }
        guard !ids.isEmpty else { message = "Select holdings without a draft, or use Refresh for a new collection."; return }
        Task { await review.collect(ids: Array(ids)); refreshEditor() }
    }
    private func manualReview() {
        guard !selected.isEmpty else { message = "Select at least one holding."; return }
        busy = true
        Task { @MainActor in
            defer { busy = false }
            do { try await review.beginManualReview(ids: Array(selected)); if focused == nil { focused = selected.first }; refreshEditor() }
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
    private func apply() {
        let ids = Array(selected); busy = true
        Task { @MainActor in
            defer { busy = false }
            do { try await review.apply(ids: ids); refreshEditor(); message = "Terms applied. History was preserved." }
            catch { message = error.localizedDescription }
        }
    }
}
