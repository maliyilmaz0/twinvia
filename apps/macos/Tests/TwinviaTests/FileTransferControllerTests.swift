import TwinviaProtocol
import Foundation
import XCTest
@testable import Twinvia

@MainActor
final class FileTransferControllerTests: XCTestCase {
    private func fixture() throws -> (URL, LocalFile, Data) {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TwinviaControllerTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let data = Data((0..<98_317).map { UInt8($0 % 251) })
        let input = root.appendingPathComponent("controller.bin")
        try data.write(to: input)
        return (root, try LocalFile.inspect(input), data)
    }

    private func waitUntil(_ predicate: () -> Bool) async throws {
        for _ in 0..<300 {
            if predicate() { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("File transfer did not reach its expected state")
    }

    func testAcknowledgedTransferAndRepeatedSendUseDifferentIDs() async throws {
        let (root, file, data) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        var sender: FileTransferController!
        var receiver: FileTransferController!
        var ids: [String] = []
        receiver = FileTransferController(
            send: { sender.receive($0) }, sendChunk: { _ in }, directory: root.appendingPathComponent("received"))
        sender = FileTransferController(
            send: { control in
                receiver.receive(control)
                if case .offer(let offer) = control { ids.append(offer.transferId); receiver.accept() }
            }, sendChunk: { chunk in receiver.receiveChunk(try FileChunk.decode(chunk.encode())) }, directory: root)
        for _ in 0..<2 {
            sender.sendFile(file)
            try await waitUntil { !sender.status.busy && receiver.status.receivedURL != nil }
            let output = try XCTUnwrap(receiver.status.receivedURL)
            XCTAssertEqual(try Data(contentsOf: output), data)
            XCTAssertTrue(sender.status.message.contains("SHA-256"))
        }
        XCTAssertEqual(ids.count, 2)
        XCTAssertNotEqual(ids[0], ids[1])
        XCTAssertNotEqual(ids[0], file.offer.transferId)
        sender = nil; receiver = nil
    }

    func testReceiverRejectionNeverCreatesDestination() async throws {
        let (root, file, _) = try fixture()
        defer { try? FileManager.default.removeItem(at: root) }
        let destination = root.appendingPathComponent("rejected")
        var sender: FileTransferController!
        var receiver: FileTransferController!
        receiver = FileTransferController(send: { sender.receive($0) }, sendChunk: { _ in }, directory: destination)
        sender = FileTransferController(
            send: { control in
                receiver.receive(control)
                if case .offer = control { receiver.cancel(reason: "File declined.") }
            }, sendChunk: { _ in XCTFail("Sender emitted data before acceptance") }, directory: root)
        sender.sendFile(file)
        try await waitUntil { !sender.status.busy }
        XCTAssertEqual(sender.status.message, "File declined.")
        XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
        sender = nil; receiver = nil
    }
}
