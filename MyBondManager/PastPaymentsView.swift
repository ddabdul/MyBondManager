import SwiftUI
import CoreData
import UniformTypeIdentifiers

struct PastPaymentsJSONDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    let data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws {
        guard let data = configuration.file.regularFileContents else { throw PortfolioError("The JSON file could not be read.") }
        self.data = data
    }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

struct PastPaymentsView: View {
    @Environment(\.managedObjectContext) private var context
    @Environment(\.portfolioContainer) private var portfolioContainer
    let from: MarketDay
    let through: MarketDay
    let bank: String
    let search: String
    let kind: BondPayment.Kind?
    var now: Date = Date()
    @State private var report: PastPaymentReport?
    @State private var document: PastPaymentsJSONDocument?
    @State private var loading = false
    @State private var loadError: String?
    @State private var exportError: String?
    @State private var exporting = false
    @State private var exportDocument: PastPaymentsJSONDocument?
    @State private var exportFilename = "expected-payments"
    @State private var revision = 0
    private struct ReviewSelection: Identifiable {
        let review: BondTermsReview
        let holdingIDs: Set<UUID>
        let range: ClosedRange<MarketDay>
        var id: ObjectIdentifier { ObjectIdentifier(review) }
    }
    @State private var reviewSelection: ReviewSelection?
    @State private var reviewError: String?
    @State private var showingScope = false

    private struct Request: Hashable {
        let from: MarketDay
        let through: MarketDay
        let bank: String
        let search: String
        let kind: String?
        let revision: Int
    }
    var body: some View {
        let coordinator = context.persistentStoreCoordinator
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("Bonds maturing today or later", systemImage: "line.3.horizontal.decrease.circle").font(.callout).foregroundStyle(.primary)
                Spacer()
                Button { showingScope = true } label: { Image(systemName: "info.circle") }
                    .buttonStyle(.plain).accessibilityLabel("About this report")
                    .popover(isPresented: $showingScope) {
                        Text("Expected payments reconstructed from current approved terms, not confirmation of bank receipt. Bonds that matured before today, deleted holdings and prior versions of terms are not included.")
                            .font(.callout).padding().frame(width: 320)
                    }
            }.foregroundStyle(.secondary)
            if loading {
                ProgressView("Preparing expected payments…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if let error = loadError {
                ContentUnavailableView("Report unavailable", systemImage: "exclamationmark.triangle", description: Text(error))
            } else if let report {
                ViewThatFits(in: .horizontal) {
                    HStack {
                        CashFlowTotalsView(coupons: report.coupons, repayments: report.redemptions)
                        Spacer(minLength: 16)
                        exportButton(report)
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        CashFlowTotalsView(coupons: report.coupons, repayments: report.redemptions)
                        exportButton(report)
                    }
                }
                Text("Expected receipts from saved terms; not confirmation of bank receipt.").font(.caption).foregroundStyle(.secondary)
                if !report.excludedHoldings.isEmpty {
                    CashFlowExclusionNotice(exclusions: report.excludedHoldings, review: { openReview(report) })
                }
                if report.payments.isEmpty {
                    ContentUnavailableView("No expected payments in this period", systemImage: "calendar",
                        description: Text("Change the dates or filters. Review any excluded holdings before treating the report as complete."))
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(report.payments.enumerated()), id: \.element.id) { index, payment in
                                CashFlowReceiptRow(day: payment.paymentDay, name: payment.name, bank: payment.bank, isin: payment.isin,
                                    kind: payment.type == .coupon ? "Coupon" : "Repayment", amount: payment.amount,
                                    contractualDay: payment.contractualDay, projected: payment.rateSource == .projected,
                                    conditional: payment.conditional, warnings: payment.warnings, alternating: !index.isMultiple(of: 2))
                            }
                        }.padding(2)
                    }
                }
            }
        }.padding(.horizontal)
        .task(id: Request(from: from, through: through, bank: bank, search: search, kind: kind?.rawValue, revision: revision)) {
            await load()
        }
        .onReceive(NotificationCenter.default.publisher(for: .NSManagedObjectContextDidSave).map { note in
            guard let saved = note.object as? NSManagedObjectContext, let coordinator,
                  saved.persistentStoreCoordinator === coordinator else { return false }
            return [NSInsertedObjectsKey, NSUpdatedObjectsKey, NSDeletedObjectsKey].contains { key in
                (note.userInfo?[key] as? Set<NSManagedObject>)?.contains { $0.entity.name == "BondEntity" } == true
            }
        }.receive(on: RunLoop.main)) { changed in if changed { revision += 1 } }
        .sheet(item: $reviewSelection, onDismiss: { revision += 1 }) { selection in
            BondTermsReviewView(review: selection.review, requestedIDs: selection.holdingIDs, reportRange: selection.range)
        }
        .alert("Review unavailable", isPresented: Binding(get: { reviewError != nil }, set: { if !$0 { reviewError = nil } })) {
            Button("OK", role: .cancel) { reviewError = nil }
        } message: { Text(reviewError ?? "") }
        .fileExporter(isPresented: $exporting, document: exportDocument, contentType: .json,
            defaultFilename: exportFilename) { result in
            exportDocument = nil
            if case .failure(let error) = result, (error as? CocoaError)?.code != .userCancelled {
                exportError = error.localizedDescription
            }
        }
        .alert("JSON export failed", isPresented: Binding(get: { exportError != nil }, set: { if !$0 { exportError = nil } })) {
            Button("OK", role: .cancel) { exportError = nil }
        } message: { Text(exportError ?? "") }
    }

    private func exportButton(_ report: PastPaymentReport) -> some View {
        Button("Download JSON", systemImage: "square.and.arrow.down") {
            exportDocument = document
            exportFilename = "expected-payments-\(report.from.rawValue)-to-\(report.through.rawValue)"
            exporting = true
        }.disabled(document == nil).fixedSize()
    }
    private func openReview(_ report: PastPaymentReport) {
        guard let portfolioContainer else { reviewError = "Portfolio store is unavailable."; return }
        reviewSelection = ReviewSelection(review: BondTermsReview(container: portfolioContainer),
            holdingIDs: Set(report.excludedHoldings.map(\.id)), range: report.from...report.through)
    }

    @MainActor
    private func load() async {
        loading = true; report = nil; document = nil; loadError = nil
        do {
            guard !context.hasChanges else { throw PortfolioError("Save pending portfolio changes before preparing the report.") }
            guard let coordinator = context.persistentStoreCoordinator else { throw PortfolioError("The portfolio store is unavailable.") }
            let background = NSManagedObjectContext(concurrencyType: .privateQueueConcurrencyType)
            background.persistentStoreCoordinator = coordinator
            let result = try await background.perform {
                let report = try PastPaymentReport.build(bonds: background.fetch(BondEntity.fetchRequest()),
                    from: from, through: through, bank: bank, search: search, kind: kind, now: now)
                return (report, try report.json())
            }
            guard !Task.isCancelled else { return }
            report = result.0; document = PastPaymentsJSONDocument(data: result.1); loading = false
        } catch {
            guard !Task.isCancelled else { return }
            loadError = error.localizedDescription; loading = false
        }
    }
}
