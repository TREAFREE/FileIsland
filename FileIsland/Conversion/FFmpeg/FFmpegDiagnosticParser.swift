import Foundation

struct FFmpegSourceMetadata: Equatable, Sendable {
    var duration: Double?
    var hasAudio = false
    var displaySize: CGSize?
    var rotationDegrees = 0.0

    var orientedDisplaySize: CGSize? {
        guard let displaySize else { return nil }
        let normalizedRotation = abs(rotationDegrees).truncatingRemainder(dividingBy: 180)
        if abs(normalizedRotation - 90) < 1 {
            return CGSize(width: displaySize.height, height: displaySize.width)
        }
        return displaySize
    }
}

struct FFmpegDiagnosticParser: Sendable {
    private let sensitivePaths: [String]
    private let maximumDiagnosticCharacters: Int
    private let maximumLineBytes: Int
    private var lineBuffer = Data()
    private var isDiscardingOversizedLine = false
    private(set) var metadata = FFmpegSourceMetadata()
    private(set) var diagnostic = ""

    init(
        sensitivePaths: [String],
        maximumDiagnosticCharacters: Int = 4_096,
        maximumLineBytes: Int = 64 * 1_024
    ) {
        self.sensitivePaths = sensitivePaths.filter { !$0.isEmpty }
        self.maximumDiagnosticCharacters = max(1, maximumDiagnosticCharacters)
        self.maximumLineBytes = max(1, maximumLineBytes)
    }

    mutating func consume(_ data: Data) {
        appendDiagnostic(String(decoding: data, as: UTF8.self))
        var cursor = data.startIndex

        while cursor < data.endIndex {
            if isDiscardingOversizedLine {
                guard let newline = data[cursor...].firstIndex(of: 0x0A) else { return }
                isDiscardingOversizedLine = false
                cursor = data.index(after: newline)
                continue
            }

            let newline = data[cursor...].firstIndex(of: 0x0A)
            let end = newline ?? data.endIndex
            let fragment = data[cursor..<end]

            if fragment.count > maximumLineBytes - lineBuffer.count {
                lineBuffer.removeAll(keepingCapacity: true)
                if newline == nil {
                    isDiscardingOversizedLine = true
                    return
                }
            } else {
                lineBuffer.append(contentsOf: fragment)
                if newline != nil {
                    parse(line: String(decoding: lineBuffer, as: UTF8.self))
                    lineBuffer.removeAll(keepingCapacity: true)
                }
            }

            guard let newline else { return }
            cursor = data.index(after: newline)
        }
    }

    private mutating func parse(line: String) {
        if metadata.duration == nil,
           let markerRange = line.range(of: "Duration:") {
            let remainder = line[markerRange.upperBound...]
                .trimmingCharacters(in: .whitespaces)
            let token = remainder.split(separator: ",", maxSplits: 1).first.map(String.init) ?? ""
            let components = token.split(separator: ":").compactMap { Double($0) }
            if components.count == 3 {
                let duration = components[0] * 3_600 + components[1] * 60 + components[2]
                if duration.isFinite, duration > 0 {
                    metadata.duration = duration
                }
            }
        }

        if line.contains("Stream #"), line.contains("Audio:") {
            metadata.hasAudio = true
        }

        if metadata.displaySize == nil,
           line.contains("Stream #"),
           line.contains("Video:") {
            for rawToken in line.split(whereSeparator: { $0.isWhitespace }) {
                let token = rawToken.trimmingCharacters(in: .punctuationCharacters)
                let dimensions = token.split(separator: "x", maxSplits: 1)
                guard dimensions.count == 2,
                      let width = Double(dimensions[0]),
                      let height = Double(dimensions[1]),
                      width > 0,
                      height > 0 else { continue }
                metadata.displaySize = CGSize(width: width, height: height)
                break
            }
        }

        if let rotationRange = line.range(of: "rotation of ") {
            let rotationText = line[rotationRange.upperBound...]
                .split(whereSeparator: { $0.isWhitespace })
                .first
            if let rotationText, let rotation = Double(rotationText) {
                metadata.rotationDegrees = rotation
            }
        }
    }

    private mutating func appendDiagnostic(_ text: String) {
        diagnostic.append(text)
        for path in sensitivePaths {
            diagnostic = diagnostic.replacingOccurrences(of: path, with: "<path>")
        }
        if diagnostic.count > maximumDiagnosticCharacters {
            diagnostic = String(diagnostic.suffix(maximumDiagnosticCharacters))
        }
    }
}
