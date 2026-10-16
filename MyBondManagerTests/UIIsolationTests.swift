import XCTest
import SwiftUI
import AppKit
import CoreData
@testable import MyBondManager

@MainActor
final class UIIsolationTests: XCTestCase {
    func testHostedAppUsesOnlyMemory() {
        let app = BondPortfolioManagerApp()
        XCTAssertEqual(app.persistenceController.container.persistentStoreCoordinator.persistentStores.first?.type,
                       NSInMemoryStoreType)
    }
    func testPortfolioRendersWithInjectedMemoryStore() throws {
        let container = try TestPortfolio.make()
        let bond = TestPortfolio.bond(in: container.viewContext)
        try CashFlowGenerator(context: container.viewContext).regenerateCashFlows(for: bond)
        try container.viewContext.save()
        let root = MainTabView()
            .environment(\.managedObjectContext, container.viewContext)
            .environment(\.portfolioContainer, container)
            .environmentObject(LaunchNotifier())
            .environmentObject(ETFPriceUpdater(container: container, fetchPrice: { _ in 120 }))
            .preferredColorScheme(.dark)
        let view = NSHostingView(rootView: root)
        view.frame = NSRect(x: 0, y: 0, width: 1400, height: 900)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let image = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let preview = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        defer { try? FileManager.default.removeItem(at: preview) }
        try image.write(to: preview)
        XCTAssertGreaterThan(image.count, 1000)
    }
    func testNativeReviewAndPortfolioRenderWithInjectedMixedHoldingsWithoutCollection() async throws {
        let container = try TestPortfolio.make()
        let now = TestPortfolio.date("2026-10-15T12:00:00Z")
        let regular = try TestPortfolio.readyBond(in: container.viewContext, terms: BondTermsFixtures.fixed(), now: now)
        regular.name = "Regular semiannual"
        var zero = try BondTermsFixtures.fixed(); zero.structure = .zero; zero.couponRate = 0
        let zeroBond = try TestPortfolio.readyBond(in: container.viewContext, terms: zero, now: now); zeroBond.name = "Zero coupon"
        var callable = try BondTermsFixtures.fixed(frequency: 1, maturity: "2027-01-01", next: "2027-01-01")
        callable.accrualStart = try MarketDay("2026-01-01"); callable.callable = true
        let callBond = try TestPortfolio.readyBond(in: container.viewContext, terms: callable, now: now); callBond.name = "Callable regular"
        let unresolved = TestPortfolio.bond(in: container.viewContext); unresolved.name = "Needs review"
        _ = TestPortfolio.holding(in: container.viewContext)
        try container.viewContext.save()
        var fetches = 0
        let review = BondTermsReview(container: container, fetch: { _ in fetches += 1; throw PortfolioError("Unexpected collection") }, now: { now })
        try await review.beginManualReview(ids: [regular.id])
        let portfolio = MainTabView()
            .environment(\.managedObjectContext, container.viewContext).environment(\.portfolioContainer, container)
            .environmentObject(LaunchNotifier()).environmentObject(ETFPriceUpdater(container: container, fetchPrice: { _ in 120 }))
            .preferredColorScheme(.dark)
        try await render(portfolio, to: "/tmp/mybond-bond-terms-portfolio.png")
        try await render(BondTermsReviewView(review: review, initialSelection: regular.id).preferredColorScheme(.dark), to: "/tmp/mybond-bond-terms-review.png")
        await Task.yield()
        XCTAssertEqual(fetches, 0)
        XCTAssertEqual(container.persistentStoreCoordinator.persistentStores.first?.type, NSInMemoryStoreType)
        XCTAssertEqual(try container.viewContext.count(for: HistoricalValuation.fetchRequest()), 0)
        XCTAssertEqual(try container.viewContext.count(for: BondEntity.fetchRequest()), 4)
    }

    func testRevertRestoresVisibleTermsAndClearsValidationErrors() async throws {
        let state = TermsEditorFixture(terms: try BondTermsFixtures.fixed())
        let view = NSHostingView(rootView: TermsEditorFixtureView(state: state))
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 900, height: 1000),
                              styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.orderOut(nil) }
        func settle() async throws {
            await Task.yield(); try await Task.sleep(nanoseconds: 100_000_000)
            view.layoutSubtreeIfNeeded()
        }
        func descendants(_ root: NSView) -> [NSView] { [root] + root.subviews.flatMap(descendants) }
        func field(_ value: String) throws -> NSTextField {
            try XCTUnwrap(descendants(view).compactMap { $0 as? NSTextField }.first { $0.isEditable && $0.stringValue == value })
        }
        func enter(_ value: String, into field: NSTextField) throws {
            XCTAssertTrue(window.makeFirstResponder(field))
            let input = try XCTUnwrap(field.currentEditor() as? NSTextView)
            input.string = value; input.didChangeText()
            window.makeFirstResponder(nil)
        }
        try await settle()
        try enter("9", into: field("3.375"))
        try enter("invalid", into: field("100.0"))
        try await settle()
        XCTAssertEqual(state.terms.couponRate, 9)
        XCTAssertNil(state.terms.redemptionPercent)
        state.terms = try BondTermsFixtures.fixed()
        state.resetID = UUID()
        try await settle()
        let fields = descendants(view).compactMap { $0 as? NSTextField }.filter(\.isEditable)
        XCTAssertTrue(fields.contains { $0.stringValue == "3.375" })
        XCTAssertTrue(fields.contains { $0.stringValue == "100.0" })
        XCTAssertFalse(fields.contains { ["9", "invalid"].contains($0.stringValue) })
        // The invalid numeric input and its error share the same replaced field state.
        XCTAssertEqual(state.terms.couponRate, 3.375)
        XCTAssertEqual(state.terms.redemptionPercent, 100)
    }
    private func render<V: View>(_ root: V, to path: String) async throws {
        let view = NSHostingView(rootView: root)
        let rect = NSRect(x: 0, y: 0, width: 1500, height: 1000)
        let window = NSWindow(contentRect: rect, styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view
        defer { window.orderOut(nil) }
        view.frame = rect
        await Task.yield()
        try await Task.sleep(nanoseconds: 50_000_000)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let destination = FileManager.default.temporaryDirectory.appendingPathComponent(URL(fileURLWithPath: path).lastPathComponent)
        print("Bond terms UI render: \(destination.path), \(data.count) bytes")
        try data.write(to: destination)
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.png")
        attachment.name = destination.lastPathComponent; attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "In-memory bond terms preview") { $0.add(attachment) }
        XCTAssertGreaterThan(data.count, 1000)
    }

}

@MainActor
private final class TermsEditorFixture: ObservableObject {
    @Published var terms: BondTerms
    @Published var resetID = UUID()
    init(terms: BondTerms) { self.terms = terms }
}
private struct TermsEditorFixtureView: View {
    @ObservedObject var state: TermsEditorFixture
    var body: some View { BondTermsFields(terms: $state.terms, resetID: state.resetID) }
}
