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
        .frame(minWidth: 600, minHeight: 410)
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
                        Button(localization.string(
                            viewModel.isChoosingOutputFolder ? "Choosing…" : "Choose…"
                        )) {
                            viewModel.chooseOutputFolder()
                        }
                        .disabled(viewModel.isChoosingOutputFolder)
                    }
                }
                Toggle(
                    "Reveal converted files in Finder",
                    isOn: Bindable(viewModel.preferences).revealOutputOnCompletion
                )
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

    private var conversion: some View {
        Form {
            Section("Image defaults") {
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
            Text("Built-in presets and manual controls share the same validated conversion plans. Video resolution and an optional per-file size limit are chosen for each job in the Island.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .formStyle(.grouped)
    }

    private var appearance: some View {
        Form {
            Section("Island") {
                Slider(value: Bindable(viewModel.preferences).islandOpacity, in: 0.65...1) {
                    Text("Opacity")
                }
                Text("Background styles and wallpapers can be added here without changing conversion settings.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        VStack(alignment: .leading, spacing: 14) {
            Image(systemName: "arrow.down.doc.fill")
                .font(.system(size: 42))
                .foregroundStyle(Color.accentColor)
            Text("File Island").font(.title2.bold())
            Text("A private, local-first file conversion utility for macOS.")
                .foregroundStyle(.secondary)
            Text(localization.string("Version %@", appVersion))
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
            ?? localization.string("Development")
    }

    private func localizedValue(_ value: String) -> String {
        value == "Not selected" ? localization.string(value) : value
    }
}
