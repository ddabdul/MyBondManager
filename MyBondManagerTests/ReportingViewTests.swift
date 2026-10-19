import XCTest
import SwiftUI
@testable import MyBondManager

@MainActor
final class ReportingViewTests: XCTestCase {
    func testReportsRenderAtWideAndNarrowWidthsAndRefreshAfterSave() async throws {
        let store = try TestPortfolio.make()
        let suite = "ReportingViewTests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        let now = TestPortfolio.date("2026-10-19T12:00:00Z")
        var terms = try BondTermsFixtures.fixed()
        terms.callable = true
        let bond = try TestPortfolio.readyBond(in: store.viewContext, terms: terms, now: now, nominal: 100000, cost: 99000)
        bond.issuer = "Reporting fixture issuer"
        try store.viewContext.save()
        let view = NSHostingView(rootView: ReportingView(selectedDepotBank: .constant("All"), today: MarketDay(date: now), preferences: preferences)
            .environment(\.managedObjectContext, store.viewContext).preferredColorScheme(.dark))
        view.sizingOptions = []
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 1100, height: 1100), styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.orderFront(nil)
        defer { window.orderOut(nil) }
        for width in [1100.0, 540.0] {
            window.setContentSize(NSSize(width: width, height: 1100)); view.frame = NSRect(x: 0, y: 0, width: width, height: 1100)
            await Task.yield(); try await Task.sleep(nanoseconds: 300_000_000); view.layoutSubtreeIfNeeded()
            let visible = try NativeSnapshotTestSupport.text(in: view)
            for label in ["My Reporting", "Expected Interest by Year", "Maturity Schedule", "Issuer Breakdown", "Reporting fixture issuer", "100,000"] {
                XCTAssertTrue(visible.contains(label), visible)
            }
            let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
            view.cacheDisplay(in: view.bounds, to: bitmap)
            let attachment = XCTAttachment(data: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])), uniformTypeIdentifier: "public.png")
            attachment.name = "reporting-\(Int(width))"; attachment.lifetime = .keepAlways
            XCTContext.runActivity(named: "Reporting layout") { $0.add(attachment) }
        }
        try NativeSnapshotTestSupport.click("Forecast details", in: view, window: window)
        await Task.yield(); try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(try NativeSnapshotTestSupport.text(in: view).contains("Early redemption is not modeled"))
        bond.issuer = "Updated report issuer"; try store.viewContext.save()
        await Task.yield(); try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(try NativeSnapshotTestSupport.text(in: view).contains("Updated report issuer"))
        func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
        let target = try XCTUnwrap(descendants(view).compactMap { $0 as? NSTextField }.first { $0.isEditable })
        func enter(_ value: String) async throws {
            target.selectText(nil)
            let editor = try XCTUnwrap(target.currentEditor() as? NSTextView)
            editor.insertText(value, replacementRange: NSRange(location: 0, length: editor.string.utf16.count))
            window.makeFirstResponder(nil)
            await Task.yield(); try await Task.sleep(nanoseconds: 200_000_000)
        }
        try await enter("225000")
        XCTAssertEqual(preferences.double(forKey: "reporting.annualInterestTarget"), 225000)
        try await enter("-1")
        XCTAssertTrue(try NativeSnapshotTestSupport.text(in: view).contains("Enter a non-negative amount"))
        try await enter("not an amount")
        XCTAssertEqual(preferences.double(forKey: "reporting.annualInterestTarget"), -1)
        try await enter("225000")
        view.rootView = ReportingView(selectedDepotBank: .constant("All"), today: MarketDay(date: now), preferences: preferences)
            .environment(\.managedObjectContext, store.viewContext).preferredColorScheme(.dark)
        await Task.yield(); try await Task.sleep(nanoseconds: 200_000_000)
        XCTAssertTrue(try NativeSnapshotTestSupport.text(in: view).contains("225,000"))

    }
}
