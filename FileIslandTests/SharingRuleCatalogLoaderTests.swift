import Foundation
import XCTest
@testable import FileIsland

final class SharingRuleCatalogLoaderTests: XCTestCase {
    private static let now = SharingRuleCatalogLoaderTests.date("2026-08-11T12:00:00Z")

    func testAcceptsValidEmptySchemaVersionOneCatalog() throws {
        let catalog = try decoder().decode(
            catalogJSON(catalogVersion: "2026.08", rules: [])
        )

        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertEqual(catalog.catalogVersion, "2026.08")
        XCTAssertEqual(catalog.rules, [])
    }

    func testValidRuleCreatesCompleteImmutableSnapshot() throws {
        let catalog = try decoder().decode(catalogJSON(rules: [validRuleJSON()]))
        let rule = try XCTUnwrap(catalog.rules.first)
        let snapshot = SharingRuleSnapshot(rule: rule)

        XCTAssertEqual(snapshot.id, rule.id)
        XCTAssertEqual(snapshot.revision, rule.revision)
        XCTAssertEqual(snapshot.platform, rule.platform)
        XCTAssertEqual(snapshot.channel, rule.channel)
        XCTAssertEqual(snapshot.displayName, rule.displayName)
        XCTAssertEqual(snapshot.maxBytes, rule.maxBytes)
        XCTAssertEqual(snapshot.maxDurationMilliseconds, rule.maxDurationMilliseconds)
        XCTAssertEqual(snapshot.safetyRatio, rule.safetyRatio)
        XCTAssertEqual(snapshot.acceptedContainers, rule.acceptedContainers)
        XCTAssertEqual(snapshot.acceptedVideoCodecs, rule.acceptedVideoCodecs)
        XCTAssertEqual(snapshot.acceptedAudioCodecs, rule.acceptedAudioCodecs)
        XCTAssertEqual(snapshot.sourceURLs, rule.sourceURLs)
        XCTAssertEqual(snapshot.lastVerifiedAt, rule.lastVerifiedAt)
        XCTAssertEqual(snapshot.expiresAt, rule.expiresAt)

        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(SharingRuleSnapshot.self, from: encoded)
        XCTAssertEqual(decoded, snapshot)
    }

    func testRejectsUnsupportedSchemaAndBlankCatalogVersion() {
        assertCatalogError(
            catalogJSON(schemaVersion: 2, rules: []),
            equals: .unsupportedSchemaVersion(2)
        )
        assertCatalogError(
            catalogJSON(catalogVersion: " ", rules: []),
            equals: .invalidCatalogVersion(" ")
        )
        assertCatalogError(
            catalogJSON(catalogVersion: " 2026.08", rules: []),
            equals: .invalidCatalogVersion(" 2026.08")
        )
    }

    func testRejectsBlankRuleIdentityAndNonPositiveRevision() {
        assertRuleMutation(
            replacing: "\"id\": \"platform-channel\"",
            with: "\"id\": \" \"",
            equals: .invalidIdentity(" ")
        )
        assertRuleMutation(
            replacing: "\"platform\": \"Platform\"",
            with: "\"platform\": \"\"",
            equals: .invalidIdentity("platform-channel")
        )
        assertRuleMutation(
            replacing: "\"channel\": \"Chat attachment\"",
            with: "\"channel\": \" Chat attachment\"",
            equals: .invalidIdentity("platform-channel")
        )
        assertRuleMutation(
            replacing: "\"displayName\": \"Platform · Chat attachment\"",
            with: "\"displayName\": \" \"",
            equals: .invalidIdentity("platform-channel")
        )
        assertRuleMutation(
            replacing: "\"revision\": 1",
            with: "\"revision\": 0",
            equals: .invalidRevision("platform-channel")
        )
    }

    func testRejectsDuplicateRuleRevisionAndDuplicateStableID() {
        let rule = validRuleJSON()
        assertCatalogError(
            catalogJSON(rules: [rule, rule]),
            equals: .duplicateRule(id: "platform-channel", revision: 1)
        )

        let newerRevision = rule.replacingOccurrences(
            of: "\"revision\": 1",
            with: "\"revision\": 2"
        )
        assertCatalogError(
            catalogJSON(rules: [rule, newerRevision]),
            equals: .duplicateStableID("platform-channel")
        )
    }

