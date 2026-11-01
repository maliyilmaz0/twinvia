import AppKit
import TwinviaProtocol
import XCTest
@testable import Twinvia

final class ScreenImageDecoderTests: XCTestCase {
    func testEncodedDimensionsMustMatchBoundedMetadata() throws {
        let bitmap = try XCTUnwrap(
            NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 12,
                bitsPerSample: 8, samplesPerPixel: 3, hasAlpha: false, isPlanar: false,
                colorSpaceName: .deviceRGB, bytesPerRow: 24, bitsPerPixel: 24))
        let jpeg = try XCTUnwrap(bitmap.representation(using: .jpeg, properties: [:])).base64EncodedString()
        XCTAssertNotNil(ScreenImageDecoder.decode(RemoteScreen(jpegBase64: jpeg, width: 8, height: 12)))
        XCTAssertNil(ScreenImageDecoder.decode(RemoteScreen(jpegBase64: jpeg, width: 12, height: 8)))
        XCTAssertNil(ScreenImageDecoder.decode(RemoteScreen(jpegBase64: jpeg, width: 2560, height: 2560)))
    }
}
