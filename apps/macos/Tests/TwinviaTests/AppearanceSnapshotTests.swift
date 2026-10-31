import AppKit
import SwiftUI
import XCTest
@testable import Twinvia

@MainActor
final class AppearanceSnapshotTests: XCTestCase {
    func testLaunchpadFitsMinimumWindowWidthWithMotionDisabled() throws {
        let renderer = ImageRenderer(
            content: FeatureLaunchpad { _ in }
                .padding(24).frame(width: 640)
                .background(FestTheme.background)
                .environment(\.colorScheme, .dark)
                .environment(\.twinviaPlayfulMotion, false))
        let image = try XCTUnwrap(renderer.cgImage)
        XCTAssertEqual(image.width, 640)
        XCTAssertGreaterThan(image.height, 300)
        XCTAssertLessThan(image.height, 700)
        // Optional local review artifact; CI only checks bounded rendering.
        if let directory = ProcessInfo.processInfo.environment["TWINVIA_UI_SNAPSHOTS"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("launchpad.png")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let png = try XCTUnwrap(NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]))
            try png.write(to: url)
        }
    }
}
