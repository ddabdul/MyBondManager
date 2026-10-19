import AppKit
import CoreData

@MainActor
final class PaymentCalendarSync: ObservableObject {
    @Published private(set) var isEnabled: Bool
    @Published private(set) var isSyncing = false
    @Published private(set) var isConnecting = false
    @Published private(set) var hasAccess = false
    @Published private(set) var sources: [PaymentCalendarSource] = []
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var eventCount = 0
    @Published private(set) var excludedCount = 0
    @Published private(set) var options: PaymentCalendarOptions
    private let container: NSPersistentContainer
    private let backend: any PaymentCalendarStore
    private let defaults: UserDefaults
    private let now: () -> Date
    private var observers: [NSObjectProtocol] = []
    private var pending: Task<Void, Never>?
    private var needsAnotherPass = false
    private var observedDay: MarketDay
    private var timer: Timer?
    private let prefix = "paymentCalendar."
    private var calendarID: String? { defaults.string(forKey: prefix + "calendarID") }
    var sourceID: String { defaults.string(forKey: prefix + "sourceID") ?? "" }

    init(container: NSPersistentContainer, backend: any PaymentCalendarStore = EventKitPaymentCalendarStore(),
         defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.container = container; self.backend = backend; self.defaults = defaults; self.now = now
        isEnabled = defaults.bool(forKey: prefix + "enabled")
        observedDay = MarketDay(date: now())
        var settings = PaymentCalendarOptions()
        settings.hour = defaults.object(forKey: prefix + "hour") as? Int ?? 9
        settings.dayBefore = defaults.bool(forKey: prefix + "dayBefore")
        settings.showAmounts = defaults.object(forKey: prefix + "showAmounts") as? Bool ?? true
        options = settings; lastSync = defaults.object(forKey: prefix + "lastSync") as? Date
    }
    deinit {
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        pending?.cancel(); timer?.invalidate()
    }

    func start() {
        guard observers.isEmpty else { return }
        let coordinator = container.persistentStoreCoordinator
        observers.append(NotificationCenter.default.addObserver(forName: .NSManagedObjectContextDidSave,
            object: nil, queue: nil) { [weak self] note in
            guard let context = note.object as? NSManagedObjectContext,
                  context.persistentStoreCoordinator === coordinator else { return }
            Task { @MainActor [weak self] in self?.schedule() }
        })
        // Calendar changes include our own commits; using them as triggers causes a sync feedback loop.
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification,
            object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor [weak self] in self?.schedule() }
        })
        timer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                let today = MarketDay(date: self.now())
                if today != self.observedDay { self.observedDay = today; self.schedule() }
            }
        }
        schedule()
    }

    func refreshAccess(request: Bool = false) async {
        do {
            hasAccess = try await backend.access(request: request)
            sources = hasAccess ? try await backend.sources() : []
            if request && !hasAccess {
                throw PortfolioError("Calendar access was not granted. Allow MyBondManager in System Settings > Privacy & Security > Calendars, then retry.")
            }
        } catch { errorMessage = error.localizedDescription }
    }
    func enable(sourceID: String) async {
        guard !isSyncing && !isConnecting else { return }
        isConnecting = true
        defer { isConnecting = false }
        await refreshAccess(request: true)
        guard hasAccess else { return }
        guard sources.contains(where: { $0.id == sourceID }) else {
            errorMessage = "Choose the iCloud account used on your iPhone."; return
        }
        do {
            let exists: Bool
            if let id = calendarID, self.sourceID == sourceID { exists = await backend.calendarExists(id, sourceID: sourceID) }
            else { exists = false }
            if !exists {
                let id = try await backend.createCalendar(sourceID: sourceID)
                defaults.set(id, forKey: prefix + "calendarID")
            }
            defaults.set(sourceID, forKey: prefix + "sourceID")
            defaults.set(true, forKey: prefix + "enabled"); isEnabled = true
            await syncNow()
        } catch { errorMessage = error.localizedDescription }
    }
    func disable() {
        defaults.set(false, forKey: prefix + "enabled"); isEnabled = false
        pending?.cancel(); needsAnotherPass = false
    }
    func updateOptions(_ value: PaymentCalendarOptions) {
        options = value
        defaults.set(value.hour, forKey: prefix + "hour")
        defaults.set(value.dayBefore, forKey: prefix + "dayBefore")
        defaults.set(value.showAmounts, forKey: prefix + "showAmounts")
        schedule()
    }
    func schedule() {
        guard isEnabled else { return }
        if isSyncing { needsAnotherPass = true; return }
        pending?.cancel()
        pending = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 500_000_000) } catch { return }
            guard !Task.isCancelled else { return }
            await self?.syncNow()
        }
    }
    func syncNow() async {
        guard isEnabled else { return }
        guard !isSyncing else { needsAnotherPass = true; return }
        isSyncing = true
        defer {
            isSyncing = false
            if needsAnotherPass { needsAnotherPass = false; schedule() }
        }
        do {
            guard let id = calendarID else { throw PortfolioError("Enable calendar sync and choose an iCloud account first.") }
            guard try await backend.access(request: false) else {
                hasAccess = false
                throw PortfolioError("Calendar access is unavailable. Allow MyBondManager in System Settings > Privacy & Security > Calendars, then retry.")
            }
            hasAccess = true
            let day = MarketDay(date: now())
            let context = container.newBackgroundContext()
            let data = try await context.perform {
                let bonds = try context.fetch(BondEntity.fetchRequest())
                // Abort before touching calendars if a saved profile cannot be decoded or calculated.
                for bond in bonds { _ = try BondTermsStore.validatedPreview(bond, from: day) }
                return CashFlowCalendarData.build(bonds: bonds, from: day, through: try MarketDay("2199-12-31"))
            }
            let desired = try PaymentCalendarProjection.make(data: data, options: options, timeZone: .current)
            guard isEnabled else { return }
            eventCount = try await backend.synchronize(calendarID: id, desired: desired, from: day)
            excludedCount = data.exclusions.count; lastSync = now(); errorMessage = nil
            defaults.set(lastSync, forKey: prefix + "lastSync")
        } catch { errorMessage = error.localizedDescription }
    }
}
