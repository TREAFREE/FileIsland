import Foundation

struct FFprobeKeyframeParser: Sendable {
    private let maximumLineBytes: Int
    private let maximumRecords: Int
    private let maximumKeyframes: Int
    private var lineBuffer = Data()
    private var recordCount = 0
    private var keyframeSeconds: [Decimal] = []

    init(
        maximumLineBytes: Int = 4_096,
        maximumRecords: Int = 4_000_000,
        maximumKeyframes: Int = 500_000
    ) {
        self.maximumLineBytes = maximumLineBytes
        self.maximumRecords = maximumRecords
        self.maximumKeyframes = maximumKeyframes
    }

    mutating func consume(_ data: Data) throws {
        guard !data.isEmpty else { return }
        lineBuffer.append(data)

        while let newline = lineBuffer.firstIndex(of: 0x0A) {
            let line = Data(lineBuffer[..<newline])
            lineBuffer.removeSubrange(...newline)
            try parse(line)
        }
        guard lineBuffer.count <= maximumLineBytes else {
            throw FFprobeParsingError.lineTooLong
        }
    }

    mutating func finalize(metadata: FFprobeMetadata) throws -> [Int64] {
        if !lineBuffer.isEmpty {
            let finalLine = lineBuffer
            lineBuffer.removeAll(keepingCapacity: false)
            try parse(finalLine)
        }
        guard let first = keyframeSeconds.first else {
            throw FFprobeParsingError.unsupportedMedia
        }

        let firstOffset = NSDecimalNumber(
            decimal: (first - metadata.timelineOriginSeconds) * Decimal(1_000)
        ).doubleValue
        let originTolerance = metadata.frameDurationMilliseconds / 2
        guard firstOffset.isFinite,
              abs(firstOffset) <= originTolerance + 0.000_001 else {
            throw FFprobeParsingError.unsupportedMedia
        }

        var result: [Int64] = []
        result.reserveCapacity(keyframeSeconds.count)
        var previousRaw: Decimal?
        for (index, rawSeconds) in keyframeSeconds.enumerated() {
            if let previousRaw, rawSeconds <= previousRaw {
                throw FFprobeParsingError.malformedOutput
            }
            previousRaw = rawSeconds

            let milliseconds: Int64
            if index == 0 {
                milliseconds = 0
            } else {
                milliseconds = try checkedMilliseconds(
                    rawSeconds - metadata.timelineOriginSeconds
                )
            }
            guard milliseconds >= 0,
                  milliseconds < metadata.durationMilliseconds,
                  result.last.map({ milliseconds > $0 }) ?? true else {
                throw FFprobeParsingError.unsupportedMedia
            }
            result.append(milliseconds)
        }
        return result
    }

    private mutating func parse(_ rawLine: Data) throws {
        var line = rawLine
        if line.last == 0x0D { line.removeLast() }
        guard !line.isEmpty else { return }
        guard line.count <= maximumLineBytes else {
            throw FFprobeParsingError.lineTooLong
        }

        recordCount += 1
        guard recordCount <= maximumRecords else {
            throw FFprobeParsingError.tooManyRecords
        }

        let text = String(decoding: line, as: UTF8.self)
        var fields: [Substring: Substring] = [:]
        for component in text.split(separator: "|", omittingEmptySubsequences: false) {
            let pair = component.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
            guard pair.count == 2 else {
                if component == "packet" { continue }
                throw FFprobeParsingError.malformedOutput
            }
            fields[pair[0]] = pair[1]
        }
        guard let timestamp = fields["pts_time"],
              let flags = fields["flags"] else {
            throw FFprobeParsingError.malformedOutput
        }
        guard flags.contains("K") else { return }
        guard let seconds = Decimal(
            string: String(timestamp),
            locale: Locale(identifier: "en_US_POSIX")
        ), seconds.isFinite else {
            throw FFprobeParsingError.malformedOutput
        }
        keyframeSeconds.append(seconds)
        guard keyframeSeconds.count <= maximumKeyframes else {
            throw FFprobeParsingError.tooManyRecords
        }
    }

    private func checkedMilliseconds(_ seconds: Decimal) throws -> Int64 {
        var scaled = seconds * Decimal(1_000)
        guard scaled.isFinite else { throw FFprobeParsingError.arithmeticOverflow }
        var rounded = Decimal()
        NSDecimalRound(&rounded, &scaled, 0, .plain)
        guard rounded >= 0, rounded <= Decimal(Int64.max) else {
            throw FFprobeParsingError.arithmeticOverflow
        }
        return NSDecimalNumber(decimal: rounded).int64Value
    }
}
