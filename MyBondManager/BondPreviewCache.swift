import Foundation

final class BondPreviewCache: @unchecked Sendable {
    private struct Key: Hashable {
        let profile: Data
        let day: MarketDay
    }
    private let lock = NSLock()
    private var values: [Key: BondSchedulePreview] = [:]
    private var profiles: [Data: BondTermsStore.Profile] = [:]

    func profile(_ data: Data, decode: () throws -> BondTermsStore.Profile) rethrows -> BondTermsStore.Profile {
        if let saved = lock.withLock({ profiles[data] }) { return saved }
        let value = try decode()
        lock.withLock {
            if profiles.count >= 512 { profiles.removeAll(keepingCapacity: true) }
            profiles[data] = value
        }
        return value
    }


    func preview(profile: Data, from day: MarketDay, calculate: () throws -> BondSchedulePreview) rethrows -> BondSchedulePreview {
        // Saved profiles contain the terms, trade and frozen market inputs; the day selects the payment window.
        let key = Key(profile: profile, day: day)
        if let saved = lock.withLock({ values[key] }) { return saved }
        let value = try calculate()
        guard value.assessment.supported else { return value }
        lock.withLock {
            if values.count >= 512 { values.removeAll(keepingCapacity: true) }
            values[key] = value
        }
        return value
    }
}
