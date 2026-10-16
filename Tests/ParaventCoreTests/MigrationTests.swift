import XCTest
@testable import ParaventCore

final class MigrationTests: XCTestCase {
    private var folder: URL!
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUpWithError() throws {
        folder = FileManager.default.temporaryDirectory.appendingPathComponent("ParaventMigrationTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        suite = "ParaventMigrationTests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: folder)
        defaults.removePersistentDomain(forName: suite)
    }

    func testCopiesTheOldFolderOnce() throws {
        let old = folder.appendingPathComponent("Drawer"), new = folder.appendingPathComponent("Paravent")
        try FileManager.default.createDirectory(at: old, withIntermediateDirectories: true)
        try Data(#"{"com.example/0":"drawer"}"#.utf8).write(to: old.appendingPathComponent("config.json"))
        XCTAssertTrue(DrawerMigration.copyFolder(from: old, to: new))
        XCTAssertTrue(FileManager.default.fileExists(atPath: new.appendingPathComponent("config.json").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: old.appendingPathComponent("config.json").path), "The old folder stays")

        try Data("{}".utf8).write(to: new.appendingPathComponent("config.json"))
        XCTAssertFalse(DrawerMigration.copyFolder(from: old, to: new), "An existing Paravent folder is never replaced")
        XCTAssertEqual(try Data(contentsOf: new.appendingPathComponent("config.json")), Data("{}".utf8))
    }

    func testNothingToCopyWithoutAnOldFolder() {
        XCTAssertFalse(DrawerMigration.copyFolder(from: folder.appendingPathComponent("Drawer"), to: folder.appendingPathComponent("Paravent")))
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("Paravent").path))
    }

    func testCopiesSettingsOnceAndRenamesStatusItemPositions() {
        defaults.set(7, forKey: "NSStatusItem Preferred Position paravent.main")
        DrawerMigration.copyDefaults([
            "NSStatusItem Preferred Position drawer.main": 559,
            "NSStatusItem Preferred Position drawer.divider": 783,
            "other": "value",
        ], to: defaults)
        XCTAssertEqual(defaults.integer(forKey: "NSStatusItem Preferred Position paravent.main"), 7, "Paravent's own value wins")
        XCTAssertEqual(defaults.integer(forKey: "NSStatusItem Preferred Position paravent.divider"), 783)
        XCTAssertNil(defaults.object(forKey: "NSStatusItem Preferred Position drawer.divider"))
        XCTAssertEqual(defaults.string(forKey: "other"), "value")

        defaults.removeObject(forKey: "other")
        DrawerMigration.copyDefaults(["other": "again"], to: defaults)
        XCTAssertNil(defaults.object(forKey: "other"), "The settings are copied only once")
    }

    func testReadsDrawersPanelMode() throws {
        let modes = try JSONDecoder().decode([String: ItemMode].self, from: Data(#"{"a":"visible","b":"drawer","c":"hidden","d":"panel","e":"unknown"}"#.utf8))
        XCTAssertEqual(modes, ["a": .visible, "b": .panel, "c": .hidden, "d": .panel, "e": .visible])
        XCTAssertEqual(String(decoding: try JSONEncoder().encode(ItemMode.panel), as: UTF8.self), #""panel""#)
    }
}
