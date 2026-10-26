import Foundation
import XCTest
@testable import AndrofestProtocol

final class FileChunkTests: XCTestCase {
    private let id = "12345678-1234-4234-9234-123456789abc"

    func testIndependentBinaryFixture() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent(
                "fixtures/binary/file-chunk.json")
        let fixture = try JSONDecoder().decode(Fixture.self, from: Data(contentsOf: url))
        let bytes = try XCTUnwrap(Data(base64Encoded: fixture.frameBase64))
        let chunk = try FileChunk.decode(bytes)
        XCTAssertEqual(chunk.transferId, fixture.transferId)
        XCTAssertEqual(chunk.offset, fixture.offset)
        XCTAssertEqual(String(decoding: chunk.data, as: UTF8.self), fixture.text)
        XCTAssertEqual(try chunk.encode(), bytes)
    }

    func testMaximumChunkAndFileBoundary() throws {
        let data = Data(repeating: 42, count: FileChunk.maxDataBytes)
        let value = FileChunk(transferId: id, offset: FileChunk.maxFileBytes - Int64(data.count), data: data)
        XCTAssertEqual(try FileChunk.decode(value.encode()).data, data)
        XCTAssertThrowsError(try FileChunk(transferId: id, offset: FileChunk.maxFileBytes, data: Data([1])).encode())
    }

    func testInvalidPayloadsRejected() throws {
        for data in [Data(), Data(repeating: 1, count: FileChunk.maxDataBytes + 1)] {
            XCTAssertThrowsError(try FileChunk(transferId: id, offset: 0, data: data).encode())
        }
        XCTAssertThrowsError(try FileChunk(transferId: id, offset: -1, data: Data([1])).encode())
        XCTAssertThrowsError(try FileChunk(transferId: "bad-id", offset: 0, data: Data([1])).encode())
    }

    func testTruncatedAndUnknownFramesRejected() throws {
        var frame = try FileChunk(transferId: id, offset: 7, data: Data([1])).encode()
        XCTAssertThrowsError(try FileChunk.decode(frame.prefix(28)))
        frame[0] = 0
        XCTAssertThrowsError(try FileChunk.decode(frame))
    }

    private struct Fixture: Decodable {
        let transferId: String; let offset: Int64; let text: String; let frameBase64: String
    }
}
