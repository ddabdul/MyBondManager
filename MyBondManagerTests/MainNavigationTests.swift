import XCTest
import SwiftUI
import AppKit
@testable import MyBondManager

@MainActor
final class MainNavigationTests: XCTestCase {
    func testNavigationStaysInsideWindowAtSamePositionWhenSwitchingTabs() async throws {
        let container = try TestPortfolio.make()
        for index in 0..<82 {
            var terms = try BondTermsFixtures.fixed(maturity: "2035-01-15", next: "2026-07-15")
            terms.isin = String(format: "DE%010d", index)
            let bond = try TestPortfolio.readyBond(in: container.viewContext, terms: terms,
                now: TestPortfolio.date("2026-10-17T12:00:00Z"), nominal: 100000, cost: 99000)
            bond.name = "Long issuer name International Investment Finance Luxembourg SA \(index)"
        }
        try container.viewContext.save()
        let root = MainTabView()
            .environment(\.managedObjectContext, container.viewContext)
            .environment(\.portfolioContainer, container)
            .environmentObject(LaunchNotifier())
            .environmentObject(ETFPriceUpdater(container: container, fetchPrice: { _ in 100 }))
            .preferredColorScheme(.dark)
        let view = NSHostingView(rootView: root)
        let rect = NSRect(x: 0, y: 0, width: 1200, height: 800)
        let window = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.orderOut(nil) }
        view.frame = rect
        window.orderFront(nil)
        func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
        func settle() async throws {
            await Task.yield(); try await Task.sleep(nanoseconds: 100_000_000)
            view.layoutSubtreeIfNeeded()
        }
        try await settle()
        let control = try XCTUnwrap(descendants(view).compactMap { $0 as? NSSegmentedControl }.first { $0.segmentCount == 4 })
        for width in [900.0, 1100.0, 1500.0] {
            window.setContentSize(NSSize(width: width, height: 800)); view.frame.size.width = width
            try await settle()
            var initialX: CGFloat?
            var initialY: CGFloat?
            for index in [0,1,2,3,0] {
                let started = Date()
                control.selectedSegment = index
                control.sendAction(control.action, to: control.target)
                try await settle()
                let frame = control.convert(control.bounds, to: view)
                print("NAVIGATION_FRAME elapsed=\(Date().timeIntervalSince(started)) segment=\(index) window=\(view.bounds) selector=\(frame)")
                XCTAssertGreaterThanOrEqual(frame.width, control.intrinsicContentSize.width)
                XCTAssertGreaterThanOrEqual(frame.minX, 12)
                XCTAssertLessThanOrEqual(frame.maxX, view.bounds.maxX - 12)
                if width == 1500, index == 1 {
                    let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
                    view.cacheDisplay(in: view.bounds, to: bitmap)
                    let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                    let attachment = XCTAttachment(data: png, uniformTypeIdentifier: "public.png")
                    attachment.name = "stable-navigation-cashflows"; attachment.lifetime = .keepAlways
                    XCTContext.runActivity(named: "Native navigation layout") { $0.add(attachment) }
                }
                if let initialX { XCTAssertEqual(frame.minX, initialX, accuracy: 0.01) }
                else { initialX = frame.minX }
                if let initialY { XCTAssertEqual(frame.minY, initialY, accuracy: 0.01) }
                else { initialY = frame.minY }
            }
        }
    }
}
