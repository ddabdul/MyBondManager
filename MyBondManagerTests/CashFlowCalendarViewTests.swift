import XCTest
import SwiftUI
import AppKit
import Vision
@testable import MyBondManager

@MainActor
final class CashFlowCalendarViewTests: XCTestCase {
    func testYearsArrangeSideBySideAndReflowAtNarrowWidth() async throws {
        let receipts = try (2026...2031).map { year in
            let day = try MarketDay("\(year)-11-04")
            return CalendarReceipt(id: String(year), purchaseID: UUID(), isin: "EXAMPLE", name: "Example bond",
                bank: "Bank", acquisitionDay: day, nominal: 100000, cost: 99000,
                paymentDay: day, contractualDay: day, kind: .maturity, amount: 100000,
                rateSource: nil, conditional: false, warnings: [])
        }
        let state = CalendarScreenState(year: 2026)
        let root = CalendarScreenFixture(state: state,
            data: CashFlowCalendarData(receipts: receipts, exclusions: [])).preferredColorScheme(.dark)
        let view = NSHostingView(rootView: root)
        view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 980),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        func positions(_ name: String) async throws -> [Int: CGRect] {
            await Task.yield(); try await Task.sleep(nanoseconds: 250_000_000)
            view.layoutSubtreeIfNeeded()
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let request = VNRecognizeTextRequest()
            try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = name; attachment.lifetime = .keepAlways
            XCTContext.runActivity(named: name) { $0.add(attachment) }
            var result: [Int: CGRect] = [:]
            for observation in request.results ?? [] {
                if let text = observation.topCandidates(1).first?.string,
                   let year = Int(text), (2026...2031).contains(year) {
                    result[year] = observation.boundingBox
                }
            }
            return result
        }
        let wide = try await positions("year-tiles-wide")
        let first = try XCTUnwrap(wide[2026]), second = try XCTUnwrap(wide[2027])
        XCTAssertEqual(first.midY, second.midY, accuracy: 0.02, "Consecutive years must share a tile row")
        XCTAssertGreaterThan(second.minX, first.maxX, "Year tiles must sit side by side")
        XCTAssertEqual(wide.count, 6, "Six years should fit without scrolling in the wide overview")
        window.setContentSize(NSSize(width: 360, height: 980)); view.frame.size.width = 360
        let narrow = try await positions("year-tiles-narrow")
        let narrowFirst = try XCTUnwrap(narrow[2026]), narrowSecond = try XCTUnwrap(narrow[2027])
        XCTAssertEqual(narrowFirst.minX, narrowSecond.minX, accuracy: 0.02)
        XCTAssertGreaterThan(narrowFirst.midY, narrowSecond.midY, "Narrow windows must stack the tiles")
    }

    func testCalendarModeAndPeriodSurviveSwitchingMainTabs() async throws {
        let store = try TestPortfolio.make()
        let root = MainTabView().environment(\.managedObjectContext, store.viewContext)
            .environment(\.portfolioContainer, store).environmentObject(LaunchNotifier())
            .environmentObject(ETFPriceUpdater(container: store, fetchPrice: { _ in 100 }))
        let view = NSHostingView(rootView: root)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1200, height: 900),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.orderFront(nil)
        defer { window.orderOut(nil) }
        func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
        func switchControl(_ count: Int, to segment: Int) async throws {
            let control = try XCTUnwrap(descendants(view).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == count && (count != 2 || $0.label(forSegment: 0) == "List") })
            control.selectedSegment = segment; control.sendAction(control.action, to: control.target)
            await Task.yield(); try await Task.sleep(nanoseconds: 150_000_000); view.layoutSubtreeIfNeeded()
        }
        await Task.yield(); try await Task.sleep(nanoseconds: 150_000_000)
        try await switchControl(5, to: 1)
        try await switchControl(2, to: 1)
        try await switchControl(3, to: 2)
        try await switchControl(5, to: 0)
        try await switchControl(5, to: 1)
        let restored = descendants(view).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == 3 }
        XCTAssertEqual(restored?.selectedSegment, 2, "Returning to Cash Flows must retain Calendar/Month")
    }

    func testNativeCalendarLevelsRenderActualTotalsAndPaymentDetails() async throws {
        let store = try TestPortfolio.make()
        let year = MarketDay(date: Date()).year + 1
        let terms = try BondTermsFixtures.fixed(maturity: "\(year)-01-15", next: "2026-07-15")
        for cost in [99010.0, 98570.0] {
            let bond = try TestPortfolio.readyBond(in: store.viewContext, terms: terms,
                now: Date(), nominal: 100000, cost: cost)
            bond.name = "Example EUR income bond"
        }
        try store.viewContext.save()
        let data = CashFlowCalendarData.build(bonds: try store.viewContext.fetch(BondEntity.fetchRequest()),
            from: MarketDay(date: Date()), through: try MarketDay("2199-12-31"))
        let state = CalendarScreenState(year: year)
        let root = CalendarScreenFixture(state: state, data: data).preferredColorScheme(.dark)
        let view = NSHostingView(rootView: root)
        view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 980),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil) }
        func settle() async throws {
            await Task.yield(); try await Task.sleep(nanoseconds: 250_000_000); view.layoutSubtreeIfNeeded()
        }
        func screenshot(_ name: String, of content: NSView) throws -> [String] {
            let bitmap = try XCTUnwrap(content.bitmapImageRepForCachingDisplay(in: content.bounds))
            content.cacheDisplay(in: content.bounds, to: bitmap)
            let request = VNRecognizeTextRequest()
            try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
            let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
            attachment.name = name; attachment.lifetime = .keepAlways
            XCTContext.runActivity(named: name) { $0.add(attachment) }
            return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }
        }
        func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
        try await settle()
        let overview = try screenshot("calendar-years", of: view).joined(separator: " ")
        XCTAssertTrue(overview.contains("200,000"), overview)
        XCTAssertFalse(overview.contains("January"), "Years overview must show only year summaries")
        XCTAssertFalse(overview.contains("December"), "Month calendars belong inside the selected Year view")
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let recognition = VNRecognizeTextRequest()
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([recognition])
        let yearLabel = try XCTUnwrap(recognition.results?.first { $0.topCandidates(1).first?.string == String(year) })
        let box = yearLabel.boundingBox
        let point = view.convert(NSPoint(x: box.midX * view.bounds.width,
            y: (view.isFlipped ? 1 - box.midY : box.midY) * view.bounds.height), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            let event = try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1))
            window.sendEvent(event)
        }
        try await settle()
        XCTAssertEqual(state.navigation.level, .year, "Clicking a year summary must open Year view")
        XCTAssertEqual(state.navigation.year, year)
        let control = try XCTUnwrap(descendants(view).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == 3 })
        for (index, name) in [(1, "calendar-year"), (2, "calendar-month")] {
            control.selectedSegment = index; control.sendAction(control.action, to: control.target)
            try await settle()
            let text = try screenshot(name, of: view).joined(separator: " ")
            XCTAssertTrue(text.contains("200,000"), text)
            if index == 1 { XCTAssertTrue(text.contains("January"), "Year view must retain the twelve months") }
        }
        state.navigation.selectedDay = try XCTUnwrap(data.receipts.first {
            $0.paymentDay.year == year && $0.paymentDay.month == 1
        }).paymentDay
        try await settle()
        let popover = try XCTUnwrap(NSApp.windows.first { $0.isVisible && $0.className.contains("Popover") })
        let text = try screenshot("calendar-payment-details", of: XCTUnwrap(popover.contentView)).joined(separator: " ")
        XCTAssertTrue(text.contains("Example EUR income bond"), text)
        XCTAssertTrue(text.contains("2 purchases"), text)
        window.setContentSize(NSSize(width: 600, height: 900)); view.frame.size.width = 600
        state.navigation.selectedDay = nil
        try await settle()
        state.navigation.level = .year
        try await settle()
        _ = try screenshot("calendar-narrow-year", of: view)
    }
}

@MainActor
private final class CalendarScreenState: ObservableObject {
    @Published var navigation: CashFlowCalendarNavigation
    init(year: Int) { navigation = CashFlowCalendarNavigation(year: year, month: 1) }
}
private struct CalendarScreenFixture: View {
    @ObservedObject var state: CalendarScreenState
    let data: CashFlowCalendarData
    var body: some View {
        CashFlowCalendarView(data: data, navigation: $state.navigation).padding().background(AppTheme.panelBackground)
    }
}
