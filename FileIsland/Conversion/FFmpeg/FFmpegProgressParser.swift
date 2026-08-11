import Foundation

struct FFmpegProgressRecord: Equatable, Sendable {
    let outTimeMicroseconds: Int64?
    let isFinished: Bool
}

struct FFmpegProgressParser: Sendable {
    private let maximumLineBytes: Int
    private var lineBuffer = Data()
    private var isDiscardingOversizedLine = false
    private var currentOutTimeMicroseconds: Int64?

    init(maximumLineBytes: Int = 4 * 1_024) {
        self.maximumLineBytes = max(1, maximumLineBytes)
    }

    mutating func consume(_ data: Data) -> [FFmpegProgressRecord] {
        var records: [FFmpegProgressRecord] = []
        var cursor = data.startIndex

        while cursor < data.endIndex {
            if isDiscardingOversizedLine {
                guard let newline = data[cursor...].firstIndex(of: 0x0A) else {
                    return records
                }
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
                    return records
                }
            } else {
                lineBuffer.append(contentsOf: fragment)
                if newline != nil {
                    let line = String(decoding: lineBuffer, as: UTF8.self)
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                    lineBuffer.removeAll(keepingCapacity: true)
                    consume(line: line, records: &records)
                }
            }

            guard let newline else { return records }
            cursor = data.index(after: newline)
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
