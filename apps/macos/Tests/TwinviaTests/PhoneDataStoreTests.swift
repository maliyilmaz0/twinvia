import TwinviaProtocol
import XCTest
@testable import Twinvia

@MainActor
final class PhoneDataStoreTests: XCTestCase {
    func testOldSearchReplyCannotReplaceCurrentSearchAndDisconnectClearsData() {
        var requests: [(String, DeviceCommand)] = []
        let store = PhoneDataStore(available: { true }) { command in
            let id = UUID().uuidString; requests.append((id, command)); return id
        }
        store.load(.contacts)
        store.contactSearch = "Ada"; store.load(.contacts)
        let page = PhonePage(
            kind: .contacts, contacts: [PhoneContact(id: "1", name: "Ada", number: "123456")], total: 1)
        XCTAssertFalse(store.receive(CommandResult(requestId: requests[0].0, success: true, message: "ok", data: page)))
        XCTAssertTrue(store.contacts.isEmpty)
        XCTAssertTrue(store.receive(CommandResult(requestId: requests[1].0, success: true, message: "ok", data: page)))
        XCTAssertEqual(store.contacts.count, 1)
        store.disconnected()
        XCTAssertTrue(store.contacts.isEmpty)
        XCTAssertTrue(store.totals.isEmpty)
    }
    func testResponseForWrongFolderIsRejectedAndNextPageIsCorrelated() {
        var request = ""
        let store = PhoneDataStore(available: { true }) { _ in
            request = UUID().uuidString; return request
        }
        store.load(.files, folder: "Download")
        store.receive(
            CommandResult(requestId: request, success: true, message: "ok", data: PhonePage(kind: .files, path: "DCIM"))
        )
        XCTAssertNotNil(store.errors[.files])
        XCTAssertTrue(store.files.isEmpty)
        store.load(.contacts)
        let page = PhonePage(
            kind: .contacts, contacts: [PhoneContact(id: "1", name: "Test", number: "123456")], nextOffset: 1, total: 2)
        store.receive(CommandResult(requestId: request, success: true, message: "ok", data: page))
        store.load(.contacts, more: true)
        store.receive(
            CommandResult(
                requestId: request, success: true, message: "ok",
                data: PhonePage(
                    kind: .contacts,
                    contacts: [PhoneContact(id: "2", name: "Second", number: "654321")], total: 2)))
        XCTAssertEqual(store.contacts.count, 2)
        XCTAssertNil(store.next[.contacts])
    }
}
