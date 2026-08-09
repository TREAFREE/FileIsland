import Foundation
import XCTest
@testable import FileIsland

final class FFmpegProgressParserTests: XCTestCase {
    func testParsesFragmentedMachineReadableRecords() {
        var parser = FFmpegProgressParser()

        XCTAssertEqual(parser.consume(Data("frame=12\nout_time_".utf8)), [])
        let first = parser.consume(Data("us=2500000\nprogress=continue\n".utf8))
        let second = parser.consume(Data("out_time_us=5000000\nprogress=end\n".utf8))

        XCTAssertEqual(first, [FFmpegProgressRecord(outTimeMicroseconds: 2_500_000, isFinished: false)])
        XCTAssertEqual(second, [FFmpegProgressRecord(outTimeMicroseconds: 5_000_000, isFinished: true)])
    }

    func testIgnoresInvalidValuesAndNeverCarriesTimeAcrossRecords() {
        var parser = FFmpegProgressParser()

        let records = parser.consume(Data(
            "out_time_us=invalid\nprogress=continue\nprogress=end\n".utf8
        ))

        XCTAssertEqual(records, [
            FFmpegProgressRecord(outTimeMicroseconds: nil, isFinished: false),
            FFmpegProgressRecord(outTimeMicroseconds: nil, isFinished: true)
        ])
    }
}
