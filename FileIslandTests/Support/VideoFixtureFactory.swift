import AVFoundation
import CoreMedia
import CoreVideo
import Foundation

struct VideoFixtureInfo: Sendable {
    let duration: Double
    let displaySize: CGSize
    let videoCodec: FourCharCode?
    let audioCodec: FourCharCode?
    let isPlayable: Bool
}

@MainActor
enum VideoFixtureFactory {
    static func writeMovie(
        to outputURL: URL,
        fileType: AVFileType,
        width: Int = 160,
        height: Int = 90,
        duration: Double = 1,
        withAudio: Bool = true,
        rotationDegrees: Int = 0
    ) async throws {
        let workspace = outputURL.deletingLastPathComponent()
            .appendingPathComponent("fixture-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: workspace, withIntermediateDirectories: false)
        defer { try? FileManager.default.removeItem(at: workspace) }

        let videoURL = workspace.appendingPathComponent("video.mov")
        try await writeVideo(
            to: videoURL,
            width: width,
            height: height,
            duration: duration,
            rotationDegrees: rotationDegrees
        )

        let composition = AVMutableComposition()
        let videoAsset = AVURLAsset(url: videoURL)
        let videoDuration = try await videoAsset.load(.duration)
        guard let sourceVideoTrack = try await videoAsset.loadTracks(withMediaType: .video).first,
              let compositionVideoTrack = composition.addMutableTrack(
                withMediaType: .video,
                preferredTrackID: kCMPersistentTrackID_Invalid
              ) else {
            throw FixtureError.couldNotCreateMedia
        }
        try compositionVideoTrack.insertTimeRange(
            CMTimeRange(start: .zero, duration: videoDuration),
            of: sourceVideoTrack,
            at: .zero
        )
        compositionVideoTrack.preferredTransform = try await sourceVideoTrack.load(.preferredTransform)

        if withAudio {
            let audioURL = workspace.appendingPathComponent("tone.wav")
            try writeTone(to: audioURL, duration: duration)
            let audioAsset = AVURLAsset(url: audioURL)
            guard let sourceAudioTrack = try await audioAsset.loadTracks(withMediaType: .audio).first,
                  let compositionAudioTrack = composition.addMutableTrack(
                    withMediaType: .audio,
                    preferredTrackID: kCMPersistentTrackID_Invalid
                  ) else {
                throw FixtureError.couldNotCreateMedia
            }
            try compositionAudioTrack.insertTimeRange(
                CMTimeRange(start: .zero, duration: videoDuration),
                of: sourceAudioTrack,
                at: .zero
            )
        }

        let preset = fileType == .mov
            ? AVAssetExportPresetPassthrough
            : AVAssetExportPreset1280x720
        guard let exporter = AVAssetExportSession(asset: composition, presetName: preset) else {
            throw FixtureError.couldNotCreateMedia
        }
        try? FileManager.default.removeItem(at: outputURL)
        try await exporter.export(to: outputURL, as: fileType)
    }

    static func inspect(_ url: URL) async throws -> VideoFixtureInfo {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        let isPlayable = try await asset.load(.isPlayable)
        guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
            throw FixtureError.couldNotCreateMedia
        }
        let naturalSize = try await videoTrack.load(.naturalSize)
        let transform = try await videoTrack.load(.preferredTransform)
        let displayRect = CGRect(origin: .zero, size: naturalSize)
            .applying(transform)
            .standardized
        let videoCodec = try await codec(of: videoTrack)
        let audioTrack = try await asset.loadTracks(withMediaType: .audio).first
        let audioCodec: FourCharCode?
        if let audioTrack {
            audioCodec = try await codec(of: audioTrack)
        } else {
            audioCodec = nil
        }

        return VideoFixtureInfo(
            duration: duration,
            displaySize: displayRect.size,
            videoCodec: videoCodec,
            audioCodec: audioCodec,
            isPlayable: isPlayable
        )
    }

    private static func writeVideo(
        to url: URL,
        width: Int,
        height: Int,
        duration: Double,
        rotationDegrees: Int
    ) async throws {
        let writer = try AVAssetWriter(outputURL: url, fileType: .mov)
        let input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: width,
                AVVideoHeightKey: height,
                AVVideoCompressionPropertiesKey: [
                    AVVideoAverageBitRateKey: 600_000,
                    AVVideoExpectedSourceFrameRateKey: 30
                ]
            ]
        )
        input.expectsMediaDataInRealTime = false
        if rotationDegrees == 90 {
            input.transform = CGAffineTransform(translationX: CGFloat(height), y: 0)
                .rotated(by: .pi / 2)
        }
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ]
        )
        guard writer.canAdd(input) else { throw FixtureError.couldNotCreateMedia }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? FixtureError.couldNotCreateMedia }
        writer.startSession(atSourceTime: .zero)

        let frameCount = max(1, Int(ceil(duration * 30)))
        for frame in 0..<frameCount {
            while !input.isReadyForMoreMediaData { await Task.yield() }
            guard let pool = adaptor.pixelBufferPool else { throw FixtureError.couldNotCreateMedia }
            var optionalBuffer: CVPixelBuffer?
            guard CVPixelBufferPoolCreatePixelBuffer(nil, pool, &optionalBuffer) == kCVReturnSuccess,
                  let buffer = optionalBuffer else {
                throw FixtureError.couldNotCreateMedia
            }
            fill(buffer, frame: frame)
            guard adaptor.append(
                buffer,
                withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: 30)
            ) else {
                throw writer.error ?? FixtureError.couldNotCreateMedia
            }
        }
        input.markAsFinished()
        await writer.finishWriting()
        guard writer.status == .completed else {
            throw writer.error ?? FixtureError.couldNotCreateMedia
        }
    }

    private static func fill(_ buffer: CVPixelBuffer, frame: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let baseAddress = CVPixelBufferGetBaseAddress(buffer) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(buffer)
        let height = CVPixelBufferGetHeight(buffer)
        let blue = UInt8((frame * 13) % 255)
        let green = UInt8((frame * 7 + 60) % 255)
        let red = UInt8((frame * 3 + 120) % 255)
        for row in 0..<height {
            let pixels = baseAddress.advanced(by: row * bytesPerRow)
                .assumingMemoryBound(to: UInt8.self)
            for column in stride(from: 0, to: bytesPerRow, by: 4) {
                pixels[column] = blue
                pixels[column + 1] = green
                pixels[column + 2] = red
                pixels[column + 3] = 255
            }
        }
    }

    private static func writeTone(to url: URL, duration: Double) throws {
        let sampleRate = 44_100.0
        guard let format = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: sampleRate,
            channels: 1,
            interleaved: false
        ) else {
            throw FixtureError.couldNotCreateMedia
        }
        let frameCount = AVAudioFrameCount(max(1, Int(duration * sampleRate)))
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channel = buffer.floatChannelData?[0] else {
            throw FixtureError.couldNotCreateMedia
        }
        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            channel[frame] = Float(sin(2 * .pi * 440 * Double(frame) / sampleRate) * 0.15)
        }
        let file = try AVAudioFile(
            forWriting: url,
            settings: format.settings,
            commonFormat: .pcmFormatFloat32,
            interleaved: false
        )
        try file.write(from: buffer)
    }

    private static func codec(of track: AVAssetTrack) async throws -> FourCharCode? {
        let descriptions = try await track.load(.formatDescriptions)
        return descriptions.first.map(CMFormatDescriptionGetMediaSubType)
    }
}

private enum FixtureError: Error {
    case couldNotCreateMedia
}
