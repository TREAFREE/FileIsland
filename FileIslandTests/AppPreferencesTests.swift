import Foundation
import XCTest
@testable import FileIsland

@MainActor
final class AppPreferencesTests: XCTestCase {
    func testDefaultsAndPersistence() {
        let suite = "AppPreferencesTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let preferences = AppPreferences(defaults: defaults)

        XCTAssertEqual(preferences.defaultQuality, .balanced)
        XCTAssertTrue(preferences.stripMetadataByDefault)
        XCTAssertEqual(preferences.islandOpacity, 1, accuracy: 0.001)

        preferences.defaultQuality = .highestQuality
        preferences.stripMetadataByDefault = false
        var observedOpacity: Double?
        preferences.onIslandOpacityChange = { observedOpacity = $0 }
        preferences.islandOpacity = 0.8

        let restored = AppPreferences(defaults: defaults)
        XCTAssertEqual(restored.defaultQuality, .highestQuality)
        XCTAssertFalse(restored.stripMetadataByDefault)
        XCTAssertEqual(restored.islandOpacity, 0.8, accuracy: 0.001)
        XCTAssertEqual(observedOpacity ?? -1, 0.8, accuracy: 0.001)
    }
}
