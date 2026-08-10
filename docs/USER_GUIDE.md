# File Island User Guide

[简体中文](USER_GUIDE.zh-CN.md)

## Install and open

1. Download the DMG and matching SHA-256 file from the official GitHub Release.
2. Verify it with `shasum -a 256 FileIsland-0.2.0-unsigned.dmg`.
3. Open the DMG and drag **File Island.app** onto the **Applications** shortcut.
4. Open File Island from Applications. This unsigned build may require **System Settings → Privacy & Security → Open Anyway** after the first launch attempt. Never disable Gatekeeper.

The DMG contains the universal app and its audited FFmpeg runtime. Homebrew and a separate FFmpeg installation are not required.

## Convert files

1. Drag one or more supported files, or an ordinary folder, to the Island at the top of the current display.
2. Review the media groups. Each group has format-appropriate controls.
3. Choose image, video, and audio outputs. MP3 is accepted as input but is intentionally not offered as output.
4. Select **Start**. On first use, authorize a persistent output folder; change it later in **Settings → General**.
5. Keep File Island running until the progress indicator finishes, then reveal the results in Finder.

Sources are never overwritten. Folder structure is preserved, name collisions receive numeric suffixes, and a failed or cancelled batch is rolled back.

## Language and automation

Choose System, English, or Simplified Chinese in **Settings → General → Language**. The change applies immediately.

For scripts and agents, build the `FileIslandCLI` scheme and query `fileisland capabilities --json` before conversion. CLI calls use explicit paths and the caller's filesystem permissions; they do not inherit the GUI output-folder bookmark. See the examples in the main README.

## Troubleshooting

- If the Island is not visible, look for the File Island menu-bar icon and confirm the app is running.
- If a file is blocked, compare it with the [format matrix](FORMAT_MATRIX.md); an extension alone does not guarantee that the underlying media stream is decodable.
- If saving fails, choose another writable output folder in Settings and confirm adequate free space.
- Report reproducible bugs through GitHub Issues without attaching private media.

## Uninstall

1. Quit File Island from its menu-bar menu.
2. Move **File Island.app** from Applications to the Trash.
3. Optional: remove the app's sandbox container from `~/Library/Containers/com.treafree.FileIsland` only if you also want to erase its saved output-folder authorization and preferences.

Uninstalling File Island does not delete source media or previously converted outputs.
