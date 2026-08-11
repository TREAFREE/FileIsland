import AVFoundation
import CoreMedia
import CoreVideo
import Darwin
import Foundation

/// A deliberately tiny crash/timeout boundary around AVFoundation's
/// synchronous first-sample decode call.
///
/// The parent process passes only an application-controlled staging file and
/// treats every non-success exit as an undecodable segment. This executable
/// never prints the input path or an underlying framework diagnostic.
@main
enum FileIslandMediaValidatorEntry {
    private static let acceptedResponse = Data(
        "{\"decodable\":true,\"schemaVersion\":1}\n".utf8
    )
    private static let rejectedResponse = Data(
        "{\"decodable\":false,\"schemaVersion\":1}\n".utf8
    )

    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        guard arguments.count == 2,
              arguments[0] == "--first-frame",
              arguments[1].hasPrefix("/") else {
            finish(decodable: false, exitCode: EX_USAGE)
        }

        let fileURL = URL(fileURLWithPath: arguments[1], isDirectory: false)
        let initialIdentity: FileIdentity
        do {
            initialIdentity = try validateLocalRegularFile(fileURL)
        } catch {
            finish(decodable: false, exitCode: 2)
        }

        let decodable = await decodeFirstFrame(at: fileURL)
        guard decodable,
              (try? validateLocalRegularFile(fileURL)) == initialIdentity else {
            finish(decodable: false, exitCode: 2)
        }
        finish(decodable: true, exitCode: 0)
    }

    private static func decodeFirstFrame(at fileURL: URL) async -> Bool {
        do {
            let asset = AVURLAsset(url: fileURL)
            guard let track = try await asset.loadTracks(withMediaType: .video).first else {
                return false
            }
            let reader = try AVAssetReader(asset: asset)
            let output = AVAssetReaderTrackOutput(
                track: track,
                outputSettings: [
                    kCVPixelBufferPixelFormatTypeKey as String:
                        Int(kCVPixelFormatType_32BGRA)
                ]
            )
            output.alwaysCopiesSampleData = false
            guard reader.canAdd(output) else { return false }
            reader.add(output)
            guard reader.startReading() else { return false }
            defer { reader.cancelReading() }

            // This API may block in a system decoder. It is intentionally the
            // only potentially unbounded call and lives in this killable child.
            guard let sampleBuffer = output.copyNextSampleBuffer() else {
                return false
            }
            return CMSampleBufferIsValid(sampleBuffer)
                && CMSampleBufferDataIsReady(sampleBuffer)
                && CMSampleBufferGetImageBuffer(sampleBuffer) != nil
        } catch {
            return false
        }
    }

    private static func validateLocalRegularFile(_ fileURL: URL) throws -> FileIdentity {
        guard fileURL.isFileURL else { throw InputError.rejected }
        return try fileURL.withUnsafeFileSystemRepresentation { path in
            guard let path else { throw InputError.rejected }
            var pathStatus = stat()
            guard lstat(path, &pathStatus) == 0,
                  pathStatus.st_mode & S_IFMT != S_IFLNK,
                  pathStatus.st_mode & S_IFMT == S_IFREG else {
                throw InputError.rejected
            }

            let descriptor = open(path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw InputError.rejected }
            defer { _ = close(descriptor) }

            var openedStatus = stat()
            guard fstat(descriptor, &openedStatus) == 0,
                  openedStatus.st_mode & S_IFMT == S_IFREG,
                  pathStatus.st_dev == openedStatus.st_dev,
                  pathStatus.st_ino == openedStatus.st_ino,
                  pathStatus.st_size == openedStatus.st_size,
                  pathStatus.st_mtimespec.tv_sec == openedStatus.st_mtimespec.tv_sec,
                  pathStatus.st_mtimespec.tv_nsec == openedStatus.st_mtimespec.tv_nsec else {
                throw InputError.rejected
            }
            return FileIdentity(
                device: UInt64(openedStatus.st_dev),
                inode: UInt64(openedStatus.st_ino),
                byteCount: Int64(openedStatus.st_size),
                modificationSeconds: Int64(openedStatus.st_mtimespec.tv_sec),
                modificationNanoseconds: Int64(openedStatus.st_mtimespec.tv_nsec)
            )
        }
    }

    private static func finish(decodable: Bool, exitCode: Int32) -> Never {
        FileHandle.standardOutput.write(decodable ? acceptedResponse : rejectedResponse)
        Darwin.exit(exitCode)
    }
}

private struct FileIdentity: Equatable {
    let device: UInt64
    let inode: UInt64
    let byteCount: Int64
    let modificationSeconds: Int64
    let modificationNanoseconds: Int64
}

private enum InputError: Error {
    case rejected
}
