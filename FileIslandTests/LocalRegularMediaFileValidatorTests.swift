import Foundation
import Testing
@testable import FileIsland

struct LocalRegularMediaFileValidatorTests {
    @Test
    func validatesARegularFileAndChecksItsExpectedSize() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("input.mp4")
        try Data([0, 1, 2, 3]).write(to: file)

        let validator = POSIXLocalRegularMediaFileValidator()
        let identity = try validator.validate(file, expectedByteCount: 4)
        #expect(identity.byteCount == 4)

        expectValidationFailure(.fileSizeMismatch) {
            try validator.validate(file, expectedByteCount: 5)
        }
    }

    @Test
    func rejectsDirectoriesAndSymbolicLinksWithoutFollowingThem() throws {
        let directory = try makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appendingPathComponent("input.mp4")
        let link = directory.appendingPathComponent("linked.mp4")
        try Data([0]).write(to: file)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: file)

        let validator = POSIXLocalRegularMediaFileValidator()
        expectValidationFailure(.notRegularFile) {
            try validator.validate(directory, expectedByteCount: nil)
        }
        expectValidationFailure(.symbolicLink) {
            try validator.validate(link, expectedByteCount: 1)
        }
    }

    private func makeTemporaryDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("FileIsland-validator-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: false
        )
        return directory
    }

    private func expectValidationFailure<T>(
        _ expected: LocalRegularMediaFileValidationError,
        operation: () throws -> T
    ) {
        do {
            _ = try operation()
            Issue.record("Expected local-file validation failure: \(expected)")
        } catch let error as LocalRegularMediaFileValidationError {
            #expect(error == expected)
        } catch {
            Issue.record("Unexpected error: \(error)")
        }
    }
}
