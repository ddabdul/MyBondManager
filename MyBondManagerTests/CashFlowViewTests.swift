import XCTest
import SwiftUI
import AppKit
import Vision
@testable import MyBondManager

@MainActor
final class CashFlowViewTests: XCTestCase {
    func testCashFlowTabShowsScheduledYearOnOpeningAndParentRefresh() async throws {
        let container = try TestPortfolio.make()
        let now = Date()
        let paymentYear = String(MarketDay.calendar.component(.year, from: now) + 1)
        let terms = try BondTermsFixtures.fixed(maturity: paymentYear + "-01-15", next: "2026-07-15")
        let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: terms,
            now: now, nominal: 100000, cost: 99000)
        XCTAssertTrue(BondTermsStore.isReady(bond))
        let end = try XCTUnwrap(MarketDay.calendar.date(byAdding: .year, value: 1, to: now))
        XCTAssertFalse(try BondEligibility.flows(bond, from: MarketDay(date: now),
                                                through: MarketDay(date: end)).isEmpty)
        try container.viewContext.save()
        let state = CashFlowScreenState()
        let root = CashFlowScreenFixture(state: state)
            .environment(\.managedObjectContext, container.viewContext)
        let view = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 800),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        window.orderFront(nil)
        defer { window.orderOut(nil) }
        func settle() async throws {
            await Task.yield(); try await Task.sleep(nanoseconds: 200_000_000)
            view.layoutSubtreeIfNeeded()
        }
        func visibleText() throws -> [String] {
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let request = VNRecognizeTextRequest()
            try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }
        func waitForYear(_ visible: Bool) async throws {
            for _ in 0..<10 {
                try await settle()
                if try visibleText().contains(paymentYear) == visible { return }
            }
            XCTFail("Expected scheduled year visibility: \(visible)")
        }
        try await waitForYear(true)
        XCTAssertTrue(try visibleText().contains(paymentYear), "The scheduled cash-flow year must be visible on opening")
        state.refresh += 1
        try await waitForYear(true)
        XCTAssertTrue(try visibleText().contains(paymentYear), "Parent updates must not reset the fetch to an empty predicate")
        state.bank = "Other bank"
        try await waitForYear(false)
        state.bank = "Bank"
        try await waitForYear(true)
        try CashFlowGenerator(context: container.viewContext).regenerateCashFlows(for: bond)
        try container.viewContext.save()
        try await waitForYear(true)

        func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
        let switcher = try XCTUnwrap(descendants(view).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == 2 })
        switcher.selectedSegment = 1; switcher.sendAction(switcher.action, to: switcher.target)
        try await settle()
        let calendarText = try visibleText()
        let calendarLevels = try XCTUnwrap(descendants(view).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == 3 })
        XCTAssertEqual(calendarLevels.selectedSegment, 0, "Calendar must open at the Years overview")
        XCTAssertTrue(calendarText.contains(paymentYear), "Calendar rendered text: \(calendarText)")
        switcher.selectedSegment = 0; switcher.sendAction(switcher.action, to: switcher.target)
        try await waitForYear(true)

        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
        attachment.name = "cash-flow-content-after-refresh"; attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Cash-flow payments remain visible") { $0.add(attachment) }
    }
}

@MainActor
private final class CashFlowScreenState: ObservableObject {
    @Published var bank = "All"
    @Published var refresh = 0
}
private struct CashFlowScreenFixture: View {
    @ObservedObject var state: CashFlowScreenState
    var body: some View {
        VStack {
            Text("Refresh \(state.refresh)")
            CashFlowView(selectedDepotBank: $state.bank)
        }
    }
}
