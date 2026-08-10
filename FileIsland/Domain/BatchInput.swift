import Foundation

enum InputSelection: Equatable, Sendable {
    case file(URL)
    case folder(URL)

    var url: URL {
        switch self {
        case let .file(url), let .folder(url): url
        }
    }

    var isFolder: Bool {
        if case .folder = self { return true }
        return false
    }
}

enum SafeRelativePathError: Error, Equatable, Sendable {
    case invalidPath
    case escapesRoot
}

struct SafeRelativePath: Equatable, Hashable, Sendable {
    let components: [String]

    init(_ string: String) throws {
        guard !string.isEmpty,
              !string.hasPrefix("/"),
              !string.hasPrefix("~") else {
            throw SafeRelativePathError.invalidPath
        }
        let components = string.split(
            separator: "/",
            omittingEmptySubsequences: false
        ).map(String.init)
        guard !components.isEmpty,
              components.allSatisfy({ !$0.isEmpty && $0 != "." && $0 != ".." }) else {
            throw SafeRelativePathError.invalidPath
        }
        self.components = components
    }

    var string: String { components.joined(separator: "/") }

    var parent: SafeRelativePath? {
        guard components.count > 1 else { return nil }
        return try? SafeRelativePath(components.dropLast().joined(separator: "/"))
    }

    func resolvedURL(relativeTo root: URL) throws -> URL {
        guard root.isFileURL else { throw SafeRelativePathError.invalidPath }
        let canonicalRoot = root.standardizedFileURL.resolvingSymlinksInPath()
        let candidate = components.reduce(root.standardizedFileURL) { partial, component in
            partial.appendingPathComponent(component, isDirectory: false)
        }
        let rootComponents = canonicalRoot.pathComponents

        var canonicalCursor = canonicalRoot
        for component in components {
            let next = canonicalCursor.appendingPathComponent(component, isDirectory: false)
            canonicalCursor = FileManager.default.fileExists(atPath: next.path)
                ? next.resolvingSymlinksInPath().standardizedFileURL
                : next.standardizedFileURL
            let cursorComponents = canonicalCursor.pathComponents
            guard cursorComponents.count > rootComponents.count,
                  cursorComponents.starts(with: rootComponents) else {
                throw SafeRelativePathError.escapesRoot
            }
        }
        return candidate
    }
}

struct BatchInput: Identifiable, Equatable, Sendable {
    var id: UUID { file.id }
    let file: InputFile
    let selection: InputSelection
    let relativePath: SafeRelativePath
}

struct InputScanResult: Equatable, Sendable {
    let selections: [InputSelection]
    let inputs: [BatchInput]

    var files: [InputFile] { inputs.map(\.file) }
    var containsFolderRoot: Bool { selections.contains(where: \.isFolder) }
}
