import AppKit
import TwinviaProtocol
import XCTest
@testable import Twinvia

@MainActor
final class AutomaticClipboardTests: XCTestCase {
    func testCopyIsAutomaticAndRemoteWritesNeverEcho() {
        let board = NSPasteboard(name: .init("twinvia-test-" + UUID().uuidString))
        var texts: [String] = []
        let clipboard = AutomaticClipboard(pasteboard: board, automaticallyPoll: false, canSend: { true }) {
            texts.append($0); return UUID().uuidString
        }
        board.clearContents(); board.setString("copy from another app", forType: .string)
        clipboard.poll()
        XCTAssertEqual(texts, ["copy from another app"])
        clipboard.receive("phone copy")
        XCTAssertEqual(board.string(forType: .string), "phone copy")
        clipboard.poll(); clipboard.poll()
        XCTAssertEqual(texts.count, 1)
        XCTAssertEqual(clipboard.applied, 1)
        board.releaseGlobally()
    }
    func testHistoryOfflineAndDisabledChangesDoNotLeakLater() {
        let board = NSPasteboard(name: .init("twinvia-test-" + UUID().uuidString))
        board.setString("historical", forType: .string)
        var online = false; var sent = 0
        let clipboard = AutomaticClipboard(pasteboard: board, automaticallyPoll: false, canSend: { online }) { _ in
            sent += 1; return UUID().uuidString
        }
        clipboard.poll(); online = true; clipboard.poll(); XCTAssertEqual(sent, 0)
        clipboard.setEnabled(false)
        board.clearContents(); board.setString("disabled copy", forType: .string)
        clipboard.poll(); clipboard.setEnabled(true); clipboard.poll(); XCTAssertEqual(sent, 0)
        clipboard.setEnabled(false); clipboard.receive("remote")
        XCTAssertEqual(board.string(forType: .string), "disabled copy")
        board.releaseGlobally()
    }
    func testRapidCopiesCoalesceAndOversizedContentIsIgnored() {
        let board = NSPasteboard(name: .init("twinvia-test-" + UUID().uuidString))
        var texts: [String] = []
        let clipboard = AutomaticClipboard(pasteboard: board, automaticallyPoll: false, canSend: { true }) {
            texts.append($0); return UUID().uuidString
        }
        for text in ["first", "last"] { board.clearContents(); board.setString(text, forType: .string) }
        clipboard.poll(); XCTAssertEqual(texts, ["last"])
        board.clearContents(); board.setString(String(repeating: "x", count: 16385), forType: .string)
        clipboard.poll(); XCTAssertEqual(texts.count, 1)
        board.releaseGlobally()
    }
    func testConcealedContentDoesNotSync() {
        let board = NSPasteboard(name: .init("twinvia-test-" + UUID().uuidString))
        var sent = 0
        let clipboard = AutomaticClipboard(pasteboard: board, automaticallyPoll: false, canSend: { true }) { _ in
            sent += 1; return UUID().uuidString
        }
        board.clearContents(); board.setString("secret", forType: .string)
        board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType"))
        clipboard.poll(); XCTAssertEqual(sent, 0)
        board.releaseGlobally()
    }
    func testImageTakesPriorityOverTextAndConcealedImagesAreSkipped() async throws {
        let board = NSPasteboard(name: .init("twinvia-image-test-" + UUID().uuidString))
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 8,
            bitsPerPixel: 32)!
        let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
        var images: [Data] = [], texts: [String] = []
        let clipboard = AutomaticClipboard(
            pasteboard: board, automaticallyPoll: false, canSend: { true },
            sendImage: { data, _ in images.append(data) },
            send: {
                texts.append($0); return UUID().uuidString
            })
        board.clearContents(); board.setData(png, forType: .png); board.setString("image fallback", forType: .string)
        clipboard.poll()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(images, [png]); XCTAssertTrue(texts.isEmpty)
        board.clearContents(); board.setData(png, forType: .png)
        board.setData(Data(), forType: .init("org.nspasteboard.ConcealedType")); clipboard.poll()
        for _ in 0..<10 { await Task.yield() }
        XCTAssertEqual(images.count, 1)
        board.releaseGlobally()
    }

}
