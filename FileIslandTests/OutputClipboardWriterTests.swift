import AppKit
import Foundation
import Testing
@testable import FileIsland

@MainActor
struct OutputClipboardWriterTests {
    @Test
    func copiesOneLocalOutputWhenEnabled() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("OutputClipboardWriterTests-\(UUID().uuidString)")
        )
        defer { pasteboard.clearContents() }
        let outputURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("converted-\(UUID().uuidString).jpg")
        try Data([0x01]).write(to: outputURL)
        defer { try? FileManager.default.removeItem(at: outputURL) }

        let writer = AppKitOutputClipboardWriter(pasteboard: pasteboard)

        let copied = writer.copySingleOutputIfEligible(
            [outputURL],
            inputCount: 1,
            isEnabled: true
        )

        #expect(copied)
        let objects = try #require(
            pasteboard.readObjects(
                forClasses: [NSURL.self],
                options: [.urlReadingFileURLsOnly: true]
            ) as? [NSURL]
        )
        let copiedURL = try #require(objects.first as URL?)
        #expect(copiedURL.standardizedFileURL == outputURL.standardizedFileURL)
    }

    @Test
    func leavesClipboardUntouchedWhenAutomaticCopyIsDisabled() throws {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("OutputClipboardWriterTests-\(UUID().uuidString)")
        )
        defer { pasteboard.clearContents() }
        pasteboard.clearContents()
        pasteboard.setString("keep me", forType: .string)
        let writer = AppKitOutputClipboardWriter(pasteboard: pasteboard)

        let copied = writer.copySingleOutputIfEligible(
            [URL(fileURLWithPath: "/tmp/output.jpg")],
            inputCount: 1,
            isEnabled: false
        )

        #expect(copied == false)
        #expect(pasteboard.string(forType: .string) == "keep me")
    }

    @Test(arguments: [
        (inputCount: 2, outputCount: 1),
        (inputCount: 1, outputCount: 2),
        (inputCount: 0, outputCount: 1),
    ])
    func rejectsNonSingleFileResults(inputCount: Int, outputCount: Int) {
        let pasteboard = NSPasteboard(
            name: NSPasteboard.Name("OutputClipboardWriterTests-\(UUID().uuidString)")
        )
        defer { pasteboard.clearContents() }
        pasteboard.clearContents()
        pasteboard.setString("keep me", forType: .string)
        let writer = AppKitOutputClipboardWriter(pasteboard: pasteboard)
        let outputs = (0..<outputCount).map {
            URL(fileURLWithPath: "/tmp/output-\($0).jpg")
        }

        let copied = writer.copySingleOutputIfEligible(
            outputs,
            inputCount: inputCount,
            isEnabled: true
        )

        #expect(copied == false)
        #expect(pasteboard.string(forType: .string) == "keep me")
    }

    @Test
    func clipboardPreferenceDefaultsOffAndPersists() {
        let suite = "OutputClipboardWriterTests.Preferences-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.removePersistentDomain(forName: suite)

        let preferences = AppPreferences(defaults: defaults)
        #expect(preferences.copySingleOutputToClipboard == false)

        preferences.copySingleOutputToClipboard = true

        let restored = AppPreferences(defaults: defaults)
        #expect(restored.copySingleOutputToClipboard)
    }
}
