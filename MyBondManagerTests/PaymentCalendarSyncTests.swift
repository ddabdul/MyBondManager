import XCTest
import EventKit
@testable import MyBondManager

@MainActor
final class PaymentCalendarSyncTests: XCTestCase {
    func testEnableReusesCalendarAndAutomaticSaveUpdatesAndRemovesFutureEvents() async throws {
        let container = try TestPortfolio.make()
        let day = TestPortfolio.date("2026-10-18T12:00:00Z")
        let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(),
            now: day, nominal: 100000, cost: 99000)
        try container.viewContext.save()
        let suite = "PaymentCalendarSyncTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = RecordingPaymentCalendarStore()
        let sync = PaymentCalendarSync(container: container, backend: backend, defaults: defaults, now: { day })
        sync.start()
        await sync.enable(sourceID: "icloud")
        XCTAssertTrue(sync.isEnabled)
        XCTAssertNil(sync.errorMessage)
        let first = await backend.events
        XCTAssertEqual(first.count, 1)
        bond.name = "Renamed bond"; try container.viewContext.save()
        for _ in 0..<40 {
            if await backend.events.first?.title.contains("Renamed bond") == true { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let updated = await backend.events
        XCTAssertTrue(updated.first?.title.contains("Renamed bond") == true)
        XCTAssertEqual(first.first?.key, updated.first?.key)
        container.viewContext.delete(bond); try container.viewContext.save()
        for _ in 0..<40 {
            if await backend.events.isEmpty { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let removed = await backend.events
        XCTAssertTrue(removed.isEmpty)
        sync.disable()
        await sync.enable(sourceID: "icloud")
        let creations = await backend.creations
        XCTAssertEqual(creations, 1, "Re-enabling must reuse its dedicated calendar")
        sync.disable()
    }

    func testCalendarNotificationsFromOwnWritesDoNotCauseRepeatedSync() async throws {
        let container = try TestPortfolio.make()
        let day = TestPortfolio.date("2026-10-18T12:00:00Z")
        let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: day)
        try container.viewContext.save()
        let suite = "PaymentCalendarSyncTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = RecordingPaymentCalendarStore()
        await backend.echoCalendarNotifications()
        let sync = PaymentCalendarSync(container: container, backend: backend, defaults: defaults, now: { day })
        sync.start(); await sync.enable(sourceID: "icloud")
        try await Task.sleep(nanoseconds: 1_300_000_000)
        let initialWrites = await backend.writes
        XCTAssertEqual(initialWrites, 1, "A sync's own Calendar notification must not start another sync")
        bond.name = "Changed after idle"; try container.viewContext.save()
        for _ in 0..<40 {
            if await backend.events.first?.title.contains("Changed after idle") == true { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        try await Task.sleep(nanoseconds: 700_000_000)
        let writesAfterEdit = await backend.writes
        let updated = await backend.events
        XCTAssertEqual(writesAfterEdit, 2, "A real portfolio save must sync once and settle again")
        XCTAssertTrue(updated.first?.title.contains("Changed after idle") == true)
        sync.disable()
    }

    func testRepeatedEnableCannotCreateTwoCalendars() async throws {
        let container = try TestPortfolio.make()
        let suite = "PaymentCalendarSyncTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = RecordingPaymentCalendarStore()
        let sync = PaymentCalendarSync(container: container, backend: backend, defaults: defaults)
        async let first: Void = sync.enable(sourceID: "icloud")
        async let second: Void = sync.enable(sourceID: "icloud")
        _ = await (first, second)
        let creations = await backend.creations
        XCTAssertEqual(creations, 1)
        sync.disable()
    }

    func testBackgroundSaveTriggersSyncAndCorruptProfileDoesNotClearPublishedEvents() async throws {
        let container = try TestPortfolio.make()
        let day = TestPortfolio.date("2026-10-18T12:00:00Z")
        let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: day)
        try container.viewContext.save()
        let id = bond.objectID
        let suite = "PaymentCalendarSyncTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = RecordingPaymentCalendarStore()
        let sync = PaymentCalendarSync(container: container, backend: backend, defaults: defaults, now: { day })
        sync.start(); await sync.enable(sourceID: "icloud")
        try await PortfolioTransaction.run(in: container) { context in
            try context.existingObject(with: id).setValue("Background update", forKey: "name")
        }
        for _ in 0..<40 {
            if await backend.events.first?.title.contains("Background update") == true { break }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let published = await backend.events
        XCTAssertTrue(published.first?.title.contains("Background update") == true)
        try await PortfolioTransaction.run(in: container) { context in
            try context.existingObject(with: id).setValue(Data([0]), forKey: "termsData")
        }
        await sync.syncNow()
        XCTAssertNotNil(sync.errorMessage)
        let retained = await backend.events
        XCTAssertEqual(retained, published)
        sync.disable()
    }

    func testDeniedPermissionDoesNotEnableOrWriteAndFailedSyncRetainsEvents() async throws {
        let container = try TestPortfolio.make()
        let suite = "PaymentCalendarSyncTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let backend = RecordingPaymentCalendarStore()
        await backend.denyAccess()
        let sync = PaymentCalendarSync(container: container, backend: backend, defaults: defaults)
        await sync.enable(sourceID: "icloud")
        XCTAssertFalse(sync.isEnabled)
        XCTAssertNotNil(sync.errorMessage)
        let writes = await backend.writes
        XCTAssertEqual(writes, 0)
        await backend.allowAccess()
        await sync.enable(sourceID: "icloud")
        await backend.failWrites()
        await sync.syncNow()
        XCTAssertNotNil(sync.errorMessage)
        XCTAssertTrue(sync.isEnabled, "A transient failure must remain retryable")
        let failure = sync.errorMessage
        await sync.refreshAccess()
        XCTAssertEqual(sync.errorMessage, failure, "Opening settings must preserve the failed sync explanation")
        sync.disable()
    }
}

actor RecordingPaymentCalendarStore: PaymentCalendarStore {
    private(set) var events: [PaymentCalendarEvent] = []
    private(set) var creations = 0
    private(set) var writes = 0
    private var allowed = true
    private var failing = false
    private var echoesCalendarNotifications = false
    func echoCalendarNotifications() { echoesCalendarNotifications = true }
    func denyAccess() { allowed = false }
    func allowAccess() { allowed = true }
    func failWrites() { failing = true }
    func access(request: Bool) -> Bool { allowed }
    func sources() -> [PaymentCalendarSource] { [.init(id: "icloud", title: "iCloud")] }
    func calendarExists(_ id: String, sourceID: String) -> Bool { id == "owned" && sourceID == "icloud" }
    func createCalendar(sourceID: String) async throws -> String {
        try await Task.sleep(nanoseconds: 30_000_000)
        guard sourceID == "icloud" else { throw PortfolioError("Missing source") }
        creations += 1; return "owned"
    }
    func synchronize(calendarID: String, desired: [PaymentCalendarEvent], from day: MarketDay) throws -> Int {
        if failing { throw PortfolioError("Calendar temporarily unavailable") }
        writes += 1; events = desired
        if echoesCalendarNotifications { NotificationCenter.default.post(name: .EKEventStoreChanged, object: nil) }
        return desired.count
    }
}
