import XCTest
import AppKit
import Vision

@MainActor
enum NativeSnapshotTestSupport {
    static func observations(in view: NSView) throws -> [VNRecognizedTextObservation] {
        view.layoutSubtreeIfNeeded()
        let bitmap = try XCTUnwrap(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: bitmap)
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        let request = VNRecognizeTextRequest()
        request.minimumTextHeight = 0.005; request.recognitionLanguages = ["en-US"]
        try VNImageRequestHandler(data: png).perform([request])
        return request.results ?? []
    }
    static func text(in view: NSView) throws -> String {
        try observations(in: view).compactMap { $0.topCandidates(1).first?.string }.joined(separator: " ")
    }
    static func click(_ label: String, in view: NSView, window: NSWindow) throws {
        let boxes = try observations(in: view).compactMap { observation -> CGRect? in
            guard let candidate = observation.topCandidates(1).first, let range = candidate.string.range(of: label) else { return nil }
            return try candidate.boundingBox(for: range)?.boundingBox
        }
        let box = try XCTUnwrap(boxes.max { $0.midY < $1.midY }, "Visible control: " + label)
        let point = view.convert(NSPoint(x: box.midX * view.bounds.width,
            y: (view.isFlipped ? 1 - box.midY : box.midY) * view.bounds.height), to: nil)
        for type in [NSEvent.EventType.leftMouseDown, .leftMouseUp] {
            window.sendEvent(try XCTUnwrap(NSEvent.mouseEvent(with: type, location: point, modifierFlags: [],
                timestamp: ProcessInfo.processInfo.systemUptime, windowNumber: window.windowNumber,
                context: nil, eventNumber: 0, clickCount: 1, pressure: 1)))
        }
    }
}
