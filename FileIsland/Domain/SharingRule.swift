import Foundation

enum SharingVideoContainer: String, Codable, Equatable, Hashable, Sendable {
    case mp4
}

enum SharingVideoCodec: String, Codable, Equatable, Hashable, Sendable {
    case h264
}

enum SharingAudioCodec: String, Codable, Equatable, Hashable, Sendable {
    case aac
}

struct SharingRuleCatalog: Codable, Equatable, Sendable {
    let schemaVersion: Int
    let catalogVersion: String
    let rules: [SharingRule]
}

struct SharingRule: Codable, Equatable, Identifiable, Sendable {
    let id: String
    let revision: Int
    let platform: String
    let channel: String
    let displayName: String
    let maxBytes: Int64?
    let maxDurationMilliseconds: Int64?
    let safetyRatio: Double
    let acceptedContainers: [SharingVideoContainer]
    let acceptedVideoCodecs: [SharingVideoCodec]
    let acceptedAudioCodecs: [SharingAudioCodec]
    let sourceURLs: [URL]
    let lastVerifiedAt: Date
    let expiresAt: Date

    var snapshot: SharingRuleSnapshot {
        SharingRuleSnapshot(rule: self)
    }
}

struct SharingRuleSnapshot: Codable, Equatable, Sendable {
    let id: String
    let revision: Int
    let platform: String
    let channel: String
    let displayName: String
    let maxBytes: Int64?
    let maxDurationMilliseconds: Int64?
    let safetyRatio: Double
    let acceptedContainers: [SharingVideoContainer]
    let acceptedVideoCodecs: [SharingVideoCodec]
    let acceptedAudioCodecs: [SharingAudioCodec]
    let sourceURLs: [URL]
    let lastVerifiedAt: Date
    let expiresAt: Date

    init(rule: SharingRule) {
        id = rule.id
        revision = rule.revision
        platform = rule.platform
        channel = rule.channel
        displayName = rule.displayName
        maxBytes = rule.maxBytes
        maxDurationMilliseconds = rule.maxDurationMilliseconds
        safetyRatio = rule.safetyRatio
        acceptedContainers = rule.acceptedContainers
        acceptedVideoCodecs = rule.acceptedVideoCodecs
        acceptedAudioCodecs = rule.acceptedAudioCodecs
        sourceURLs = rule.sourceURLs
        lastVerifiedAt = rule.lastVerifiedAt
        expiresAt = rule.expiresAt
    }
}