    func testRejectsMissingNonPositiveOrInvalidConstraints() {
        let noConstraints = validRuleJSON()
            .replacingOccurrences(of: "\"maxBytes\": 100000000,\n", with: "")
            .replacingOccurrences(of: "\"maxDurationMilliseconds\": 300000,\n", with: "")
        assertCatalogError(
            catalogJSON(rules: [noConstraints]),
            equals: .invalidConstraints("platform-channel")
        )
        assertRuleMutation(
            replacing: "\"maxBytes\": 100000000",
            with: "\"maxBytes\": 0",
            equals: .invalidConstraints("platform-channel")
        )
        assertRuleMutation(
            replacing: "\"maxDurationMilliseconds\": 300000",
            with: "\"maxDurationMilliseconds\": -1",
            equals: .invalidConstraints("platform-channel")
        )
        assertRuleMutation(
            replacing: "\"safetyRatio\": 0.92",
            with: "\"safetyRatio\": 0.79",
            equals: .invalidSafetyRatio("platform-channel")
        )
        assertRuleMutation(
            replacing: "\"safetyRatio\": 0.92",
            with: "\"safetyRatio\": 0.99",
            equals: .invalidSafetyRatio("platform-channel")
        )
    }

    func testAcceptsSizeOnlyAndDurationOnlyConstraintsAtRatioBounds() throws {
        let sizeOnly = validRuleJSON()
            .replacingOccurrences(of: "\"maxDurationMilliseconds\": 300000,\n", with: "")
            .replacingOccurrences(of: "\"safetyRatio\": 0.92", with: "\"safetyRatio\": 0.80")
        let durationOnly = validRuleJSON(id: "duration-only")
            .replacingOccurrences(of: "\"maxBytes\": 100000000,\n", with: "")
            .replacingOccurrences(of: "\"safetyRatio\": 0.92", with: "\"safetyRatio\": 0.98")

        let rules = try decoder().decode(catalogJSON(rules: [sizeOnly, durationOnly])).rules

        XCTAssertEqual(rules.count, 2)
        XCTAssertEqual(rules[0].maxDurationMilliseconds, nil)
        XCTAssertEqual(rules[0].safetyRatio, 0.80)
        XCTAssertEqual(rules[1].maxBytes, nil)
        XCTAssertEqual(rules[1].safetyRatio, 0.98)
    }

    func testRejectsMissingOrNonHTTPSSources() {
        assertRuleMutation(
            replacing: "\"sourceURLs\": [\"https://official.example/rules\"]",
            with: "\"sourceURLs\": []",
            equals: .missingSources("platform-channel")
        )
        assertRuleMutation(
            replacing: "https://official.example/rules",
            with: "http://official.example/rules",
            equals: .insecureSource(
                id: "platform-channel",
                url: "http://official.example/rules"
            )
        )
        assertRuleMutation(
            replacing: "https://official.example/rules",
            with: "https:///rules",
            equals: .insecureSource(id: "platform-channel", url: "https:///rules")
        )
    }

    func testRejectsMissingOrDuplicateAcceptedFormats() {
        assertRuleMutation(
            replacing: "\"acceptedContainers\": [\"mp4\"]",
            with: "\"acceptedContainers\": []",
            equals: .invalidAcceptedFormats("platform-channel")
        )
        assertRuleMutation(
            replacing: "\"acceptedVideoCodecs\": [\"h264\"]",
            with: "\"acceptedVideoCodecs\": []",
            equals: .invalidAcceptedFormats("platform-channel")
        )
        assertRuleMutation(
            replacing: "\"acceptedAudioCodecs\": [\"aac\"]",
            with: "\"acceptedAudioCodecs\": []",
            equals: .invalidAcceptedFormats("platform-channel")
        )
        assertRuleMutation(
            replacing: "[\"mp4\"]",
            with: "[\"mp4\", \"mp4\"]",
            equals: .invalidAcceptedFormats("platform-channel")
        )
    }

    func testUnknownContainerVideoOrAudioCodecFailsClosed() {
        assertDecodingFailure(replacing: "[\"mp4\"]", with: "[\"mkv\"]")
        assertDecodingFailure(replacing: "[\"h264\"]", with: "[\"h265\"]")
        assertDecodingFailure(replacing: "[\"aac\"]", with: "[\"opus\"]")
    }

