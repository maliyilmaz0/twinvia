import TwinviaProtocol
import CryptoKit
import Foundation
import XCTest
@testable import Twinvia

final class FileStorageTests: XCTestCase {
    private func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(
            "TwinviaFileTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func offer(_ data: Data, hash: String? = nil) -> FileOffer {
        FileOffer(
            transferId: UUID().uuidString.lowercased(), fileName: "fixture.bin", mimeType: "application/octet-stream",
            size: Int64(data.count), sha256: hash ?? SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        )
    }

    func testSeveralChunksProduceExactFile() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data((0..<50_003).map { UInt8($0 % 251) })
        let original = root.appendingPathComponent("original.bin")
        try data.write(to: original)
        let file = try LocalFile.inspect(original)
        let sender = FileStorage(directory: root)
        let receiver = FileStorage(directory: root.appendingPathComponent("received"))
        try await sender.beginSending(file)
        try await receiver.beginReceiving(file.offer)
        var offset: Int64 = 0
        while let chunk = try await sender.read(at: offset) { offset = try await receiver.write(chunk) }
        let output = try await receiver.finishReceiving()
        XCTAssertEqual(try Data(contentsOf: output), data)
        await sender.reset()
        await receiver.reset()
    }

    func testExistingDestinationIsNeverOverwritten() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = root.appendingPathComponent("fixture.bin")
        try Data("existing".utf8).write(to: original)
        let data = Data("new".utf8)
        let value = offer(data)
        let receiver = FileStorage(directory: root)
        try await receiver.beginReceiving(value)
        _ = try await receiver.write(FileChunk(transferId: value.transferId, offset: 0, data: data))
        let output = try await receiver.finishReceiving()
        XCTAssertNotEqual(output, original)
        XCTAssertEqual(try String(contentsOf: original, encoding: .utf8), "existing")
        XCTAssertEqual(try Data(contentsOf: output), data)
        await receiver.reset()
    }

    func testIncorrectHashFailsAndPartialFileIsRemoved() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let data = Data("modified".utf8)
        let value = offer(data, hash: String(repeating: "0", count: 64))
        let receiver = FileStorage(directory: root)
        try await receiver.beginReceiving(value)
        _ = try await receiver.write(FileChunk(transferId: value.transferId, offset: 0, data: data))
        do { _ = try await receiver.finishReceiving(); XCTFail("Corrupt file accepted") } catch {}
        await receiver.reset()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testOutOfOrderChunkRejectedAndCancellationCleansUp() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let value = offer(Data([1, 2, 3]))
        let receiver = FileStorage(directory: root)
        try await receiver.beginReceiving(value)
        do {
            _ = try await receiver.write(FileChunk(transferId: value.transferId, offset: 1, data: Data([2])))
            XCTFail("Out of order chunk accepted")
        } catch {}
        await receiver.reset()
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.path), [])
    }

    func testEmptyFileNeedsNoBinaryChunk() async throws {
        let root = try temporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let receiver = FileStorage(directory: root)
        try await receiver.beginReceiving(offer(Data()))
        let output = try await receiver.finishReceiving()
        XCTAssertEqual(try Data(contentsOf: output), Data())
        await receiver.reset()
    }
}
