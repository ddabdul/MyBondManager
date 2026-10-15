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
}
