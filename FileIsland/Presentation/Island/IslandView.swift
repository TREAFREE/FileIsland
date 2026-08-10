import AppKit
import SwiftUI

struct IslandView: View {
    @Bindable var viewModel: IslandViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            if viewModel.presentationMode == .physicalNotch {
                notchWingContent
                    .frame(height: viewModel.notchOcclusionHeight)
            }
            if !isPhysicalNotchIdle {
                stateContent
                    .id(viewModel.state.visualPhase)
                    .transition(contentTransition)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 9)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
        .background { islandBackground }
        .overlay {
            IslandProgressBorder(
                visual: IslandProgressVisual(
                    state: viewModel.state,
                    reduceMotion: reduceMotion
                ),
                presentationMode: viewModel.presentationMode
            )
        }
        .contentShape(Rectangle())
        .onHover { viewModel.setPointerInside($0) }
        .accessibilityElement(children: .contain)
        .animation(contentAnimation, value: viewModel.state.visualPhase)
    }

    @ViewBuilder
    private var stateContent: some View {
        Group {
            switch viewModel.state {
            case .idle:
                idleContent
            case .dragHover:
                dragHoverContent
            case .inspecting:
                inspectingContent
            case let .droppedSummary(files):
                summaryContent(files)
            case let .actionSelection(files):
                imageActionContent(files)
            case .preparing:
                progressContent(
                    JobSnapshot(
                        actionLabel: "Preparing…",
                        progress: 0,
                        isEstimated: true,
                        currentFile: 0,
                        totalFiles: 0,
                        inputBytes: nil,
                        estimatedOutputBytes: nil
                    )
                )
            case let .converting(snapshot):
                progressContent(snapshot)
            case let .success(summary):
                successContent(summary)
            case let .failure(error):
                failureContent(error)
            }
        }
    }

    private var idleContent: some View {
        Group {
            if isPhysicalNotchIdle {
                HStack {
                    Image(systemName: "doc.fill")
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.down")
                }
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.72))
            } else {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.down.doc.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.76))
                    Text("File Island")
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                    Spacer(minLength: 0)
                }
            }
        }
    }

    @ViewBuilder
    private var islandBackground: some View {
        if viewModel.presentationMode == .physicalNotch {
            TopAttachedIslandShape()
                .fill(.black.opacity(viewModel.islandOpacity))
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(viewModel.islandOpacity)
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(
                            Color(red: 0.035, green: 0.04, blue: 0.05)
                                .opacity(0.72 * viewModel.islandOpacity)
                        )
                }
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.14), lineWidth: 1)
                }
        }
    }

    private var isPhysicalNotchIdle: Bool {
        viewModel.presentationMode == .physicalNotch && viewModel.state == .idle
    }

    private var contentTransition: AnyTransition {
        if reduceMotion { return .opacity }
        return .opacity.combined(with: .scale(scale: 0.98, anchor: .top))
    }

    private var contentAnimation: Animation {
        .timingCurve(
            0.23,
            1,
            0.32,
            1,
            duration: IslandMotionPolicy.contentDuration(reduceMotion: reduceMotion)
        )
    }

    private var notchWingContent: some View {
        let metrics = NotchWingLayout.metrics(
            islandWidth: viewModel.islandWidth,
            notchWidth: viewModel.notchOcclusionWidth,
            horizontalPadding: 14
        )
        return HStack(spacing: 0) {
            leadingWing
                .frame(width: metrics.leadingWidth, alignment: .leading)
            Color.clear.frame(width: metrics.occludedWidth)
            trailingWing
                .frame(width: metrics.trailingWidth, alignment: .trailing)
        }
        .padding(.horizontal, 14)
        .font(.system(size: 10, weight: .semibold, design: .rounded))
        .foregroundStyle(.white.opacity(0.78))
    }

    @ViewBuilder
    private var leadingWing: some View {
        switch viewModel.state {
        case .idle:
            Image(systemName: "doc.fill")
        case let .actionSelection(files):
            Text(wingSourceLabel(files)).lineLimit(1)
        case let .converting(snapshot):
            Text(snapshot.totalFiles > 1 ? "\(snapshot.currentFile)/\(snapshot.totalFiles)" : conversionPairLabel)
                .monospacedDigit()
        case .preparing:
            Text(conversionPairLabel)
        default:
            Text("File Island").lineLimit(1)
        }
    }

    @ViewBuilder
    private var trailingWing: some View {
        switch viewModel.state {
        case .idle:
            Image(systemName: "arrow.down")
        case let .converting(snapshot):
            Text("\(Int(snapshot.progress.clamped(to: 0...1) * 100))%")
                .monospacedDigit()
        case .preparing:
            ProgressView().controlSize(.mini)
        case .actionSelection:
            Text(wingTargetLabel).lineLimit(1)
        default:
            Image(systemName: "arrow.down.circle")
        }
    }

    private var dragHoverContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.accentColor)
                .shadow(color: Color.accentColor.opacity(0.55), radius: 8)
                .scaleEffect(reduceMotion ? 1 : 1.03)
            Text("Drop to process")
                .font(.system(size: 17, weight: .semibold, design: .rounded))
            Text("The original file stays untouched")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.58))
        }
    }

    private var inspectingContent: some View {
        HStack(spacing: 12) {
            ProgressView()
                .controlSize(.small)
            VStack(alignment: .leading, spacing: 3) {
                Text("Reading file details…")
                    .font(.headline)
                Text("Name, type, and size only")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.58))
            }
            Spacer()
        }
    }

    private func summaryContent(_ files: [InputFile]) -> some View {
        HStack(spacing: 12) {
            Image(systemName: files.count == 1 ? "doc.fill" : "doc.on.doc.fill")
                .font(.system(size: 27, weight: .semibold))
                .foregroundStyle(Color.accentColor)

            VStack(alignment: .leading, spacing: 5) {
                Text(summaryTitle(for: files))
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(summaryDetails(for: files))
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.64))
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            Button {
                viewModel.reset()
            } label: {
                Image(systemName: "xmark")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.66))
            .accessibilityLabel("Clear")

            Button("Continue") { viewModel.continueToActions() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
    }

    private func imageActionContent(_ files: [InputFile]) -> some View {
        HStack(spacing: 14) {
            sourcePane(viewModel.isBatchWorkflow ? viewModel.activeFiles : files)
                .frame(width: 176)
            Divider().overlay(.white.opacity(0.12))
            Group {
                switch viewModel.conversionCapability {
                case .image:
                    imageOptionsPane
                case .video:
                    videoOptionsPane
                case let .unsupported(kind):
                    unsupportedOptionsPane(kind)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func sourcePane(_ files: [InputFile]) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Group {
                if let preview = viewModel.previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                } else {
                    Image(systemName: files.first?.kind == .video ? "film" : "photo")
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.white.opacity(0.48))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 74, maxHeight: 74)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))

            Text(files.count == 1 ? files[0].displayName : "\(files.count) files")
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
            Text(summaryDetails(for: files))
                .font(.system(size: 10, weight: .medium, design: .monospaced))
                .foregroundStyle(.white.opacity(0.56))
                .lineLimit(1)
        }
    }

    private var imageOptionsPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Image options").font(.system(size: 13, weight: .semibold))
                Spacer()
                batchSectionPicker
                presetMenu
                Button("Back") { viewModel.returnToSummary() }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.62))
            }
            settingRow(title: "Format") {
                ForEach(viewModel.availableOutputFormats, id: \.rawValue) { format in
                    choiceButton(format == .jpeg ? "JPEG" : "PNG", selected: viewModel.imageIntent?.outputFormat == format) {
                        viewModel.selectOutputFormat(format)
                    }
                }
            }
            settingRow(title: "Longest edge") {
                choiceButton("Original", selected: viewModel.imageIntent?.maxPixelDimension == nil) {
                    viewModel.selectMaximumDimension(nil)
                }
                ForEach([2048, 1280], id: \.self) { dimension in
                    choiceButton("\(dimension)", selected: viewModel.imageIntent?.maxPixelDimension == dimension) {
                        viewModel.selectMaximumDimension(dimension)
                    }
                }
            }
            settingRow(title: "Target") {
                choiceButton("None", selected: viewModel.imageIntent?.targetBytes == nil) {
                    viewModel.selectTargetBytes(nil)
                }
                ForEach([5_000_000, 1_000_000, 500_000], id: \.self) { target in
                    choiceButton(target.targetSizeLabel, selected: viewModel.imageIntent?.targetBytes == Int64(target)) {
                        viewModel.selectTargetBytes(Int64(target))
                    }
                }
            }
            if viewModel.imageIntent?.outputFormat == .jpeg {
                settingRow(title: "Quality") {
                    if viewModel.imageIntent?.targetBytes != nil {
                        Label("Adaptive", systemImage: "wand.and.stars")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.72))
                    } else {
                        ForEach([QualityPreference.smallestFile, .balanced, .highestQuality], id: \.rawValue) { quality in
                            choiceButton(quality.shortLabel, selected: viewModel.imageIntent?.qualityPreference == quality) {
                                viewModel.selectQuality(quality)
                            }
                        }
                    }
                }
            }
            HStack {
                Toggle("Remove metadata", isOn: Binding(
                    get: { viewModel.imageIntent?.stripMetadata ?? true },
                    set: { viewModel.setStripMetadata($0) }
                ))
                .toggleStyle(.checkbox).font(.caption)
                Spacer()
                batchExecutionSummary
                Button(viewModel.isChoosingOutputFolder ? "Choosing…" : "Start") {
                    viewModel.startConversion()
                }
                    .buttonStyle(.borderedProminent).controlSize(.small)
                    .disabled(viewModel.isChoosingOutputFolder || viewModel.batchProcessCount == 0)
            }
        }
    }

    private var videoOptionsPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Video options").font(.system(size: 13, weight: .semibold))
                Spacer()
                batchSectionPicker
                presetMenu
                Button("Back") { viewModel.returnToSummary() }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.62))
            }
            settingRow(title: "Format") {
                choiceButton("MP4", selected: true) {}
                    .disabled(true)
            }
            settingRow(title: "Compatibility") {
                Label("High · H.264 + AAC", systemImage: "checkmark.shield")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.72))
            }
            settingRow(title: "Resolution") {
                ForEach([VideoResolution.source, .p1080, .p720], id: \.rawValue) { resolution in
                    choiceButton(
                        resolution.shortLabel,
                        selected: viewModel.videoIntent?.maxResolution == resolution
                    ) {
                        viewModel.selectVideoResolution(resolution)
                    }
                }
            }
            if viewModel.supportsVideoTargetSize {
                settingRow(title: "Target") {
                    choiceButton("None", selected: viewModel.videoIntent?.targetBytes == nil) {
                        viewModel.selectVideoTargetBytes(nil)
                    }
                    choiceButton(
                        "100M",
                        selected: !viewModel.isUsingCustomVideoTarget
                            && viewModel.videoIntent?.targetBytes == 100_000_000
                    ) {
                        viewModel.selectVideoTargetBytes(100_000_000)
                    }
                    choiceButton(
                        "50M",
                        selected: !viewModel.isUsingCustomVideoTarget
                            && viewModel.videoIntent?.targetBytes == 50_000_000
                    ) {
                        viewModel.selectVideoTargetBytes(50_000_000)
                    }
                    choiceButton("Custom", selected: viewModel.isUsingCustomVideoTarget) {
                        viewModel.selectCustomVideoTarget()
                    }
                }
            } else {
                settingRow(title: "Engine") {
                    Label("FFmpeg 8.1.2 fallback", systemImage: "shippingbox.fill")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.72))
                }
            }
            HStack {
                if viewModel.isUsingCustomVideoTarget {
                    Button {
                        viewModel.adjustCustomVideoTargetMegabytes(by: -5)
                    } label: {
                        Image(systemName: "minus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                    Text("\(viewModel.customVideoTargetMegabytes) MB / file")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.7))
                    Button {
                        viewModel.adjustCustomVideoTargetMegabytes(by: 5)
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.mini)
                } else {
                    Label(
                        viewModel.supportsVideoTargetSize && viewModel.batchHasFallbackVideo
                            ? "Size applies to native video only"
                            : viewModel.supportsVideoTargetSize
                            ? "Native AVFoundation"
                            : "Hardware H.264 · estimated size",
                        systemImage: "bolt.fill"
                    )
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.48))
                }
                Spacer()
                batchExecutionSummary
                Button(viewModel.isChoosingOutputFolder ? "Choosing…" : "Start") {
                    viewModel.startConversion()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.isChoosingOutputFolder || viewModel.batchProcessCount == 0)
            }
            Spacer(minLength: 0)
        }
    }

    private func unsupportedOptionsPane(_ kind: UnsupportedBatchKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(kind == .video ? "Video" : "This selection")
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                batchSectionPicker
                Button("Back") { viewModel.returnFromUnsupportedSection() }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.62))
            }
            Label("Not available in this milestone", systemImage: "clock.badge.exclamationmark")
                .foregroundStyle(.orange)
            Text(kind == .video
                 ? "Task 008.1 supports readable MOV, MP4, M4V, MKV, and WebM files. This video container is not available yet."
                 : "Choose a supported HEIC, HEIF, JPEG, PNG, WebP, or TIFF image batch to configure conversion.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            HStack {
                batchExecutionSummary
                Spacer()
                if viewModel.isBatchWorkflow {
                    Button(viewModel.isChoosingOutputFolder ? "Choosing…" : "Start") {
                        viewModel.startConversion()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(viewModel.isChoosingOutputFolder || viewModel.batchProcessCount == 0)
                }
            }
        }
    }

    @ViewBuilder
    private var batchSectionPicker: some View {
        if viewModel.isBatchWorkflow {
            Menu {
                batchSectionMenuButton(
                    "Images (\(viewModel.batchImageCount))",
                    section: .image,
                    enabled: viewModel.batchImageCount > 0
                )
                batchSectionMenuButton(
                    "Videos (\(viewModel.batchVideoCount))",
                    section: .video,
                    enabled: viewModel.batchVideoCount > 0
                )
                batchSectionMenuButton(
                    "Other (\(viewModel.batchUnsupportedCount))",
                    section: .unsupported,
                    enabled: viewModel.batchUnsupportedCount > 0
                )
            } label: {
                Label(currentBatchSectionLabel, systemImage: "square.grid.2x2")
                    .font(.caption)
                    .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
        }
    }

    private func batchSectionMenuButton(
        _ title: String,
        section: BatchSection,
        enabled: Bool
    ) -> some View {
        Button {
            viewModel.selectBatchSection(section)
        } label: {
            if viewModel.selectedBatchSection == section {
                Label(title, systemImage: "checkmark")
            } else {
                Text(title)
            }
        }
            .disabled(!enabled)
    }

    private var currentBatchSectionLabel: String {
        switch viewModel.selectedBatchSection {
        case .image: "Img \(viewModel.batchImageCount)"
        case .video: "Vid \(viewModel.batchVideoCount)"
        case .unsupported: "Other \(viewModel.batchUnsupportedCount)"
        }
    }

    @ViewBuilder
    private var batchExecutionSummary: some View {
        if viewModel.isBatchWorkflow {
            Text(
                "Do \(viewModel.batchProcessCount) · Skip \(viewModel.batchSkippedCount) · Block \(viewModel.batchFailClosedCount)"
            )
            .font(.system(size: 9, weight: .medium, design: .monospaced))
            .foregroundStyle(.white.opacity(0.52))
            .lineLimit(1)
        }
    }

    @ViewBuilder
    private var presetMenu: some View {
        if !viewModel.availablePresetRecommendations.isEmpty {
            Menu {
                ForEach(viewModel.availablePresetRecommendations, id: \.preset.id) { recommendation in
                    Button {
                        viewModel.applyPreset(id: recommendation.preset.id)
                    } label: {
                        if viewModel.selectedPresetID == recommendation.preset.id {
                            Label(recommendation.preset.displayName, systemImage: "checkmark")
                        } else {
                            Text(recommendation.preset.displayName)
                        }
                    }
                    .help(recommendation.preset.summary)
                }
            } label: {
                Label(
                    viewModel.selectedPresetDisplayName ?? "Presets",
                    systemImage: "slider.horizontal.3"
                )
                .font(.caption)
                .lineLimit(1)
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            .accessibilityLabel("Conversion presets")
        }
    }

    private func settingRow<Content: View>(
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .frame(width: 82, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func choiceButton(
        _ title: String,
        selected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(title, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(selected ? Color.accentColor : .white.opacity(0.22))
    }

    private func progressContent(_ snapshot: JobSnapshot) -> some View {
        HStack(spacing: 10) {
            Text(snapshot.actionLabel)
                .font(.system(size: 12, weight: .semibold, design: .rounded))
                .lineLimit(1)
            ProgressView(value: snapshot.progress.clamped(to: 0...1))
                .progressViewStyle(.linear)
                .frame(maxWidth: .infinity)
            Text("\(Int(snapshot.progress.clamped(to: 0...1) * 100))%")
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
            Button("Cancel") { viewModel.cancelConversion() }
                .buttonStyle(.plain)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
        }
    }

    private func successContent(_ summary: ResultSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text("\(formatBytes(summary.inputBytes)) → \(formatBytes(summary.outputBytes))")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
            if summary.inputBytes > 0, summary.outputBytes < summary.inputBytes {
                Text("Saved \(Int((1 - Double(summary.outputBytes) / Double(summary.inputBytes)) * 100))%")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.62))
            }
            HStack {
                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting(summary.outputURLs)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                Button("Clear") { viewModel.reset() }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func failureContent(_ error: UserFacingError) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(error.title, systemImage: "exclamationmark.triangle.fill")
                .font(.headline)
                .foregroundStyle(.orange)
            Text(error.message)
                .font(.caption)
                .foregroundStyle(.white.opacity(0.64))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryTitle(for files: [InputFile]) -> String {
        guard files.count == 1, let file = files.first else {
            return "\(files.count) files"
        }
        return file.displayName
    }

    private func summaryDetails(for files: [InputFile]) -> String {
        guard files.count == 1, let file = files.first else {
            return formatBytes(files.reduce(0) { $0 + $1.fileSize })
        }
        return "\(file.displayType) · \(formatBytes(file.fileSize))"
    }

    private func wingSourceLabel(_ files: [InputFile]) -> String {
        guard let first = files.first else { return "File" }
        return files.count == 1 ? first.displayType : "\(files.count) files"
    }

    private var wingTargetLabel: String {
        switch viewModel.conversionCapability {
        case .image:
            guard let format = viewModel.imageIntent?.outputFormat else { return "Preview" }
            return format == .jpeg ? "→ JPEG" : "→ PNG"
        case .video:
            if let targetBytes = viewModel.videoIntent?.targetBytes {
                return "≤ \(formatBytes(targetBytes))"
            }
            return "→ MP4"
        case .unsupported:
            return "Preview"
        }
    }

    private var conversionPairLabel: String {
        let source = viewModel.activeFiles.first?.displayType ?? "File"
        return "\(source) \(wingTargetLabel)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private extension QualityPreference {
    var shortLabel: String {
        switch self {
        case .smallestFile: "Small"
        case .balanced: "Balanced"
        case .highestQuality: "High"
        }
    }
}

private extension VideoResolution {
    var shortLabel: String {
        switch self {
        case .source: "Source"
        case .p1080: "1080p"
        case .p720: "720p"
        }
    }
}

private extension Int {
    var targetSizeLabel: String {
        switch self {
        case 5_000_000: "5 MB"
        case 1_000_000: "1 MB"
        case 500_000: "500 KB"
        default: "\(self) B"
        }
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
