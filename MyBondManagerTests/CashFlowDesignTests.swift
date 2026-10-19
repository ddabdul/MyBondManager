import XCTest
import SwiftUI
import Vision
@testable import MyBondManager

@MainActor
final class CashFlowDesignTests: XCTestCase {
    func testListAndCalendarShowSameFullReceiptsAndListDisclosuresRevealPayments() async throws {
        let store = try TestPortfolio.make()
        for cost in [99010.0, 98570.0] {
            _ = try TestPortfolio.readyBond(in: store.viewContext, terms: BondTermsFixtures.fixed(),
                now: TestPortfolio.date("2026-10-18T12:00:00Z"), nominal: 100000, cost: cost)
        }
        let data = CashFlowCalendarData.build(bonds: try store.viewContext.fetch(BondEntity.fetchRequest()),
            from: try MarketDay("2027-01-15"), through: try MarketDay("2027-01-15"))
        let list = NSHostingView(rootView: CashFlowReceiptList(data: data).padding().background(CashFlowStyle.background).preferredColorScheme(.dark))
        let window = makeWindow(list)
        defer { window.orderOut(nil) }
        try await settle(list)
        var visible = try text(list)
        XCTAssertTrue(visible.contains("203,375"), visible)
        XCTAssertTrue(visible.contains("200,000"), visible)
        try click("2027", in: list, window: window)
        try await settle(list)
        try click("January", in: list, window: window)
        try await settle(list)
        visible = try text(list)
        XCTAssertTrue(visible.contains("100,000"), visible)
        XCTAssertTrue(visible.contains("Repayment"), visible)
        XCTAssertFalse(visible.contains("99,010"), visible)
        attach(list, name: "cash-flow-list-disclosed")
        let calendar = NSHostingView(rootView: CashFlowCalendarView(data: data, navigation: .constant(CashFlowCalendarNavigation()))
            .padding().background(CashFlowStyle.background).preferredColorScheme(.dark))
        calendar.sizingOptions = []; window.contentView = calendar; calendar.frame = NSRect(x: 0, y: 0, width: 1050, height: 800)
        try await settle(calendar)
        visible = try text(calendar)
        XCTAssertTrue(visible.contains("203,375"), visible)
        XCTAssertTrue(visible.contains("200,000"), visible)
        attach(calendar, name: "cash-flow-year-tiles-dark")
        var navigation = CashFlowCalendarNavigation(); navigation.level = .month; navigation.year = 2027; navigation.month = 1
        let month = NSHostingView(rootView: CashFlowCalendarView(data: data, navigation: .constant(navigation))
            .padding().background(CashFlowStyle.background).preferredColorScheme(.light))
        month.sizingOptions = []; window.contentView = month; month.frame = NSRect(x: 0, y: 0, width: 1050, height: 800)
        try await settle(month)
        visible = try text(month)
        XCTAssertTrue(visible.contains("4 payments"), visible)
        attach(month, name: "cash-flow-month-light")
    }

    func testLongExclusionsHaveBoundedScrollableDetails() async throws {
        let exclusions = (0..<40).map { CashFlowCalendarData.Exclusion(id: UUID(), name: "Excluded holding \($0)",
            reason: "A confirmed first-coupon date is required before this payment can be calculated.") }
        let root = VStack(alignment: .leading, spacing: 12) {
            CashFlowExclusionNotice(exclusions: exclusions)
            Text("Payments remain visible")
            Spacer()
        }.padding().background(CashFlowStyle.background).preferredColorScheme(.light)
        let view = NSHostingView(rootView: root)
        let window = makeWindow(view)
        defer { window.orderOut(nil) }
        try await settle(view)
        try click("attention", in: view, window: window)
        try await settle(view)
        func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
        let scroll = try XCTUnwrap(descendants(view).compactMap { $0 as? NSScrollView }.first)
        XCTAssertLessThanOrEqual(scroll.frame.height, 230)
        XCTAssertGreaterThan(scroll.documentView?.frame.height ?? 0, scroll.frame.height)
        attach(view, name: "cash-flow-exclusions-scroll")
    }

    func testPaymentExplanationsRenderOnBothRowSurfaces() async throws {
        let day = try MarketDay("2027-01-15")
        let receipt = CalendarReceipt(id: "presentation", purchaseID: UUID(), isin: "TEST",
            name: "Projected payment", bank: "Fixture bank", acquisitionDay: day, nominal: 100000, cost: 99000,
            paymentDay: day, contractualDay: day, kind: .interest, amount: 1250,
            rateSource: .projected, conditional: true, warnings: ["Saved day-count assumption"])
        let root = VStack(alignment: .leading, spacing: 16) {
            CashFlowAssumptionsView(receipts: [receipt])
            ForEach([false, true], id: \.self) { alternating in
                CashFlowReceiptRow(day: day, name: alternating ? "Grey surface" : "Dark surface",
                    bank: receipt.bank, isin: receipt.isin, kind: "Coupon", amount: receipt.amount,
                    contractualDay: day, projected: true, conditional: true, warnings: receipt.warnings,
                    alternating: alternating)
            }
            Spacer()
        }.disclosureGroupStyle(ExpandedReceiptStyle()).padding()
            .background(CashFlowStyle.background).preferredColorScheme(.dark)
        let view = NSHostingView(rootView: root)
        let window = makeWindow(view)
        defer { window.orderOut(nil) }
        try await settle(view)
        let visible = try text(view)
        for label in ["Projected coupons", "Conditional payments", "Dark surface", "Grey surface",
                      "Projected using frozen market data", "Conditional payment; may be deferred", "Saved day-count assumption", "Fixture bank"] {
            XCTAssertTrue(visible.contains(label), visible)
        }
        attach(view, name: "cash-flow-explanations-both-surfaces")
    }

    // Render the same disclosure content expanded for visual inspection of both backgrounds.
    private struct ExpandedReceiptStyle: DisclosureGroupStyle {
        func makeBody(configuration: Configuration) -> some View {
            VStack(alignment: .leading, spacing: 8) {
                configuration.label
                configuration.content
            }
        }
    }

    private func makeWindow<Content: View>(_ view: NSHostingView<Content>) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1050, height: 800), styleMask: [.titled], backing: .buffered, defer: false)
        view.sizingOptions = []
        window.isReleasedWhenClosed = false; window.contentView = view; view.frame = NSRect(x: 0, y: 0, width: 1050, height: 800); window.orderFront(nil)
        return window
    }
    private func settle(_ view: NSView) async throws {
        await Task.yield(); try await Task.sleep(nanoseconds: 250_000_000); view.layoutSubtreeIfNeeded()
    }
    private func text(_ view: NSView) throws -> String { try NativeSnapshotTestSupport.text(in: view) }
    private func click(_ label: String, in view: NSView, window: NSWindow) throws {
        try NativeSnapshotTestSupport.click(label, in: view, window: window)
    }
    private func attach(_ view: NSView, name: String) {
        guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png"); attachment.name = name; attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: name) { $0.add(attachment) }
    }
}
