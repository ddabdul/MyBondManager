import SwiftUI

private struct PaymentCalendarSyncKey: EnvironmentKey {
    static let defaultValue: PaymentCalendarSync? = nil
}
extension EnvironmentValues {
    var paymentCalendarSync: PaymentCalendarSync? {
        get { self[PaymentCalendarSyncKey.self] }
        set { self[PaymentCalendarSyncKey.self] = newValue }
    }
}

struct PaymentCalendarButton: View {
    @ObservedObject var sync: PaymentCalendarSync
    @State private var showingSettings = false
    var body: some View {
        Button { showingSettings = true } label: {
            Label("iPhone alerts", systemImage: sync.errorMessage != nil ? "exclamationmark.triangle" : "bell")
                .foregroundStyle(sync.errorMessage != nil ? Color.orange : Color.primary)
        }
        .help(sync.errorMessage ?? "Sync expected payment reminders to iCloud Calendar")
        .sheet(isPresented: $showingSettings) { PaymentCalendarSettingsView(sync: sync) }
    }
}

struct PaymentCalendarSettingsView: View {
    @ObservedObject var sync: PaymentCalendarSync
    @Environment(\.dismiss) private var dismiss
    @State private var selectedSource = ""
    private var busy: Bool { sync.isSyncing || sync.isConnecting }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Payment alerts on iPhone").font(.title2).fontWeight(.semibold)
                Spacer()
                Button("Close") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            Text("Sync expected coupons and redemptions to a dedicated Bond payments calendar. iCloud delivers the event alerts on your iPhone, even when this Mac is off.")
                .fixedSize(horizontal: false, vertical: true)
            GroupBox("Calendar account") {
                VStack(alignment: .leading, spacing: 12) {
                    if !sync.hasAccess {
                        Text("Calendar access lets MyBondManager update its existing events without creating duplicates. It only changes its marked payment events in its dedicated calendar.")
                        Button("Allow Calendar access") { Task { await sync.refreshAccess(request: true); selectAccount() } }
                            .disabled(busy)
                    } else if sync.sources.isEmpty {
                        Text("No calendar account is available. Enable iCloud Calendar in System Settings, then refresh the accounts.")
                        Button("Refresh accounts") { Task { await sync.refreshAccess(); selectAccount() } }.disabled(busy)
                    } else {
                        Picker("Account", selection: $selectedSource) {
                            Text("Choose iCloud account").tag("")
                            ForEach(sync.sources) { source in Text(source.title).tag(source.id) }
                        }.disabled(sync.isEnabled || busy)
                        Text("Choose the iCloud account used on your iPhone. Enable Calendar in iCloud settings on both devices.")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
            }
            GroupBox("Alerts") {
                VStack(alignment: .leading, spacing: 12) {
                    Picker("Payment-day alert", selection: option(\.hour)) {
                        ForEach(0..<24) { hour in Text(String(format: "%02d:00", hour)).tag(hour) }
                    }
                    Toggle("Also remind me the day before", isOn: option(\.dayBefore))
                    Toggle("Include amounts in event titles", isOn: option(\.showAmounts))
                    Text("Alert times use this Mac’s time zone when synced (\(TimeZone.current.identifier)). Amounts and details are stored in your iCloud calendar. These reminders indicate payment is due; they do not confirm bank receipt.")
                        .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }.padding(8)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text(sync.isEnabled ? "Automatic sync is on" : "Automatic sync is off").fontWeight(.medium)
                if let date = sync.lastSync {
                    Text("Last synced \(date.formatted(date: .abbreviated, time: .shortened))")
                        .font(.caption).foregroundStyle(.secondary)
                }
                if sync.isEnabled {
                    Text("\(sync.eventCount) future payment events. \(sync.excludedCount) holdings excluded because their schedules need review.")
                        .font(.caption)
                }
                if let error = sync.errorMessage { Text(error).foregroundStyle(.orange).textSelection(.enabled) }
                Text("Updates publish when this app runs. Stopping sync leaves existing events and alerts in Calendar; delete the Bond payments calendar there to remove them.")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                if busy { ProgressView().controlSize(.small); Text(sync.isConnecting ? "Connecting…" : "Syncing…").font(.caption) }
                Spacer()
                if sync.isEnabled {
                    Button("Stop syncing") { sync.disable() }.disabled(busy)
                    Button("Sync now") { Task { await sync.syncNow() } }.disabled(busy)
                } else {
                    Button("Enable automatic sync") { Task { await sync.enable(sourceID: selectedSource) } }
                        .disabled(busy || !sync.hasAccess || selectedSource.isEmpty)
                }
            }
        }.padding(24).frame(width: 540).background(AppTheme.panelBackground)
        .task { await sync.refreshAccess(); selectAccount() }
    }
    private func option<Value>(_ keyPath: WritableKeyPath<PaymentCalendarOptions, Value>) -> Binding<Value> {
        Binding(get: { sync.options[keyPath: keyPath] }, set: { value in
            var settings = sync.options; settings[keyPath: keyPath] = value; sync.updateOptions(settings)
        })
    }
    private func selectAccount() {
        if sync.sources.contains(where: { $0.id == sync.sourceID }) { selectedSource = sync.sourceID }
        else { selectedSource = sync.sources.first { $0.title.localizedCaseInsensitiveContains("iCloud") }?.id ?? "" }
    }
}
