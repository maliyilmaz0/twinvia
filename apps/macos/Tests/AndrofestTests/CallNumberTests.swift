import Foundation
import XCTest
@testable import Androfest

final class CallNumberTests: XCTestCase {
    func testNormalizesPhoneLinksWithoutDialing() {
        XCTAssertEqual(CallNumber.normalize("+90 (555) 123-45-67"), "+905551234567")
        XCTAssertEqual(CallNumber.from(URL(string: "tel:%2B905551234567")!), "+905551234567")
        XCTAssertEqual(CallNumber.from(URL(string: "callto://905551234567")!), "905551234567")
    }
    func testRejectsUSSDExtensionsAndCommands() {
        for value in [
            "*123#", "+90;123", "123,456", "123\n456", "++1234", "abc123", "12", String(repeating: "1", count: 21),
            "123?call=456",
        ] {
            XCTAssertNil(CallNumber.normalize(value))
        }
        XCTAssertNil(CallNumber.from(URL(string: "tel:123%0A456")!))
        XCTAssertNil(CallNumber.from(URL(string: "https://example.com/123456")!))
    }
}
