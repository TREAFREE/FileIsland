import Foundation

struct FFmpegProgressRecord: Equatable, Sendable {
    let outTimeMicroseconds: Int64?
    let isFinished: Bool
}

struct FFmpegProgressParser: Sendable {
    private var lineBuffer = Data()
    private var currentOutTimeMicroseconds: Int64?

    mutating func consume(_ data: Data) -> [FFmpegProgressRecord] {
        lineBuffer.append(data)
        var records: [FFmpegProgressRecord] = []

        while let newlineIndex = lineBuffer.firstIndex(of: 0x0A) {
            let lineData = lineBuffer[..<newlineIndex]
            lineBuffer.removeSubrange(...newlineIndex)
            let line = String(decoding: lineData, as: UTF8.self)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            consume(line: line, records: &records)
        }
        return records
    }

    private mutating func consume(
        line: String,
        records: inout [FFmpegProgressRecord]
    ) {
        guard let separator = line.firstIndex(of: "=") else { return }
        let key = String(line[..<separator])
        let value = String(line[line.index(after: separator)...])

        switch key {
        case "out_time_us", "out_time_ms":
            currentOutTimeMicroseconds = Int64(value)
        case "progress" where value == "continue" || value == "end":
            records.append(FFmpegProgressRecord(
                outTimeMicroseconds: currentOutTimeMicroseconds,
                isFinished: value == "end"
            ))
            currentOutTimeMicroseconds = nil
        default:
            break
        }
    }
}
