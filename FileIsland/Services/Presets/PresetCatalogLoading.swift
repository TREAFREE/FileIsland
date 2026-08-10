import Foundation

protocol PresetCatalogLoading: Sendable {
    func loadPresets() async throws -> [ConversionPreset]
}

enum PresetCatalogError: Error, Equatable, Sendable {
    case resourceMissing
    case unsupportedSchemaVersion(Int)
    case emptyCatalog
    case duplicateID(String)
    case invalidIdentity(String)
    case invalidVersion(String)
    case invalidConstraints(String)
    case invalidMediaConfiguration(String)
}

struct JSONPresetCatalogDecoder: Sendable {
    func decode(_ data: Data) throws -> [ConversionPreset] {
        let catalog = try JSONDecoder().decode(ConversionPresetCatalog.self, from: data)
        guard catalog.schemaVersion == 1 else {
            throw PresetCatalogError.unsupportedSchemaVersion(catalog.schemaVersion)
        }
        guard !catalog.presets.isEmpty else {
            throw PresetCatalogError.emptyCatalog
        }

        var identifiers: Set<String> = []
        for preset in catalog.presets {
            try validate(preset)
            guard identifiers.insert(preset.id).inserted else {
                throw PresetCatalogError.duplicateID(preset.id)
            }
        }
        return catalog.presets
    }

    private func validate(_ preset: ConversionPreset) throws {
        let trimmedID = preset.id.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedName = preset.displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedSummary = preset.summary.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedID.isEmpty,
              trimmedID == preset.id,
              !trimmedName.isEmpty,
              !trimmedSummary.isEmpty else {
            throw PresetCatalogError.invalidIdentity(preset.id)
        }
        guard preset.version > 0 else {
            throw PresetCatalogError.invalidVersion(preset.id)
        }
        guard preset.constraints.maxPixelDimension.map({ $0 > 0 }) ?? true,
              preset.constraints.maxBytes.map({ $0 > 0 }) ?? true else {
            throw PresetCatalogError.invalidConstraints(preset.id)
        }

        switch preset.mediaType {
        case .image:
            guard preset.output.imageFormat != nil,
                  preset.output.container == nil,
                  preset.output.videoCodec == nil,
                  preset.output.audioCodec == nil,
                  preset.output.compatibility == nil,
                  preset.constraints.maxResolution == nil,
                  preset.options.quality != nil,
                  preset.options.stripMetadata != nil else {
                throw PresetCatalogError.invalidMediaConfiguration(preset.id)
            }
        case .video:
            guard preset.output.imageFormat == nil,
                  preset.output.container == .mp4,
                  preset.output.videoCodec == .h264,
                  preset.output.audioCodec == .aac,
                  preset.output.compatibility == .highCompatibility,
                  preset.constraints.maxPixelDimension == nil,
                  preset.constraints.maxResolution != nil,
                  preset.options.quality != nil,
                  preset.options.stripMetadata == nil else {
                throw PresetCatalogError.invalidMediaConfiguration(preset.id)
            }
        }
    }
}

struct BundledPresetCatalogLoader: PresetCatalogLoading {
    private let resourceURL: URL?
    private let decoder: JSONPresetCatalogDecoder

    init(
        bundle: Bundle = .main,
        resourceName: String = "built-in-presets",
        decoder: JSONPresetCatalogDecoder = JSONPresetCatalogDecoder()
    ) {
        resourceURL = bundle.url(forResource: resourceName, withExtension: "json")
        self.decoder = decoder
    }

    init(
        resourceURL: URL?,
        decoder: JSONPresetCatalogDecoder = JSONPresetCatalogDecoder()
    ) {
        self.resourceURL = resourceURL
        self.decoder = decoder
    }

    func loadPresets() async throws -> [ConversionPreset] {
        guard let resourceURL else { throw PresetCatalogError.resourceMissing }
        return try await Task.detached(priority: .utility) {
            let data = try Data(contentsOf: resourceURL, options: .mappedIfSafe)
            return try decoder.decode(data)
        }.value
    }
}
