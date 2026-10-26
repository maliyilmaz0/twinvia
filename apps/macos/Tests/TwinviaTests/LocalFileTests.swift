import CryptoKit
import Foundation
import XCTest
@testable import Twinvia

final class LocalFileTests: XCTestCase {
    func testEmptyFileMatchesSharedProtocolFixture() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("merhaba.txt")
        try Data().write(to: url)
        let file = try LocalFile.inspect(url)
        XCTAssertEqual(file.offer.size, 0)
        XCTAssertEqual(file.offer.sha256, "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        XCTAssertEqual(file.offer.mimeType, "text/plain")
    }

    func testDigestCoversMoreThanOneReadChunk() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("binary.dat")
        var data = Data(repeating: 0x61, count: 1_048_576)
        data.append(Data(repeating: 0x62, count: 524_321))
        try data.write(to: url)
        let expected = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
        let file = try LocalFile.inspect(url)
        XCTAssertEqual(file.offer.size, Int64(data.count))
        XCTAssertEqual(file.offer.sha256, expected)
    }

    func testDirectoryIsRejected() {
        XCTAssertThrowsError(try LocalFile.inspect(FileManager.default.temporaryDirectory))
    }
}
