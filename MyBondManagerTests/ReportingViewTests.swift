import XCTest
import SwiftUI
@testable import MyBondManager

@MainActor
final class ReportingViewTests: XCTestCase {
    func testIssuerHeadersReorderVisibleRowsInBothDirections() async throws {
        let store = try TestPortfolio.make()
        let suite = "ReportingSortTests." + UUID().uuidString
        let preferences = UserDefaults(suiteName: suite)!
        defer { preferences.removePersistentDomain(forName: suite) }
        for (name, nominal, date) in [("Alpha Company", 100000.0, "2029-01-19"),
                                      ("Bravo Company", 300000.0, "2027-01-19"),
                                      ("Charlie Company", 200000.0, "2030-01-19")] {
            let bond = TestPortfolio.bond(in: store.viewContext, par: nominal)
            bond.issuer = name; bond.termsLegacyDateZone = "Europe/Berlin"
            bond.maturityDate = try MarketDay(date).instant
        }
        try store.viewContext.save()
        let view = NSHostingView(rootView: ReportingView(selectedDepotBank: .constant("All"), today: try MarketDay("2026-10-19"), preferences: preferences)
            .environment(\.managedObjectContext, store.viewContext).preferredColorScheme(.dark))
        view.sizingOptions = []
        let rect = NSRect(x: 0, y: 0, width: 540, height: 1400)
        let window = NSWindow(contentRect: rect, styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; view.frame = rect; window.orderFront(nil)
        defer { window.orderOut(nil) }
        func settle() async throws { await Task.yield(); try await Task.sleep(nanoseconds: 200_000_000); view.layoutSubtreeIfNeeded() }
        func order() throws -> [String] {
            let names = ["Alpha Company", "Bravo Company", "Charlie Company"]
            return try NativeSnapshotTestSupport.observations(in: view).compactMap { observation -> (String, CGFloat)? in
                guard let value = observation.topCandidates(1).first?.string,
                      let name = names.first(where: { value.contains($0) }) else { return nil }
                return (name, observation.boundingBox.midY)
            }.sorted { $0.1 > $1.1 }.map { $0.0 }
        }
        func clickHeader(_ label: String) async throws {
            let boxes = try NativeSnapshotTestSupport.observations(in: view).compactMap { observation -> CGRect? in
                guard let value = observation.topCandidates(1).first, let range = value.string.range(of: label) else { return nil }
                return try value.boundingBox(for: range)?.boundingBox
            }
            let box = try XCTUnwrap(boxes.min { $0.midY < $1.midY })
            let point = view.convert(NSPoint(x: box.midX * view.bounds.width, y: (view.isFlipped ? 1 - box.midY : box.midY) * view.bounds.height), to: nil)
            for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
                window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                    windowNumber: window.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
            }
            try await settle()
        }
        try await settle()
        XCTAssertEqual(try order(), ["Bravo Company", "Charlie Company", "Alpha Company"])
        for (header, firstOrder, secondOrder) in [
            ("Issuer", ["Alpha Company", "Bravo Company", "Charlie Company"], ["Charlie Company", "Bravo Company", "Alpha Company"]),
            ("Principal", ["Bravo Company", "Charlie Company", "Alpha Company"], ["Alpha Company", "Charlie Company", "Bravo Company"]),
            ("Avg. Maturity", ["Charlie Company", "Alpha Company", "Bravo Company"], ["Bravo Company", "Alpha Company", "Charlie Company"])
        ] {
            try await clickHeader(header); XCTAssertEqual(try order(), firstOrder)
            try await clickHeader(header); XCTAssertEqual(try order(), secondOrder)
        }
    }

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
            for label in ["My Reporting", "Expected Interest by Year", "Maturity Schedule", "Issuer Breakdown", "Avg. Maturity", "Reporting fixture issuer", "100,000"] {
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
