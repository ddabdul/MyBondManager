import XCTest
import SwiftUI
import Vision
@testable import MyBondManager

@MainActor
final class PastPaymentsViewTests: XCTestCase {
    func testNativeReportShowsExpectedTotalsAndRefreshesAfterSave() async throws {
        let store = try TestPortfolio.make()
        for cost in [99010.0, 98570.0] {
            let bond = try TestPortfolio.readyBond(in: store.viewContext, terms: BondTermsFixtures.fixed(),
                now: TestPortfolio.date("2026-10-18T12:00:00Z"), nominal: 100000, cost: cost)
            bond.name = "Historical fixture"
        }
        try store.viewContext.save()
        let root = PastPaymentsView(from: try MarketDay("2026-07-15"), through: try MarketDay("2026-07-15"),
            bank: "All", search: "", kind: nil, now: TestPortfolio.date("2026-10-18T12:00:00Z"))
            .environment(\.managedObjectContext, store.viewContext).preferredColorScheme(.dark)
            .padding().background(CashFlowStyle.background)
        let view = NSHostingView(rootView: root); view.appearance = NSAppearance(named: .darkAqua)
        let window = makeWindow(view)
        defer { window.orderOut(nil) }
        try await waitFor("3,375", in: view)
        let initial = try text(view)
        XCTAssertTrue(initial.contains("Download JSON"), initial)
        XCTAssertTrue(initial.contains("Historical fixture"), initial)
        XCTAssertTrue(initial.contains("15 Jul 2026"), initial)
        XCTAssertTrue(initial.contains("3,375"), initial)
        try await PortfolioTransaction.run(in: store) { context in
            for bond in try context.fetch(BondEntity.fetchRequest()) { bond.name = "Saved background change" }
        }
        try await waitFor("Saved background change", in: view)
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let attachment = XCTAttachment(data: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])),
            uniformTypeIdentifier: "public.png")
        attachment.name = "past-expected-payments"; attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Past payment report with JSON action") { $0.add(attachment) }
    }

    func testPastReportWorkflowShowsEligibilityScopeAndReturnsToUpcoming() async throws {
        let store = try TestPortfolio.make()
        let year = MarketDay(date: Date()).year + 1
        _ = try TestPortfolio.readyBond(in: store.viewContext,
            terms: BondTermsFixtures.fixed(maturity: "\(year)-01-15", next: "2026-07-15"), now: Date())
        try store.viewContext.save()
        let root = CashFlowView(selectedDepotBank: .constant("All"))
            .environment(\.managedObjectContext, store.viewContext).preferredColorScheme(.dark)
        let view = NSHostingView(rootView: root); view.appearance = NSAppearance(named: .darkAqua)
        let window = makeWindow(view)
        defer { window.orderOut(nil) }
        await Task.yield(); try await Task.sleep(nanoseconds: 200_000_000)
        func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
        try clickPastOption(in: view, window: window, label: "Past report")
        // Loaded totals identify the workflow; the dedicated report test verifies the export action.
        try await waitFor("Expected receipts", in: view)
        XCTAssertFalse(descendants(view).compactMap { $0 as? NSSegmentedControl }.contains { $0.segmentCount == 2 && $0.label(forSegment: 0) == "List" })
        try clickPastOption(in: view, window: window, label: "Upcoming")
        await Task.yield(); try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(descendants(view).compactMap { $0 as? NSSegmentedControl }.contains { $0.segmentCount == 2 && $0.label(forSegment: 0) == "List" })
    }

    func testExcludedReviewShowsHistoricalFailureDespiteCurrentReadinessAndOpensSavedTerms() async throws {
        let store = try TestPortfolio.make()
        let archived = try TestPortfolio.historicalOpeningBond(in: store.viewContext)
        archived.name = "Relevant review fixture"
        let other = TestPortfolio.bond(in: store.viewContext)
        other.name = "Unrelated active fixture"; other.isin = "DE0000000002"; other.depotBank = "Other"
        other.maturityDate = TestPortfolio.date("2030-01-15T00:00:00Z")
        try store.viewContext.save()
        let root = PastPaymentsView(from: try MarketDay("2025-06-01"), through: try MarketDay("2026-01-15"),
            bank: "Bank", search: "", kind: nil, now: TestPortfolio.date("2026-10-18T12:00:00Z"))
            .environment(\.managedObjectContext, store.viewContext).environment(\.portfolioContainer, store)
            .preferredColorScheme(.dark).padding().background(CashFlowStyle.background)
        let view = NSHostingView(rootView: root); view.appearance = NSAppearance(named: .darkAqua)
        let window = makeWindow(view)
        defer { window.orderOut(nil) }
        try await waitFor("Review", in: view)
        try clickPastOption(in: view, window: window, label: "Review")
        for _ in 0..<30 {
            await Task.yield(); try await Task.sleep(nanoseconds: 100_000_000)
            if window.sheets.first != nil { break }
        }
        let sheet = try XCTUnwrap(window.sheets.first)
        let content = try XCTUnwrap(sheet.contentView)
        try await waitFor("Relevant review fixture", in: content)
        let visible = try text(content)
        XCTAssertFalse(visible.contains("Unrelated active fixture"), visible)
        XCTAssertTrue(visible.contains("Reuse approved terms"), visible)
        XCTAssertTrue(visible.contains("1 ISINs need review"), visible)
        XCTAssertTrue(visible.contains("opening coupon"), visible)
        XCTAssertTrue(visible.contains("Edit saved terms"), visible)
        let approval = archived.termsData
        try clickPastOption(in: content, window: sheet, label: "Edit saved terms")
        try await waitFor("Accrual start", in: content)
        XCTAssertEqual(archived.termsData, approval)
        sheet.orderOut(nil)
    }

    private func clickPastOption(in view: NSView, window: NSWindow, label: String = "Past expected payments") throws {
        try NativeSnapshotTestSupport.click(label, in: view, window: window)
    }

    private func makeWindow<Content: View>(_ view: NSHostingView<Content>) -> NSWindow {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 900),
            styleMask: [.titled], backing: .buffered, defer: false)
        view.sizingOptions = []
        window.isReleasedWhenClosed = false; window.contentView = view; view.frame = NSRect(x: 0, y: 0, width: 1100, height: 900); window.makeKeyAndOrderFront(nil)
        return window
    }
    private func text(_ view: NSView) throws -> String { try NativeSnapshotTestSupport.text(in: view) }
    private func waitFor(_ expected: String, in view: NSView) async throws {
        for _ in 0..<20 {
            await Task.yield(); try await Task.sleep(nanoseconds: 100_000_000)
            if try text(view).contains(expected) { return }
        }
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let attachment = XCTAttachment(data: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])), uniformTypeIdentifier: "public.png")
        attachment.name = "report-layout-failure"; attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Report layout failure") { $0.add(attachment) }
        XCTFail("Expected visible text: \(expected); actual: \(try text(view))")
    }
}
