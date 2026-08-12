import AppKit
import Foundation

@MainActor
protocol OutputClipboardWriting {
    @discardableResult
    func copySingleOutputIfEligible(
        _ outputURLs: [URL],
        inputCount: Int,
        isEnabled: Bool
    ) -> Bool
}

@MainActor
struct AppKitOutputClipboardWriter: OutputClipboardWriting {
    private let pasteboard: NSPasteboard

    init(pasteboard: NSPasteboard = .general) {
        self.pasteboard = pasteboard
    }

    @discardableResult
    func copySingleOutputIfEligible(
        _ outputURLs: [URL],
        inputCount: Int,
        isEnabled: Bool
    ) -> Bool {
        guard isEnabled,
              inputCount == 1,
              outputURLs.count == 1,
              let outputURL = outputURLs.first,
              outputURL.isFileURL,
              let values = try? outputURL.resourceValues(
                  forKeys: [.isRegularFileKey, .isSymbolicLinkKey]
              ),
              values.isRegularFile == true,
              values.isSymbolicLink != true else {
            return false
        }

        pasteboard.clearContents()
        return pasteboard.writeObjects([outputURL as NSURL])
    }
}
