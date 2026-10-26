import XCTest
import CoreGraphics
@testable import ParaventCore

final class MenuBarMatchTests: XCTestCase {
    func testBrimletOverlayCannotStealDropoverIdentity() {
        let button = CGRect(x: 1027, y: 7.5, width: 24, height: 24)
        XCTAssertFalse(MenuBarMatch.accepts(window: CGRect(x: 864, y: 0, width: 328, height: 38), button: button, sameOwner: false, systemHost: false))
        XCTAssertFalse(MenuBarMatch.accepts(window: CGRect(x: 864, y: 0, width: 328, height: 38), button: button, sameOwner: true, systemHost: false))
        XCTAssertTrue(MenuBarMatch.accepts(window: CGRect(x: 1020, y: 0, width: 38, height: 39), button: button, sameOwner: false, systemHost: true))
    }
    func testWideRealStatusItemStillMatches() {
        XCTAssertTrue(MenuBarMatch.accepts(window: CGRect(x: 1271, y: 0, width: 156, height: 39), button: CGRect(x: 1278, y: 7.5, width: 142, height: 24), sameOwner: false, systemHost: true))
    }
    func testHiddenItemsAndExternalDisplayCoordinates() {
        for origin in [CGPoint(x: -4445, y: 0), CGPoint(x: 3200, y: -1440)] {
            let window = CGRect(origin: origin, size: CGSize(width: 38, height: 30))
            XCTAssertTrue(MenuBarMatch.accepts(window: window, button: window.insetBy(dx: 7, dy: 3), sameOwner: true, systemHost: false))
        }
    }
    func testDifferentOwnerOrDifferentRowDoesNotMatch() {
        let window = CGRect(x: 100, y: 0, width: 38, height: 39)
        XCTAssertFalse(MenuBarMatch.accepts(window: window, button: window.insetBy(dx: 7, dy: 7.5), sameOwner: false, systemHost: false))
        XCTAssertFalse(MenuBarMatch.accepts(window: window, button: CGRect(x: 107, y: 32, width: 24, height: 24), sameOwner: true, systemHost: false))
    }
}
