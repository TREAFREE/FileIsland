import AppKit
import SwiftUI

struct IslandView: View {
    @Bindable var viewModel: IslandViewModel

    var body: some View {
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
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 14)
        .padding(.top, contentTopPadding)
        .padding(.bottom, isPhysicalNotchIdle ? 4 : 10)
        .foregroundStyle(.white)
        .background {
            islandBackground
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
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
                .fill(.black)
        } else {
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(Color(red: 0.08, green: 0.085, blue: 0.095))
                .overlay {
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(.white.opacity(0.16), lineWidth: 1)
                }
        }
    }

    private var isPhysicalNotchIdle: Bool {
        viewModel.presentationMode == .physicalNotch && viewModel.state == .idle
    }

    private var contentTopPadding: CGFloat {
        if isPhysicalNotchIdle { return 4 }
        guard viewModel.presentationMode == .physicalNotch else { return 10 }
        return 10 + viewModel.notchOcclusionHeight
    }

    private var dragHoverContent: some View {
        VStack(spacing: 8) {
            Image(systemName: "arrow.down.circle.fill")
                .font(.system(size: 30, weight: .semibold))
                .foregroundStyle(Color.accentColor)
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

            if viewModel.canConfigureImageConversion(for: files) {
                Button("Continue") {
                    viewModel.continueToImageActions()
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
    }

    private func imageActionContent(_ files: [InputFile]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(files.count == 1 ? files[0].displayName : "\(files.count) images")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .lineLimit(1)
                    Text("Choose conversion settings")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.58))
                }
                Spacer()
                Button("Back") { viewModel.returnToSummary() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.white.opacity(0.66))
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
                    choiceButton("\(dimension) px", selected: viewModel.imageIntent?.maxPixelDimension == dimension) {
                        viewModel.selectMaximumDimension(dimension)
                    }
                }
            }

            if viewModel.imageIntent?.outputFormat == .jpeg {
                settingRow(title: "JPEG quality") {
                    choiceButton("Small", selected: viewModel.imageIntent?.qualityPreference == .smallestFile) {
                        viewModel.selectQuality(.smallestFile)
                    }
                    choiceButton("Balanced", selected: viewModel.imageIntent?.qualityPreference == .balanced) {
                        viewModel.selectQuality(.balanced)
                    }
                    choiceButton("High", selected: viewModel.imageIntent?.qualityPreference == .highestQuality) {
                        viewModel.selectQuality(.highestQuality)
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
                .toggleStyle(.checkbox)
                .font(.caption)
                Spacer()
                Button("Start") { viewModel.startConversion() }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
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
        VStack(alignment: .leading, spacing: 7) {
            HStack {
                Text(snapshot.actionLabel)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                Spacer()
                Text("\(Int(snapshot.progress.clamped(to: 0...1) * 100))%")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
            }
            ProgressView(value: snapshot.progress.clamped(to: 0...1))
                .progressViewStyle(.linear)
            if let inputBytes = snapshot.inputBytes,
               let outputBytes = snapshot.estimatedOutputBytes {
                Text("\(formatBytes(inputBytes)) → ~\(formatBytes(outputBytes))")
                    .font(.system(size: 12, weight: .medium, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.66))
            }
            HStack {
                if snapshot.totalFiles > 0 {
                    Text("\(snapshot.currentFile) of \(snapshot.totalFiles)")
                        .font(.caption2.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.54))
                }
                Spacer()
                Button("Cancel") { viewModel.cancelConversion() }
                    .buttonStyle(.plain)
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }
    }

    private func successContent(_ summary: ResultSummary) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Done", systemImage: "checkmark.circle.fill")
                .font(.headline)
                .foregroundStyle(.green)
            Text("\(formatBytes(summary.inputBytes)) → \(formatBytes(summary.outputBytes))")
                .font(.system(size: 13, weight: .medium, design: .monospaced))
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

    private func formatBytes(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }
}

private extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        min(max(self, range.lowerBound), range.upperBound)
    }
}
