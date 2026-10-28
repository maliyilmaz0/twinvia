import Foundation
import XCTest
@testable import Twinvia

final class AppNavigationTests: XCTestCase {
    func testBrandedAndLegacyLinksHaveEquivalentRoutes() throws {
        for scheme in ["twinvia", "androfest", "TWINVIA"] {
            XCTAssertEqual(AppNavigation(url: try XCTUnwrap(URL(string: "\(scheme)://calls"))), .calls)
            XCTAssertEqual(AppNavigation(url: try XCTUnwrap(URL(string: "\(scheme)://contacts"))), .contacts)
            XCTAssertEqual(AppNavigation(url: try XCTUnwrap(URL(string: "\(scheme)://history"))), .history)
            XCTAssertEqual(AppNavigation(url: try XCTUnwrap(URL(string: "\(scheme)://screen"))), .screen)
        }
    }

    func testFileLinksDecodeOnlyTheFolderParameter() throws {
        XCTAssertEqual(
            AppNavigation(url: try XCTUnwrap(URL(string: "twinvia://files?path=Download%2FTwinvia"))),
            .files(path: "Download/Twinvia"))
        XCTAssertEqual(AppNavigation(url: try XCTUnwrap(URL(string: "androfest://files"))), .files(path: ""))
    }

    func testPairingCallingAndUnknownLinksAreNotNavigationActions() throws {
        for value in ["twinvia://pair", "androfest://unknown", "https://calls", "tel:123456"] {
            XCTAssertNil(AppNavigation(url: try XCTUnwrap(URL(string: value))))
        }
    }
}
