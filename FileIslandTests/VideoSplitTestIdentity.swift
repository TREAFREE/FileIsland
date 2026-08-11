import Foundation
@testable import FileIsland

func makeVideoSplitTestIdentity(
    byteCount: Int64,
    inode: UInt64 = 1
) -> VideoSplitFileIdentity {
    VideoSplitFileIdentity(
        device: 1,
        inode: inode,
        byteCount: byteCount,
        modificationSeconds: 1,
        modificationNanoseconds: 0
    )
}

func actualVideoSplitTestIdentity(
    at url: URL,
    expectedByteCount: Int64? = nil
) throws -> VideoSplitFileIdentity {
    try POSIXLocalRegularMediaFileValidator()
        .validate(url, expectedByteCount: expectedByteCount)
        .videoSplitIdentity
}
