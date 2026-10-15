import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class LaunchNotifierTests: XCTestCase {
    func testMaturityAndCouponAlert() async throws {
        let container = try TestPortfolio.make()
        let context = container.viewContext
        var maturityTerms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2026-10-13", next: "2026-10-13")
        maturityTerms.accrualStart = try MarketDay("2025-10-13")
        maturityTerms.checkpointObservedOn = try MarketDay("2026-02-01"); maturityTerms.couponRate = 2.5
        let matured = try TestPortfolio.readyBond(in: context, terms: maturityTerms, now: TestPortfolio.date("2026-10-01T12:00:00Z"))
        matured.name = "UnitTestBond"
        var couponTerms = try BondTermsFixtures.fixed(frequency: 1, maturity: "2027-10-14", next: "2026-10-14")
        couponTerms.accrualStart = try MarketDay("2025-10-14"); couponTerms.couponRate = 4
        let coupon = try TestPortfolio.readyBond(in: context, terms: couponTerms,
            now: TestPortfolio.date("2026-10-01T12:00:00Z"), nominal: 500, cost: 480)
        coupon.name = "CouponBond"
        try context.save()
        let suite = "LaunchNotifierTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(TestPortfolio.date("2026-10-12T00:00:00Z"), forKey: "lastLaunchDate")
        let notifier = LaunchNotifier(defaults: defaults)
        await notifier.processLaunch(in: container, now: TestPortfolio.date("2026-10-14T12:00:00Z"))
        let message = try XCTUnwrap(notifier.alertMessage)
        XCTAssertTrue(message.contains("UnitTestBond"))
        XCTAssertTrue(message.contains("CouponBond"))
    }
}
