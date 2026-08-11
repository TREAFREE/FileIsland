import Foundation

protocol SharingRuleCatalogLoading: Sendable {
    func loadCatalog() async throws -> SharingRuleCatalog
}

extension SharingRuleCatalogLoading {
    func loadRules() async throws -> [SharingRule] {
        try await loadCatalog().rules
    }
}

enum SharingRuleCatalogError: Error, Equatable, Sendable {
    case resourceMissing
    case unsupportedSchemaVersion(Int)
    case invalidCatalogVersion(String)
    case invalidIdentity(String)
    case invalidRevision(String)
    case duplicateRule(id: String, revision: Int)
    case duplicateStableID(String)
    case invalidConstraints(String)
    case invalidSafetyRatio(String)
    case invalidAcceptedFormats(String)
    case missingSources(String)
    case insecureSource(id: String, url: String)
    case verificationInFuture(String)
    case expiryBeforeVerification(String)
    case validityWindowTooLong(String)
    case expiredRule(String)
}

struct JSONSharingRuleCatalogDecoder: Sendable {
    private static let supportedSchemaVersion = 1
    private static let maximumValidityInterval: TimeInterval = 90 * 24 * 60 * 60

    private let now: @Sendable () -> Date

    init(now: @escaping @Sendable () -> Date = { Date() }) {
        self.now = now
    }

    func decode(_ data: Data) throws -> SharingRuleCatalog {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let catalog = try decoder.decode(SharingRuleCatalog.self, from: data)

        return try validate(catalog)
    }

    func validate(_ catalog: SharingRuleCatalog) throws -> SharingRuleCatalog {

        guard catalog.schemaVersion == Self.supportedSchemaVersion else {
            throw SharingRuleCatalogError.unsupportedSchemaVersion(catalog.schemaVersion)
        }
        guard isCanonicalNonBlank(catalog.catalogVersion) else {
            throw SharingRuleCatalogError.invalidCatalogVersion(catalog.catalogVersion)
        }

        let validationDate = now()
        var identities: Set<RuleIdentity> = []
        var stableIDs: Set<String> = []

        for rule in catalog.rules {
            try validate(rule, at: validationDate)

            let identity = RuleIdentity(id: rule.id, revision: rule.revision)
            guard identities.insert(identity).inserted else {
                throw SharingRuleCatalogError.duplicateRule(
                    id: rule.id,
                    revision: rule.revision
                )
            }
            guard stableIDs.insert(rule.id).inserted else {
                throw SharingRuleCatalogError.duplicateStableID(rule.id)
            }
        }

        return catalog
    }

    private func validate(_ rule: SharingRule, at validationDate: Date) throws {
        guard isCanonicalNonBlank(rule.id),
              isCanonicalNonBlank(rule.platform),
              isCanonicalNonBlank(rule.channel),
              isCanonicalNonBlank(rule.displayName) else {
            throw SharingRuleCatalogError.invalidIdentity(rule.id)
        }
        guard rule.revision > 0 else {
            throw SharingRuleCatalogError.invalidRevision(rule.id)
        }
        guard rule.maxBytes != nil || rule.maxDurationMilliseconds != nil,
              rule.maxBytes.map({ $0 > 0 }) ?? true,
              rule.maxDurationMilliseconds.map({ $0 > 0 }) ?? true else {
            throw SharingRuleCatalogError.invalidConstraints(rule.id)
        }
        guard rule.safetyRatio.isFinite,
              (0.80...0.98).contains(rule.safetyRatio) else {
            throw SharingRuleCatalogError.invalidSafetyRatio(rule.id)
        }
        guard hasUniqueValues(rule.acceptedContainers),
              hasUniqueValues(rule.acceptedVideoCodecs),
              hasUniqueValues(rule.acceptedAudioCodecs) else {
            throw SharingRuleCatalogError.invalidAcceptedFormats(rule.id)
        }
        guard !rule.sourceURLs.isEmpty else {
            throw SharingRuleCatalogError.missingSources(rule.id)
        }
        for sourceURL in rule.sourceURLs {
            guard sourceURL.scheme?.lowercased() == "https",
                  sourceURL.host?.isEmpty == false else {
                throw SharingRuleCatalogError.insecureSource(
                    id: rule.id,
                    url: sourceURL.absoluteString
                )
            }
        }
        guard rule.lastVerifiedAt <= validationDate else {
            throw SharingRuleCatalogError.verificationInFuture(rule.id)
        }
        guard rule.expiresAt > rule.lastVerifiedAt else {
            throw SharingRuleCatalogError.expiryBeforeVerification(rule.id)
        }
        guard rule.expiresAt.timeIntervalSince(rule.lastVerifiedAt)
            <= Self.maximumValidityInterval else {
            throw SharingRuleCatalogError.validityWindowTooLong(rule.id)
        }
        guard rule.expiresAt > validationDate else {
            throw SharingRuleCatalogError.expiredRule(rule.id)
        }
    }

    private func isCanonicalNonBlank(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == value
    }

    private func hasUniqueValues<Value: Hashable>(_ values: [Value]) -> Bool {
        !values.isEmpty && Set(values).count == values.count
    }
}

struct BundledSharingRuleCatalogLoader: SharingRuleCatalogLoading {
    private let resourceURL: URL?
    private let decoder: JSONSharingRuleCatalogDecoder

    init(
        bundle: Bundle = .main,
        resourceName: String = "sharing-rules",
        decoder: JSONSharingRuleCatalogDecoder = JSONSharingRuleCatalogDecoder()
    ) {
        resourceURL = bundle.url(forResource: resourceName, withExtension: "json")
            ?? bundle.url(
                forResource: resourceName,
                withExtension: "json",
                subdirectory: "SharingRules"
            )
        self.decoder = decoder
    }

    init(
        resourceURL: URL?,
        decoder: JSONSharingRuleCatalogDecoder = JSONSharingRuleCatalogDecoder()
    ) {
        self.resourceURL = resourceURL
        self.decoder = decoder
    }

    func loadCatalog() async throws -> SharingRuleCatalog {
        guard let resourceURL else {
            throw SharingRuleCatalogError.resourceMissing
        }

        return try await Task.detached(priority: .utility) {
            let data = try Data(contentsOf: resourceURL, options: .mappedIfSafe)
            return try decoder.decode(data)
        }.value
    }
}

private struct RuleIdentity: Hashable, Sendable {
    let id: String
    let revision: Int
}
