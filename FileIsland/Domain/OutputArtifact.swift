import Foundation

enum OutputArtifactRole: Hashable, Codable, Sendable {
    case converted
    case videoSegment(ordinal: Int, total: Int)

    private enum CodingKeys: String, CodingKey {
        case kind
        case ordinal
        case total
    }

    private enum Kind: String, Codable {
        case converted
        case videoSegment
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .converted:
            self = .converted
        case .videoSegment:
            self = .videoSegment(
                ordinal: try container.decode(Int.self, forKey: .ordinal),
                total: try container.decode(Int.self, forKey: .total)
            )
        }
    }

    func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .converted:
            try container.encode(Kind.converted, forKey: .kind)
        case let .videoSegment(ordinal, total):
            try container.encode(Kind.videoSegment, forKey: .kind)
            try container.encode(ordinal, forKey: .ordinal)
            try container.encode(total, forKey: .total)
        }
    }
}

struct OutputArtifactID: Hashable, Codable, Sendable {
    let sourceInputID: UUID
    let role: OutputArtifactRole
}

struct PlannedOutputArtifact: Equatable, Sendable {
    let id: OutputArtifactID
    let preferredRelativePath: SafeRelativePath
}

struct StagedOutputArtifact: Equatable, Sendable {
    let id: OutputArtifactID
    let fileURL: URL
}

struct PublishedOutputArtifact: Equatable, Sendable {
    let id: OutputArtifactID
    let fileURL: URL
}

struct EngineExecutionResult: Equatable, Sendable, RandomAccessCollection {
    typealias Index = Array<StagedOutputArtifact>.Index
    typealias Element = URL

    let artifacts: [StagedOutputArtifact]

    var outputURLs: [URL] {
        artifacts.map(\.fileURL)
    }

    var startIndex: Index { artifacts.startIndex }
    var endIndex: Index { artifacts.endIndex }

    subscript(position: Index) -> URL {
        artifacts[position].fileURL
    }

    func index(after index: Index) -> Index {
        artifacts.index(after: index)
    }

    func index(before index: Index) -> Index {
        artifacts.index(before: index)
    }
}
