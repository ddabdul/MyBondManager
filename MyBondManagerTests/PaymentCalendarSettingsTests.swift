import XCTest
import SwiftUI
import Vision
@testable import MyBondManager

@MainActor
final class PaymentCalendarSettingsTests: XCTestCase {
    func testNativeSettingsShowsSyncControlsAndPhoneInstructions() async throws {
        let store = try TestPortfolio.make()
        let suite = "PaymentCalendarSettingsTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let sync = PaymentCalendarSync(container: store, backend: RecordingPaymentCalendarStore(), defaults: defaults)
        await sync.enable(sourceID: "icloud")
        let root = PaymentCalendarSettingsView(sync: sync).preferredColorScheme(.dark)
        let view = NSHostingView(rootView: root); view.appearance = NSAppearance(named: .darkAqua)
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 540, height: 740),
            styleMask: [.titled], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false; window.contentView = view; window.makeKeyAndOrderFront(nil)
        defer { window.orderOut(nil); sync.disable() }
        await Task.yield(); try await Task.sleep(nanoseconds: 250_000_000)
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let request = VNRecognizeTextRequest()
        try VNImageRequestHandler(cgImage: XCTUnwrap(bitmap.cgImage)).perform([request])
        let text = (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
        XCTAssertTrue(text.contains("Payment alerts on iPhone"), text)
        XCTAssertTrue(text.contains("Automatic sync is on"), text)
        XCTAssertTrue(text.contains("Stop syncing"), text)
        XCTAssertTrue(text.contains("Sync now"), text)
        XCTAssertTrue(text.contains("Close"), text)
        let attachment = XCTAttachment(data: try XCTUnwrap(bitmap.representation(using: .png, properties: [:])),
            uniformTypeIdentifier: "public.png")
        attachment.name = "payment-calendar-settings"; attachment.lifetime = .keepAlways
        XCTContext.runActivity(named: "Native iPhone alert settings") { $0.add(attachment) }
    }
}
