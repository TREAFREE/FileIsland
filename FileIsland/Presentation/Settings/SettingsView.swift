import AppKit
import SwiftUI

struct SettingsView: View {
    enum Pane: String, CaseIterable, Identifiable {
        case general
        case conversion
        case appearance
        case about

        var id: Self { self }

        var title: String {
            switch self {
            case .general: "General"
            case .conversion: "Conversion"
            case .appearance: "Appearance"
            case .about: "About"
            }
        }

        var symbol: String {
            switch self {
            case .general: "gearshape"
            case .conversion: "arrow.triangle.2.circlepath"
            case .appearance: "paintbrush"
            case .about: "info.circle"
            }
        }
    }

    @Bindable var viewModel: SettingsViewModel
    @Bindable var navigation: SettingsNavigationModel
    @Environment(LocalizationController.self) private var localization

    var body: some View {
        VStack(spacing: 0) {
            sectionPicker
                .padding(.vertical, 14)
            Divider()
            Group {
                switch navigation.selection {
                case .general: general
                case .conversion: conversion
                case .appearance: appearance
                case .about: about
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .padding(24)
        }
        .frame(minWidth: 600, minHeight: 500)
        .environment(\.locale, localization.locale)
    }

    private var sectionPicker: some View {
        HStack(spacing: 10) {
            ForEach(Pane.allCases) { section in
                Button {
                    navigation.select(section)
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: section.symbol)
                            .font(.system(size: 21, weight: .medium))
                        Text(localization.string(section.title))
                            .font(.caption)
                    }
                    .frame(width: 82, height: 52)
                    .foregroundStyle(
                        navigation.selection == section ? Color.accentColor : .secondary
                    )
                    .background(
                        RoundedRectangle(cornerRadius: 10)
                            .fill(
                                navigation.selection == section
                                    ? Color.accentColor.opacity(0.12)
                                    : .clear
                            )
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var general: some View {
        VStack(alignment: .leading, spacing: 12) {
            paneHeader(.general)
            Form {
                Section("Language") {
                    Picker(
                        "App language",
                        selection: Binding(
                            get: { localization.language },
                            set: { localization.language = $0 }
                        )
                    ) {
                        Text("Follow System").tag(AppLanguage.system)
                        Text("English").tag(AppLanguage.english)
                        Text("Simplified Chinese").tag(AppLanguage.simplifiedChinese)
                    }
                    Text("Language changes apply immediately and do not restart active conversions.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section("Output") {
                    LabeledContent("Output folder") {
                        HStack(spacing: 10) {
                            Text(localizedValue(viewModel.outputFolderLabel))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .frame(maxWidth: 300, alignment: .trailing)
                            Button(
                                localization.string(
                                    viewModel.isChoosingOutputFolder ? "Choosing…" : "Choose…"
                                )
                            ) {
                                viewModel.chooseOutputFolder()
                            }
                            .disabled(viewModel.isChoosingOutputFolder)
                        }
                    }
                    Toggle(
                        "Reveal converted files in Finder",
                        isOn: Bindable(viewModel.preferences).revealOutputOnCompletion
                    )
                    Toggle(
                        "Copy single converted files to Clipboard",
                        isOn: Bindable(viewModel.preferences).copySingleOutputToClipboard
                    )
                    Text(
                        "When one input creates one file, File Island copies its file reference for pasting into Finder or compatible apps."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Section("Startup") {
                    Toggle(
                        "Launch File Island at login",
                        isOn: Binding(
                            get: { viewModel.launchAtLogin },
                            set: { viewModel.setLaunchAtLogin($0) }
                        )
                    )
                }
                if let message = viewModel.errorMessage {
                    Text(localization.string(message)).foregroundStyle(.red).font(.caption)
                }
            }
            .formStyle(.grouped)
        }
    }

    private var conversion: some View {
        VStack(alignment: .leading, spacing: 12) {
            paneHeader(.conversion)
            Form {
                Section("Default image behavior") {
                    Picker("JPEG quality", selection: Bindable(viewModel.preferences).defaultQuality) {
                        Text("Small").tag(QualityPreference.smallestFile)
                        Text("Balanced").tag(QualityPreference.balanced)
                        Text("High").tag(QualityPreference.highestQuality)
                    }
                    Toggle(
                        "Remove metadata by default",
                        isOn: Bindable(viewModel.preferences).stripMetadataByDefault
                    )
                }
                Section("Per-job controls") {
                    LabeledContent("Images") {
                        Text("JPEG · PNG")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Video") {
                        Text("MP4 · resolution · target size · splitting")
                            .foregroundStyle(.secondary)
                    }
                    LabeledContent("Audio") {
                        Text("M4A · WAV · FLAC · AIFF")
                            .foregroundStyle(.secondary)
                    }
                    Text(
                        "File Island shows only the controls that apply to the files in each job. Built-in presets and manual choices use the same validated conversion plans."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }
            .formStyle(.grouped)
        }
    }

    private var appearance: some View {
        VStack(alignment: .leading, spacing: 12) {
            paneHeader(.appearance)
            Form {
                Section("Island") {
                    HStack(spacing: 14) {
                        Spacer(minLength: 0)
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.down.doc.fill")
                                .foregroundStyle(.white.opacity(0.82))
                            Text("File Island")
                                .font(.system(size: 13, weight: .semibold, design: .rounded))
                                .foregroundStyle(.white)
                            Spacer(minLength: 22)
                        }
                        .padding(.horizontal, 14)
                        .frame(width: 240, height: 44)
                        .background {
                            Capsule()
                                .fill(
                                    Color(red: 0.035, green: 0.04, blue: 0.05)
                                        .opacity(viewModel.preferences.islandOpacity)
                                )
                        }
                        .overlay {
                            Capsule().stroke(.white.opacity(0.12), lineWidth: 1)
                        }
                        .accessibilityLabel("Island appearance preview")
                        Spacer(minLength: 0)
                    }

                    LabeledContent("Opacity") {
                        Text("\(Int((viewModel.preferences.islandOpacity * 100).rounded()))%")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Slider(value: Bindable(viewModel.preferences).islandOpacity, in: 0.65...1)
                        .accessibilityLabel("Opacity")
                    HStack(alignment: .firstTextBaseline) {
                        Text("Adjusts the Island surface only. Text and progress remain readable.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Button("Reset") {
                            viewModel.resetIslandOpacity()
                        }
                        .disabled(viewModel.preferences.islandOpacity == 1)
                    }
                }
            }
            .formStyle(.grouped)
        }
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 14) {
            paneHeader(.about)

            HStack(spacing: 16) {
                Image(nsImage: NSApplication.shared.applicationIconImage)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: 78, height: 78)
                    .shadow(color: .black.opacity(0.16), radius: 7, y: 3)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 5) {
                    Text("File Island")
                        .font(.title2.bold())
                    Text("A private, local-first file conversion utility for macOS.")
                        .foregroundStyle(.secondary)
                    Text(localization.string("Version %@ (%@)", appVersion, appBuild))
                        .font(.caption)
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                Spacer()
            }
            .padding(16)
            .background(.quaternary.opacity(0.55), in: RoundedRectangle(cornerRadius: 14))

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 10
            ) {
                destinationLink("Website", symbol: "globe", destination: .website)
                destinationLink("Latest Release", symbol: "arrow.down.circle", destination: .releases)
                destinationLink("Report Issue", symbol: "exclamationmark.bubble", destination: .issues)
                destinationLink("Privacy", symbol: "hand.raised", destination: .privacy)
                destinationLink(
                    "Third-party Notices",
                    symbol: "shippingbox",
                    destination: .thirdPartyNotices
                )
            }

            Text("Conversions run locally. File Island does not upload your files or collect usage telemetry.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 2)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    private func paneHeader(_ pane: Pane) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 38, height: 38)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(localization.string(pane.title))
                    .font(.title2.bold())
                Text(localization.string(pane.subtitle))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: pane.symbol)
                .font(.system(size: 20, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .frame(width: 28)
        }
        .accessibilityElement(children: .combine)
    }

    private func destinationLink(
        _ title: LocalizedStringKey,
        symbol: String,
        destination: SettingsDestination
    ) -> some View {
        Link(destination: destination.url) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 20)
                Text(title)
                    .foregroundStyle(.primary)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(.horizontal, 12)
            .frame(height: 42)
            .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? localization.string("Development")
    }

    private var appBuild: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
            ?? "—"
    }

    private func localizedValue(_ value: String) -> String {
        value == "Not selected" ? localization.string(value) : value
    }
}

private extension SettingsView.Pane {
    var subtitle: String {
        switch self {
        case .general:
            "Language, output, and startup"
        case .conversion:
            "Defaults and supported job controls"
        case .appearance:
            "Tune the Island surface"
        case .about:
            "Version, support, and privacy"
        }
    }
}
