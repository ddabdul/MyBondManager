import XCTest
import CoreData
@testable import MyBondManager

@MainActor
final class LaunchNotifierTests: XCTestCase {
    func testMaturityAndCouponAlert() async throws {
        let container = try TestPortfolio.make()
        let context = container.viewContext
        let matured = TestPortfolio.bond(in: context)
        matured.name = "UnitTestBond"
        matured.maturityDate = TestPortfolio.date("2026-10-13T00:00:00Z")
        matured.couponRate = 2.5
        let coupon = TestPortfolio.bond(in: context, cost: 480, par: 500)
        coupon.name = "CouponBond"
        coupon.couponRate = 4
        coupon.maturityDate = TestPortfolio.date("2027-10-14T00:00:00Z")
        try CashFlowGenerator(context: context).regenerateCashFlows(for: matured)
        try CashFlowGenerator(context: context).regenerateCashFlows(for: coupon)
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
