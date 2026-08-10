import Foundation

enum CLIResourceError: Error, Equatable, Sendable {
    case presetCatalogMissing
    case ffmpegMissing
}

struct CLIResourceLocator: Sendable {
    let executableURL: URL

    func presetCatalogURL() throws -> URL {
        let url = resourceURL(named: "built-in-presets.json")
        guard FileManager.default.isReadableFile(atPath: url.path) else {
            throw CLIResourceError.presetCatalogMissing
        }
        return url
    }

    func ffmpegExecutableURL() throws -> URL {
        let url = resourceURL(named: "ffmpeg")
        guard FileManager.default.isExecutableFile(atPath: url.path) else {
            throw CLIResourceError.ffmpegMissing
        }
        return url
    }

    private func resourceURL(named name: String) -> URL {
        executableURL.standardizedFileURL.deletingLastPathComponent()
            .appendingPathComponent(name, isDirectory: false)
    }
}
