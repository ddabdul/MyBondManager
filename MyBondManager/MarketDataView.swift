import SwiftUI
import AppKit
import UniformTypeIdentifiers

struct MarketDataView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var snapshots: [MarketDataSnapshot] = []
    @State private var selectedID: String?
    @State private var tenor = 3
    @State private var message: String?
    @State private var refreshTask: Task<Void, Never>?
    @State private var depositURL = ""
    @State private var swapURL = ""
    @State private var historyURL = ""
    private let store = MarketDataStore()
    private var selected: MarketDataSnapshot? { snapshots.first { $0.id == selectedID } }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("EURIBOR Market Data").font(.title2.bold())
                Spacer()
                Button("Close") { refreshTask?.cancel(); dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Refresh or import dated inputs here. Bond forecasts change only when you explicitly adopt a snapshot in Review Terms.")
                .foregroundStyle(.secondary)
            HStack {
                Picker("Index", selection: $tenor) {
                    ForEach([1,3,6,12], id: \.self) { Text("EURIBOR \($0)M").tag($0) }
                }.frame(width: 220).disabled(refreshTask != nil)
                Button("Refresh source data", action: refresh).disabled(refreshTask != nil || ![3,6].contains(tenor))
                Button("Import dated inputs", action: importInputs).disabled(refreshTask != nil)
                if refreshTask != nil { ProgressView().controlSize(.small); Button("Cancel") { refreshTask?.cancel() } }
            }
            if ![3,6].contains(tenor) { Text("No automatic quote source for this tenor. Import matching decimal quotes and fixings.").foregroundStyle(.secondary) }
            DisclosureGroup("Source endpoints (HTTPS)") {
                TextField("Deposit quotes", text: $depositURL)
                TextField("Matching swap quotes", text: $swapURL)
                TextField("Published fixing history", text: $historyURL)
                Button("Save source endpoints", action: saveEndpoints).disabled(![3,6].contains(tenor))
            }.disabled(refreshTask != nil)
            if let message { Text(message).foregroundStyle(.orange).textSelection(.enabled) }
            HStack(alignment: .top, spacing: 16) {
                List(selection: $selectedID) {
                    ForEach(snapshots, id: \.id) { snapshot in
                        VStack(alignment: .leading) {
                            Text("EURIBOR \(snapshot.payload.quotes.indexTenorMonths)M · \(snapshot.payload.quotes.quoteDay.rawValue)")
                            Text(snapshot.payload.sourceName).font(.caption).foregroundStyle(.secondary)
                        }.tag(snapshot.id)
                    }
                }.frame(minWidth: 280)
                if let snapshot = selected {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Snapshot inspection").font(.headline)
                            Text("Quote date: \(snapshot.payload.quotes.quoteDay.rawValue)")
                            Text("Retrieved: \(snapshot.retrievedAt.formatted())")
                            Text("Coverage through: \(snapshot.calibration.lastCurveDay.rawValue)")
                            Text("Published observations: \(snapshot.payload.historicalFixings.count)")
                            Text("Deposit residual: \(snapshot.calibration.maxDepositResidual, format: .number.precision(.fractionLength(12)))")
                            Text("Maximum swap residual: \(snapshot.calibration.maxSwapResidual, format: .number.precision(.fractionLength(12)))")
                            Text("QuantLib \(snapshot.calibration.quantLibVersion) · single-curve projection")
                            Text(snapshot.id).font(.caption.monospaced()).textSelection(.enabled)
                            if let stale = try? MarketDataStore.isStale(quoteDay: snapshot.payload.quotes.quoteDay, on: MarketDay(date: Date())) {
                                Text(stale ? "Stale: more than two TARGET business days old." : "Within two TARGET business days.")
                                    .foregroundStyle(stale ? .orange : .secondary)
                            }
                            Text("Projection forwards are estimates. This curve does not model callable exercise or option value.")
                                .foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(4)
                    }
                } else { Text("Select a snapshot to inspect its dates and calibration.").foregroundStyle(.secondary).frame(maxWidth: .infinity) }
            }
        }.padding(20).frame(minWidth: 880, minHeight: 560)
            .onAppear { load(); loadEndpoints() }
            .onChange(of: tenor) { _, _ in loadEndpoints() }
            .onDisappear { refreshTask?.cancel() }
    }
    private func load() {
        do {
            snapshots = try store.list()
            if selectedID == nil { selectedID = snapshots.first?.id }
        } catch { message = error.localizedDescription }
    }
    private func loadEndpoints() {
        do {
            let source = try MarketDataSources.bundled()
            depositURL = UserDefaults.standard.string(forKey: "market.depositURL") ?? source.fixingQuotesURL.absoluteString
            swapURL = UserDefaults.standard.string(forKey: "market.swapURL.\(tenor)") ?? source.swapQuotesURLs[tenor]?.absoluteString ?? ""
            historyURL = UserDefaults.standard.string(forKey: "market.historyURL.\(tenor)") ?? source.historicalFixingURLs[tenor]?.absoluteString ?? ""
        } catch { message = error.localizedDescription }
    }
    private func configuredSources() throws -> MarketDataSources {
        guard let deposit = URL(string: depositURL), let swap = URL(string: swapURL), let history = URL(string: historyURL) else {
            throw MarketDataError("Enter valid HTTPS source endpoints.")
        }
        return try MarketDataSources(fixingQuotesURL: deposit, swapQuotesURLs: [tenor: swap], historicalFixingURLs: [tenor: history])
    }
    private func saveEndpoints() {
        do {
            _ = try configuredSources()
            UserDefaults.standard.set(depositURL, forKey: "market.depositURL")
            UserDefaults.standard.set(swapURL, forKey: "market.swapURL.\(tenor)")
            UserDefaults.standard.set(historyURL, forKey: "market.historyURL.\(tenor)")
            message = "Source endpoints saved. Existing snapshots and bond forecasts are unchanged."
        } catch { message = error.localizedDescription }
    }
    private func refresh() {
        guard refreshTask == nil else { return }
        do {
            let client = MarketDataClient(sources: try configuredSources()), index = tenor
            refreshTask = Task { @MainActor in
                defer { refreshTask = nil }
                do {
                    let payload = try await client.fetch(indexTenorMonths: index, pricingDay: MarketDay(date: Date()))
                    try Task.checkCancellation()
                    let saved = try store.save(payload, retrievedAt: Date())
                    load()
                    let current = snapshots.first { $0.id == selectedID }
                    if current == nil || current!.payload.quotes.quoteDay <= saved.payload.quotes.quoteDay { selectedID = saved.id }
                    message = "Source snapshot saved. Adopt it explicitly in Review Terms to rebuild bond forecasts."
                } catch is CancellationError { message = "Refresh cancelled; saved snapshots are available offline." }
                catch { message = error.localizedDescription }
            }
        } catch { message = error.localizedDescription }
    }
    private func importInputs() {
        let panel = NSOpenPanel(); panel.allowedContentTypes = [.json]; panel.allowsMultipleSelection = false
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let payload = try MarketDataClient.decodeImport(Data(contentsOf: url), pricingDay: MarketDay(date: Date()))
            let saved = try store.save(payload, retrievedAt: Date())
            load(); selectedID = saved.id
            message = "Dated inputs imported. Bond approvals and financial history are unchanged."
        } catch { message = error.localizedDescription }
    }
}