    func testRejectsFutureVerificationExpiredRuleAndInvalidDateWindows() {
        assertRuleMutation(
            replacing: "2026-08-01T00:00:00Z",
            with: "2026-08-12T00:00:00Z",
            equals: .verificationInFuture("platform-channel")
        )
        assertRuleMutation(
            replacing: "2026-08-31T00:00:00Z",
            with: "2026-08-11T12:00:00Z",
            equals: .expiredRule("platform-channel")
        )
        assertRuleMutation(
            replacing: "2026-08-31T00:00:00Z",
            with: "2026-07-31T00:00:00Z",
            equals: .expiryBeforeVerification("platform-channel")
        )
        assertRuleMutation(
            replacing: "2026-08-31T00:00:00Z",
            with: "2026-10-31T00:00:01Z",
            equals: .validityWindowTooLong("platform-channel")
        )
    }

    func testAcceptsExactlyNinetyDayValidityWindow() throws {
        let rule = validRuleJSON()
            .replacingOccurrences(of: "2026-08-01T00:00:00Z", with: "2026-05-31T12:00:00Z")
            .replacingOccurrences(of: "2026-08-31T00:00:00Z", with: "2026-08-29T12:00:00Z")

        XCTAssertEqual(try decoder().decode(catalogJSON(rules: [rule])).rules.count, 1)
    }

    func testBundledCatalogIsPresentAndTruthfullyEmpty() async throws {
        let catalog = try await BundledSharingRuleCatalogLoader(bundle: .main).loadCatalog()

        XCTAssertEqual(catalog.schemaVersion, 1)
        XCTAssertEqual(catalog.catalogVersion, "2026.08")
        XCTAssertEqual(catalog.rules, [])
        let rules = try await BundledSharingRuleCatalogLoader(bundle: .main).loadRules()
        XCTAssertEqual(rules, [])
    }

    func testBundledLoaderRejectsMissingResource() async {
        let loader = BundledSharingRuleCatalogLoader(resourceURL: nil, decoder: decoder())

        do {
            _ = try await loader.loadCatalog()
            XCTFail("Expected resourceMissing")
        } catch {
            XCTAssertEqual(error as? SharingRuleCatalogError, .resourceMissing)
        }
    }

    private func decoder() -> JSONSharingRuleCatalogDecoder {
        let now = Self.now
        return JSONSharingRuleCatalogDecoder(now: { now })
    }

    private func assertCatalogError(
        _ data: Data,
        equals expected: SharingRuleCatalogError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertThrowsError(try decoder().decode(data), file: file, line: line) {
            XCTAssertEqual($0 as? SharingRuleCatalogError, expected, file: file, line: line)
        }
    }

    private func assertRuleMutation(
        replacing target: String,
        with replacement: String,
        equals expected: SharingRuleCatalogError,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rule = validRuleJSON().replacingOccurrences(of: target, with: replacement)
        XCTAssertNotEqual(rule, validRuleJSON(), "Mutation target was not found", file: file, line: line)
        assertCatalogError(catalogJSON(rules: [rule]), equals: expected, file: file, line: line)
    }

    private func assertDecodingFailure(
        replacing target: String,
        with replacement: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rule = validRuleJSON().replacingOccurrences(of: target, with: replacement)
        XCTAssertThrowsError(try decoder().decode(catalogJSON(rules: [rule])), file: file, line: line) {
            XCTAssertTrue($0 is DecodingError, "Unexpected error: \($0)", file: file, line: line)
        }
    }

    private func catalogJSON(
        schemaVersion: Int = 1,
        catalogVersion: String = "2026.08",
        rules: [String]
    ) -> Data {
        Data("""
        {
          "schemaVersion": \(schemaVersion),
          "catalogVersion": "\(catalogVersion)",
          "rules": [\(rules.joined(separator: ","))]
        }
        """.utf8)
    }

    private func validRuleJSON(id: String = "platform-channel") -> String {
        """
        {
          "id": "\(id)",
          "revision": 1,
          "platform": "Platform",
          "channel": "Chat attachment",
          "displayName": "Platform · Chat attachment",
          "maxBytes": 100000000,
          "maxDurationMilliseconds": 300000,
          "safetyRatio": 0.92,
          "acceptedContainers": ["mp4"],
          "acceptedVideoCodecs": ["h264"],
          "acceptedAudioCodecs": ["aac"],
          "sourceURLs": ["https://official.example/rules"],
          "lastVerifiedAt": "2026-08-01T00:00:00Z",
          "expiresAt": "2026-08-31T00:00:00Z"
        }
        """
    }

    private static func date(_ string: String) -> Date {
        ISO8601DateFormatter().date(from: string)!
    }
}
