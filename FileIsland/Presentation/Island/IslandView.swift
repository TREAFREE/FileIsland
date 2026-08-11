import AppKit
import SwiftUI

struct IslandView: View {
    @Bindable var viewModel: IslandViewModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorSchemeContrast) private var colorSchemeContrast
    @Environment(LocalizationController.self) private var localization

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
        .environment(\.locale, localization.locale)
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
            case .droppedSummary(let files):
                summaryContent(files)
            case .actionSelection(let files):
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
            case .converting(let snapshot):
                progressContent(snapshot)
            case .success(let summary):
                successContent(summary)
            case .failure(let error):
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
        let curve = IslandMotionPolicy.easeOutControlPoints
        return .timingCurve(
            curve.x1,
            curve.y1,
            curve.x2,
            curve.y2,
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
        case .actionSelection(let files):
            Text(wingSourceLabel(files)).lineLimit(1)
        case .converting(let snapshot):
            Text(progressWingLabel(snapshot))
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
        case .converting(let snapshot):
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
                .keyboardShortcut(.defaultAction)
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
                case .audio:
                    audioOptionsPane
                case .unsupported(let kind):
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
                    Image(systemName: sourcePlaceholderSymbol(for: files.first?.kind))
                        .font(.system(size: 32, weight: .light))
                        .foregroundStyle(.white.opacity(0.48))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 74, maxHeight: 74)
            .background(.white.opacity(0.07), in: RoundedRectangle(cornerRadius: 9))

            Text(
                files.count == 1
                    ? files[0].displayName
                    : localization.string("%d files", files.count)
            )
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
                    .keyboardShortcut(.cancelAction)
            }
            settingRow(title: "Format") {
                ForEach(viewModel.availableOutputFormats, id: \.rawValue) { format in
                    choiceButton(
                        format == .jpeg ? "JPEG" : "PNG",
                        selected: viewModel.imageIntent?.outputFormat == format
                    ) {
                        viewModel.selectOutputFormat(format)
                    }
                }
            }
            settingRow(title: "Longest edge") {
                choiceButton("Original", selected: viewModel.imageIntent?.maxPixelDimension == nil) {
                    viewModel.selectMaximumDimension(nil)
                }
                ForEach([2048, 1280], id: \.self) { dimension in
                    choiceButton(
                        "\(dimension)", selected: viewModel.imageIntent?.maxPixelDimension == dimension
                    ) {
                        viewModel.selectMaximumDimension(dimension)
                    }
                }
            }
            settingRow(title: "Target") {
                choiceButton("None", selected: viewModel.imageIntent?.targetBytes == nil) {
                    viewModel.selectTargetBytes(nil)
                }
                ForEach([5_000_000, 1_000_000, 500_000], id: \.self) { target in
                    choiceButton(
                        target.targetSizeLabel, selected: viewModel.imageIntent?.targetBytes == Int64(target)
                    ) {
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
                        ForEach([QualityPreference.smallestFile, .balanced, .highestQuality], id: \.rawValue) {
                            quality in
                            choiceButton(
                                quality.shortLabel, selected: viewModel.imageIntent?.qualityPreference == quality
                            ) {
                                viewModel.selectQuality(quality)
                            }
                        }
                    }
                }
            }
            HStack {
                Toggle(
                    "Remove metadata",
                    isOn: Binding(
                        get: { viewModel.imageIntent?.stripMetadata ?? true },
                        set: { viewModel.setStripMetadata($0) }
                    )
                )
                .toggleStyle(.checkbox).font(.caption)
                Spacer()
                batchExecutionSummary
                Button(localization.string(viewModel.isChoosingOutputFolder ? "Choosing…" : "Start")) {
                    viewModel.startConversion()
                }
                .buttonStyle(.borderedProminent).controlSize(.small)
                .disabled(viewModel.isChoosingOutputFolder || viewModel.batchProcessCount == 0)
                .keyboardShortcut(.defaultAction)
            }
        }
    }

    private var videoOptionsPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 5) {
                choiceButton(
                    "Convert",
                    selected: viewModel.videoOperation == .convert
                ) {
                    viewModel.selectVideoOperation(.convert)
                }
                choiceButton(
                    "Split for Sharing",
                    selected: viewModel.videoOperation == .splitForSharing
                ) {
                    viewModel.selectVideoOperation(.splitForSharing)
                }
                Spacer(minLength: 2)
                batchSectionPicker
                if !viewModel.isVideoSplitSelected {
                    presetMenu
                }
                Button("Back") { viewModel.returnToSummary() }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.62))
                    .keyboardShortcut(.cancelAction)
            }
            if viewModel.isVideoSplitSelected {
                videoSplitOptionsContent
            } else {
                videoConversionOptionsContent
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private var videoConversionOptionsContent: some View {
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
                Text(localization.string("%d MB / file", viewModel.customVideoTargetMegabytes))
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
                    localization.string(
                        viewModel.supportsVideoTargetSize && viewModel.batchHasFallbackVideo
                            ? "Size applies to native video only"
                            : viewModel.supportsVideoTargetSize
                                ? "Native AVFoundation"
                                : "Hardware H.264 · estimated size"),
                    systemImage: "bolt.fill"
                )
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.48))
            }
            Spacer()
            batchExecutionSummary
            Button(localization.string(viewModel.isChoosingOutputFolder ? "Choosing…" : "Start")) {
                viewModel.startConversion()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(viewModel.isChoosingOutputFolder || viewModel.batchProcessCount == 0)
            .keyboardShortcut(.defaultAction)
        }
    }

    @ViewBuilder
    private var videoSplitOptionsContent: some View {
        settingRow(title: "Mode") {
            Label("Custom · Fast · keep original quality", systemImage: "equal.circle.fill")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.76))
                .lineLimit(1)
        }
        HStack(spacing: 7) {
            splitLimitControl(
                title: "Size",
                text: Binding(
                    get: { viewModel.videoSplitMaximumMegabytesText },
                    set: { viewModel.updateVideoSplitMaximumMegabytes($0) }
                ),
                sliderPosition: Binding(
                    get: { viewModel.videoSplitSizeSliderPosition },
                    set: { viewModel.updateVideoSplitSizeSliderPosition($0) }
                ),
                selectedUnit: viewModel.videoSplitSizeUnit,
                selectUnit: viewModel.selectVideoSplitSizeUnit,
                accessibilityLabel: "Maximum segment size",
                unitAccessibilityLabel: "Size unit"
            )
            splitLimitControl(
                title: "Duration",
                text: Binding(
                    get: { viewModel.videoSplitMaximumDurationSecondsText },
                    set: { viewModel.updateVideoSplitMaximumDurationSeconds($0) }
                ),
                sliderPosition: Binding(
                    get: { viewModel.videoSplitDurationSliderPosition },
                    set: { viewModel.updateVideoSplitDurationSliderPosition($0) }
                ),
                selectedUnit: viewModel.videoSplitDurationUnit,
                selectUnit: viewModel.selectVideoSplitDurationUnit,
                accessibilityLabel: "Maximum segment duration",
                unitAccessibilityLabel: "Duration unit"
            )
        }
        settingRow(title: "Plan") {
            videoSplitPlanStatus
        }
        HStack(spacing: 7) {
            Text("1 MB equals 1,000,000 bytes.")
                .font(.system(size: 9.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.48))
                .lineLimit(1)
                .minimumScaleFactor(0.78)
            Spacer(minLength: 2)
            if viewModel.videoSplitInputCount > 1 {
                Text(localization.string("%d videos", viewModel.videoSplitInputCount))
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.white.opacity(0.58))
            }
            Button(localization.string(viewModel.isChoosingOutputFolder ? "Choosing…" : "Start")) {
                viewModel.startVideoSplit()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .disabled(!viewModel.canStartVideoSplit)
            .keyboardShortcut(.defaultAction)
            .accessibilityHint("Starts local fast splitting without re-encoding")
        }
    }

    @ViewBuilder
    private var videoSplitPlanStatus: some View {
        switch viewModel.videoSplitPlanningState {
        case .inactive:
            Text("Enter a size or duration limit")
                .foregroundStyle(.white.opacity(0.58))
        case .planning:
            HStack(spacing: 5) {
                ProgressView().controlSize(.mini)
                Text("Checking keyframes…")
            }
            .foregroundStyle(.white.opacity(0.68))
        case .ready:
            if let preview = viewModel.videoSplitPlanPreview {
                Text(splitPreviewSummary(preview))
                    .foregroundStyle(.white.opacity(0.78))
            }
        case .blocked(let issue):
            Label(videoSplitIssueMessage(issue), systemImage: "exclamationmark.circle")
                .foregroundStyle(.orange)
        }
    }

    private func splitLimitControl<Unit: VideoSplitLimitUnit>(
        title: String,
        text: Binding<String>,
        sliderPosition: Binding<Double>,
        selectedUnit: Unit,
        selectUnit: @escaping (Unit) -> Void,
        accessibilityLabel: String,
        unitAccessibilityLabel: String
    ) -> some View {
        let appearance = VideoSplitLimitFieldAppearance.resolve(
            increaseContrast: colorSchemeContrast == .increased
        )
        return VStack(alignment: .leading, spacing: 3) {
            Text(localization.string(title))
                .font(.system(size: 9.5, weight: .semibold))
                .foregroundStyle(.white.opacity(0.58))
            HStack(spacing: 5) {
                Slider(value: sliderPosition, in: 0...1)
                    .controlSize(.mini)
                    .frame(minWidth: 58)
                    .accessibilityLabel(localization.string(accessibilityLabel))
                    .accessibilityValue(
                        text.wrappedValue.isEmpty
                            ? localization.string("Not set")
                            : localization.string(
                                "%@ %@",
                                text.wrappedValue,
                                selectedUnit.shortLabel
                            )
                    )
                TextField("—", text: text)
                    .textFieldStyle(.plain)
                    .font(.caption.monospacedDigit())
                    .multilineTextAlignment(.trailing)
                    .frame(width: 43)
                    .padding(.horizontal, 4)
                    .frame(height: 22)
                    .background(.white.opacity(0.07), in: Capsule())
                    .overlay {
                        Capsule()
                            .strokeBorder(
                                .white.opacity(appearance.borderOpacity),
                                lineWidth: appearance.borderWidth
                            )
                    }
                    .accessibilityLabel(localization.string(accessibilityLabel))
                    .onSubmit {
                        if viewModel.canStartVideoSplit {
                            viewModel.startVideoSplit()
                        }
                    }
                Menu {
                    ForEach(Array(Unit.allCases), id: \.self) { unit in
                        Button {
                            selectUnit(unit)
                        } label: {
                            if unit == selectedUnit {
                                Label(
                                    localization.string(unit.shortLabel),
                                    systemImage: "checkmark"
                                )
                            } else {
                                Text(localization.string(unit.shortLabel))
                            }
                        }
                    }
                } label: {
                    HStack(spacing: 2) {
                        Text(localization.string(selectedUnit.shortLabel))
                            .font(.system(size: 9.5, weight: .semibold))
                        Image(systemName: "chevron.down")
                            .font(.system(size: 7, weight: .bold))
                    }
                    .foregroundStyle(.white.opacity(0.72))
                    .frame(minWidth: 31)
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .accessibilityLabel(localization.string(unitAccessibilityLabel))
            }
        }
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .frame(maxWidth: .infinity)
        .background(.white.opacity(0.045), in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    .white.opacity(colorSchemeContrast == .increased ? 0.3 : 0.1),
                    lineWidth: colorSchemeContrast == .increased ? 1.5 : 1
                )
        }
    }

    private func splitPreviewSummary(_ preview: VideoSplitBatchPlanPreview) -> String {
        var parts = [preview.localizedSegmentSummary(using: localization)]
        if let bytes = preview.maxBytes {
            parts.append(localization.string("≤ %@ each", formatBytes(bytes)))
        }
        if let milliseconds = preview.maxDurationMilliseconds {
            let seconds = Double(milliseconds) / 1_000
            parts.append(
                localization.string(
                    "≤ %@ sec each", seconds.formatted(.number.precision(.fractionLength(0...2)))))
        }
        return parts.joined(separator: " · ")
    }

    private func videoSplitIssueMessage(_ issue: IslandVideoSplitIssue) -> String {
        switch issue {
        case .enterAtLeastOneLimit:
            localization.string("Enter a size or duration limit")
        case .invalidMaximumMegabytes:
            localization.string("Enter a positive decimal MB value")
        case .invalidMaximumDuration:
            localization.string("Enter a positive duration in seconds")
        case .runtimeUnavailable:
            localization.string("Split runtime unavailable")
        case .unsupportedSource:
            localization.string("Fast mode needs H.264 video with AAC audio in MP4 or MOV")
        case .sourceChanged:
            localization.string("The source changed · drop it again")
        case .keyframesTooFarApart:
            localization.string("Increase a limit to reach an earlier keyframe")
        case .planningFailed:
            localization.string("Couldn’t build a safe split plan")
        }
    }

    private var audioOptionsPane: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text("Audio options").font(.system(size: 13, weight: .semibold))
                Spacer()
                batchSectionPicker
                Button("Back") { viewModel.returnToSummary() }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.62))
                    .keyboardShortcut(.cancelAction)
            }
            settingRow(title: "Format") {
                ForEach(MediaConversionMatrix.audioOutputFormats, id: \.rawValue) { format in
                    choiceButton(
                        format.rawValue.uppercased(),
                        selected: viewModel.audioIntent?.outputFormat == format
                    ) {
                        viewModel.selectAudioOutputFormat(format)
                    }
                }
            }
            settingRow(title: "Quality") {
                ForEach(AudioQuality.allCases, id: \.rawValue) { quality in
                    choiceButton(
                        audioQualityLabel(quality),
                        selected: viewModel.audioIntent?.quality == quality
                    ) {
                        viewModel.selectAudioQuality(quality)
                    }
                }
            }
            Text(
                "M4A uses AAC. WAV and AIFF use lossless PCM; FLAC is lossless. MP3 is supported as input, not output."
            )
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.55))
            .fixedSize(horizontal: false, vertical: true)
            HStack {
                Toggle(
                    "Remove metadata",
                    isOn: Binding(
                        get: { viewModel.audioIntent?.stripMetadata ?? true },
                        set: { viewModel.setAudioStripMetadata($0) }
                    )
                )
                .toggleStyle(.checkbox)
                .font(.caption)
                Spacer()
                batchExecutionSummary
                Button(localization.string(viewModel.isChoosingOutputFolder ? "Choosing…" : "Start")) {
                    viewModel.startConversion()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .disabled(viewModel.isChoosingOutputFolder || viewModel.batchProcessCount == 0)
                .keyboardShortcut(.defaultAction)
            }
            Spacer(minLength: 0)
        }
    }

    private func unsupportedOptionsPane(_ kind: UnsupportedBatchKind) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(localization.string(kind == .video ? "Video" : "This selection"))
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
                batchSectionPicker
                Button("Back") { viewModel.returnFromUnsupportedSection() }
                    .buttonStyle(.plain).foregroundStyle(.white.opacity(0.62))
                    .keyboardShortcut(.cancelAction)
            }
            Label("Unsupported format", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
            Text(localization.string(unsupportedFormatGuidance(kind)))
                .font(.caption)
                .foregroundStyle(.white.opacity(0.6))
                .fixedSize(horizontal: false, vertical: true)
            Spacer()
            HStack {
                batchExecutionSummary
                Spacer()
                if viewModel.isBatchWorkflow {
                    Button(localization.string(viewModel.isChoosingOutputFolder ? "Choosing…" : "Start")) {
                        viewModel.startConversion()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .disabled(viewModel.isChoosingOutputFolder || viewModel.batchProcessCount == 0)
                    .keyboardShortcut(.defaultAction)
                }
            }
        }
    }

    private func unsupportedFormatGuidance(_ kind: UnsupportedBatchKind) -> String {
        switch kind {
        case .video:
            "Supported video inputs: MOV, MP4, M4V, MKV, WebM, AVI, MPEG, TS, FLV, 3GP, and WMV."
        case .audio:
            "Supported audio inputs: MP3, WAV, AIFF, M4A, AAC, FLAC, OGG, Opus, and AC3."
        case .other, .mixed:
            "Choose a supported HEIC, HEIF, JPEG, PNG, WebP, TIFF, GIF, BMP, or AVIF image batch to configure conversion."
        }
    }

    @ViewBuilder
    private var batchSectionPicker: some View {
        if viewModel.isBatchWorkflow {
            Menu {
                batchSectionMenuButton(
                    localization.string("Images (%d)", viewModel.batchImageCount),
                    section: .image,
                    enabled: viewModel.batchImageCount > 0
                )
                batchSectionMenuButton(
                    localization.string("Videos (%d)", viewModel.batchVideoCount),
                    section: .video,
                    enabled: viewModel.batchVideoCount > 0
                )
                batchSectionMenuButton(
                    localization.string("Audio (%d)", viewModel.batchAudioCount),
                    section: .audio,
                    enabled: viewModel.batchAudioCount > 0
                )
                batchSectionMenuButton(
                    localization.string("Other (%d)", viewModel.batchUnsupportedCount),
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
                Label(localization.string(title), systemImage: "checkmark")
            } else {
                Text(localization.string(title))
            }
        }
        .disabled(!enabled)
    }

    private var currentBatchSectionLabel: String {
        switch viewModel.selectedBatchSection {
        case .image: localization.string("Img %d", viewModel.batchImageCount)
        case .video: localization.string("Vid %d", viewModel.batchVideoCount)
        case .audio: localization.string("Audio %d", viewModel.batchAudioCount)
        case .unsupported: localization.string("Other %d", viewModel.batchUnsupportedCount)
        }
    }

    @ViewBuilder
    private var batchExecutionSummary: some View {
        if viewModel.isBatchWorkflow {
            Text(
                localization.string(
                    "Do %d · Skip %d · Block %d",
                    viewModel.batchProcessCount,
                    viewModel.batchSkippedCount,
                    viewModel.batchFailClosedCount
                )
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
                            Label(
                                localization.string(recommendation.preset.displayName), systemImage: "checkmark")
                        } else {
                            Text(localization.string(recommendation.preset.displayName))
                        }
                    }
                    .help(localization.string(recommendation.preset.summary))
                }
            } label: {
                Label(
                    localization.string(viewModel.selectedPresetDisplayName ?? "Presets"),
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
            Text(localization.string(title))
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
        SelectionChoiceButton(
            title: localization.string(title),
            selected: selected,
            action: action
        )
    }

    private func progressContent(_ snapshot: JobSnapshot) -> some View {
        HStack(spacing: 10) {
            Text(progressActionLabel(snapshot))
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
                .keyboardShortcut(.cancelAction)
        }
    }

    private func successContent(_ summary: ResultSummary) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(Color.green.opacity(0.15))
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(Color.green)
            }
            .frame(width: 32, height: 32)

            VStack(alignment: .leading, spacing: 2) {
                Text(successTitle(outputCount: summary.outputURLs.count))
                    .font(.system(size: 14, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                Text(successDetail(summary))
                    .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.58))
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            Button {
                NSWorkspace.shared.activateFileViewerSelecting(summary.outputURLs)
            } label: {
                Label("Reveal", systemImage: "folder")
                    .font(.system(size: 11, weight: .semibold))
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .tint(.white.opacity(0.16))
            .keyboardShortcut(.defaultAction)

            Button {
                viewModel.reset()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 9, weight: .bold))
                    .frame(width: 22, height: 22)
                    .background(Circle().fill(.white.opacity(0.08)))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .foregroundStyle(.white.opacity(0.62))
            .help("Dismiss")
            .accessibilityLabel("Dismiss completed conversion")
            .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .contain)
    }

    private func successTitle(outputCount: Int) -> String {
        if let result = viewModel.lastVideoSplitResult {
            return localization.string("%d segments created", result.segmentCount)
        }
        return outputCount == 1
            ? localization.string("Conversion complete")
            : localization.string("%d files converted", outputCount)
    }

    private func successDetail(_ summary: ResultSummary) -> String {
        if let result = viewModel.lastVideoSplitResult {
            return localization.string("%@ total", formatBytes(result.totalBytes))
        }
        guard summary.inputBytes > 0, summary.outputBytes < summary.inputBytes else {
            return formatBytes(summary.outputBytes)
        }
        let percentage = Int(
            (1 - Double(summary.outputBytes) / Double(summary.inputBytes)) * 100
        )
        return localization.string(
            "%@ · %d%% smaller",
            formatBytes(summary.outputBytes),
            percentage
        )
    }

    private func failureContent(_ error: UserFacingError) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Label(localization.string(error.title), systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Text(localization.string(error.message))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.64))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Button("Dismiss") { viewModel.reset() }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .keyboardShortcut(.cancelAction)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryTitle(for files: [InputFile]) -> String {
        guard files.count == 1, let file = files.first else {
            return localization.string("%d files", files.count)
        }
        return file.displayName
    }

    private func summaryDetails(for files: [InputFile]) -> String {
        guard files.count == 1, let file = files.first else {
            return formatBytes(files.reduce(0) { $0 + $1.fileSize })
        }
        return "\(localizedDisplayType(file)) · \(formatBytes(file.fileSize))"
    }

    private func wingSourceLabel(_ files: [InputFile]) -> String {
        guard let first = files.first else { return localization.string("File") }
        return files.count == 1
            ? localizedDisplayType(first)
            : localization.string("%d files", files.count)
    }

    private var wingTargetLabel: String {
        switch viewModel.conversionCapability {
        case .image:
            guard let format = viewModel.imageIntent?.outputFormat else {
                return localization.string("Preview")
            }
            return format == .jpeg ? "→ JPEG" : "→ PNG"
        case .video:
            if viewModel.isVideoSplitSelected {
                return localization.string("→ Split")
            }
            if let targetBytes = viewModel.videoIntent?.targetBytes {
                return "≤ \(formatBytes(targetBytes))"
            }
            return "→ MP4"
        case .audio:
            guard let format = viewModel.audioIntent?.outputFormat else {
                return localization.string("Preview")
            }
            return "→ \(format.rawValue.uppercased())"
        case .unsupported:
            return localization.string("Preview")
        }
    }

    private var conversionPairLabel: String {
        let source =
            viewModel.activeFiles.first.map(localizedDisplayType)
            ?? localization.string("File")
        return "\(source) \(wingTargetLabel)"
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }

    private func localizedActionLabel(_ label: String) -> String {
        let prefix = "Converting "
        guard label.hasPrefix(prefix), label.hasSuffix("…") else {
            return localization.string(label)
        }
        let fileName = String(label.dropFirst(prefix.count).dropLast())
        return localization.string("Converting %@…", fileName)
    }

    private func progressActionLabel(_ snapshot: JobSnapshot) -> String {
        guard let progress = viewModel.videoSplitProgress else {
            return localizedActionLabel(snapshot.actionLabel)
        }
        guard let current = progress.currentSegment,
            let total = progress.totalSegments
        else {
            return localization.string("Splitting video…")
        }
        return localization.string("Splitting video… Segment %d of %d", current, total)
    }

    private func progressWingLabel(_ snapshot: JobSnapshot) -> String {
        if let progress = viewModel.videoSplitProgress,
            let current = progress.currentSegment,
            let total = progress.totalSegments
        {
            return localization.string("%d/%d segments", current, total)
        }
        return snapshot.totalFiles > 1
            ? "\(snapshot.currentFile)/\(snapshot.totalFiles)"
            : conversionPairLabel
    }

    private func localizedDisplayType(_ file: InputFile) -> String {
        file.displayType == "Unknown"
            ? localization.string("Unknown")
            : file.displayType
    }

    private func sourcePlaceholderSymbol(for kind: MediaKind?) -> String {
        switch kind {
        case .video: "film"
        case .audio: "waveform"
        default: "photo"
        }
    }

    private func audioQualityLabel(_ quality: AudioQuality) -> String {
        switch quality {
        case .compact: localization.string("Compact")
        case .balanced: localization.string("Balanced")
        case .high: localization.string("High")
        }
    }
}

extension QualityPreference {
    fileprivate var shortLabel: String {
        switch self {
        case .smallestFile: "Small"
        case .balanced: "Balanced"
        case .highestQuality: "High"
        }
    }
}

extension VideoResolution {
    fileprivate var shortLabel: String {
        switch self {
        case .source: "Source"
        case .p1080: "1080p"
        case .p720: "720p"
        }
    }
}

extension Int {
    fileprivate var targetSizeLabel: String {
        switch self {
        case 5_000_000: "5 MB"
        case 1_000_000: "1 MB"
        case 500_000: "500 KB"
        default: "\(self) B"
        }
    }
}

extension Comparable {
    fileprivate func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
