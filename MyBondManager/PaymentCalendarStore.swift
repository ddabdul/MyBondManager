import Foundation
import EventKit

struct PaymentCalendarSource: Identifiable, Sendable {
    let id: String
    let title: String
}

protocol PaymentCalendarStore: Sendable {
    func access(request: Bool) async throws -> Bool
    func sources() async throws -> [PaymentCalendarSource]
    func calendarExists(_ id: String, sourceID: String) async -> Bool
    func createCalendar(sourceID: String) async throws -> String
    func synchronize(calendarID: String, desired: [PaymentCalendarEvent], from day: MarketDay) async throws -> Int
}

actor EventKitPaymentCalendarStore: PaymentCalendarStore {
    private let store = EKEventStore()

    func access(request: Bool) async throws -> Bool {
        if EKEventStore.authorizationStatus(for: .event) == .fullAccess { return true }
        return request ? try await store.requestFullAccessToEvents() : false
    }
    func sources() throws -> [PaymentCalendarSource] {
        try requireAccess()
        // CalDAV includes iCloud. The user chooses their iCloud account; never fall back to a local calendar.
        return store.sources.filter { $0.sourceType == .calDAV }
            .map { PaymentCalendarSource(id: $0.sourceIdentifier, title: $0.title) }
            .sorted { ($0.title, $0.id) < ($1.title, $1.id) }
    }
    func calendarExists(_ id: String, sourceID: String) -> Bool {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess,
              let calendar = store.calendar(withIdentifier: id) else { return false }
        return calendar.source.sourceIdentifier == sourceID && calendar.allowsContentModifications
    }
    func createCalendar(sourceID: String) throws -> String {
        try requireAccess()
        guard let source = store.sources.first(where: { $0.sourceIdentifier == sourceID && $0.sourceType == .calDAV }) else {
            throw PortfolioError("The selected iCloud account is unavailable. Enable iCloud Calendar in System Settings and choose the account again.")
        }
        let calendar = EKCalendar(for: .event, eventStore: store)
        calendar.title = "Bond payments"; calendar.source = source
        do { try store.saveCalendar(calendar, commit: true) }
        catch { store.reset(); throw error }
        return calendar.calendarIdentifier
    }

    func synchronize(calendarID: String, desired: [PaymentCalendarEvent], from day: MarketDay) throws -> Int {
        try requireAccess()
        guard let calendar = store.calendar(withIdentifier: calendarID), calendar.allowsContentModifications,
              calendar.source.sourceType == .calDAV else {
            throw PortfolioError("The Bond payments calendar is unavailable or read-only. Stop syncing, then enable it again to reconnect.")
        }
        var nativeEvents: [String: EKEvent] = [:]
        // EventKit truncates queries longer than four years. Use three-year windows for the full supported schedule.
        var cursor = day.instant.addingTimeInterval(-86400)
        let end = try MarketDay("2200-01-02").instant
        while cursor < end {
            guard let advanced = MarketDay.calendar.date(byAdding: .year, value: 3, to: cursor) else {
                throw PortfolioError("Cannot determine the calendar query window.")
            }
            let next = min(advanced, end)
            let predicate = store.predicateForEvents(withStart: cursor, end: next, calendars: [calendar])
            for event in store.events(matching: predicate) {
                guard Self.ownedKey(event.url) != nil else { continue }
                nativeEvents[event.calendarItemIdentifier] = event
            }
            cursor = next
        }
        let existing = nativeEvents.values.compactMap { event -> PaymentCalendarEntry? in
            guard let owned = Self.ownedKey(event.url) else { return nil }
            return PaymentCalendarEntry(identifier: event.calendarItemIdentifier,
                event: PaymentCalendarEvent(key: owned.key, day: owned.day, title: event.title ?? "", notes: event.notes ?? "",
                    start: event.startDate, end: event.endDate, alarms: (event.alarms ?? []).compactMap(\.absoluteDate).sorted(),
                    allDay: event.isAllDay))
        }.sorted { $0.identifier < $1.identifier }
        let changes = PaymentCalendarChanges(desired: desired, existing: existing, from: day)
        guard !changes.upserts.isEmpty || !changes.removals.isEmpty else { return desired.count }
        do {
            for update in changes.upserts {
                let event = update.identifier.flatMap { nativeEvents[$0] } ?? EKEvent(eventStore: store)
                let value = update.event
                guard let url = URL(string: PaymentCalendarEvent.urlPrefix + value.key) else {
                    throw PortfolioError("Cannot create the payment event identity.")
                }
                event.calendar = calendar; event.url = url; event.title = value.title; event.notes = value.notes
                event.isAllDay = true; event.timeZone = nil; event.startDate = value.start; event.endDate = value.end
                event.alarms = value.alarms.map { EKAlarm(absoluteDate: $0) }
                event.availability = .free
                try store.save(event, span: .thisEvent, commit: false)
            }
            for id in changes.removals {
                if let event = nativeEvents[id] { try store.remove(event, span: .thisEvent, commit: false) }
            }
            try store.commit()
        } catch { store.reset(); throw error }
        return desired.count
    }

    static func ownedKey(_ url: URL?) -> (key: String, day: MarketDay)? {
        guard let url, url.absoluteString.hasPrefix(PaymentCalendarEvent.urlPrefix) else { return nil }
        let key = String(url.absoluteString.dropFirst(PaymentCalendarEvent.urlPrefix.count))
        let parts = key.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty, let day = try? MarketDay(String(parts[1])) else { return nil }
        return (key, day)
    }
    private func requireAccess() throws {
        guard EKEventStore.authorizationStatus(for: .event) == .fullAccess else {
            throw PortfolioError("Calendar access is required. Allow MyBondManager in System Settings > Privacy & Security > Calendars, then retry.")
        }
    }
}
