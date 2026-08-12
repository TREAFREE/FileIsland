# File Island Complete User Guide

[简体中文](USER_GUIDE.zh-CN.md) · [Project home](../README.md) · [Format matrix](FORMAT_MATRIX.md)

File Island keeps conversion work on your Mac. The DMG includes the required FFmpeg, ffprobe, and media-validation runtime; Homebrew, Python, Node.js, and separate codec packages are not required.

## 1. Download and verify

1. Open the official [GitHub Releases](https://github.com/TREAFREE/FileIsland/releases/latest) page.
2. Download the latest `.dmg` and its matching `.sha256` file.
3. In Terminal, type `shasum -a 256 `, drag the DMG into the window, and press Return.
4. Compare the displayed checksum character-for-character with the supplied file.

A checksum detects corruption or replacement, but the current ad-hoc signed build is not equivalent to Developer ID publisher authentication.

## 2. Install and open for the first time

1. Double-click the DMG.
2. Drag **File Island.app** onto the **Applications** shortcut in the same window. Do not use the copy inside the mounted DMG as a permanent installation.
3. Wait for copying to finish, eject the DMG, and optionally delete the downloaded DMG.
4. Open **File Island** from Applications.

The current early-access build is not signed with Apple Developer ID and is not notarized. If macOS blocks its first launch:

1. Try to open it normally once.
2. Open **System Settings → Privacy & Security**.
3. Find the blocked File Island entry and choose **Open Anyway**.
4. Confirm only when the DMG came from this repository's official Release and its checksum matched.

Never disable Gatekeeper. Managed Macs may prohibit manual overrides.

## 3. Convert images

[![Play the image conversion demo](assets/demos/image-conversion.jpg)](assets/demos/image-conversion.mp4)

> Click the poster to play the image batch-conversion demo.

1. Select one or more supported images in Finder and drag them to the Island at the top of the screen.
2. Choose **Continue**, then select JPEG or PNG in the image group.
3. Configure longest edge, JPEG quality, per-file target size, and metadata removal as needed.
4. Choose **Start**.
5. On the first conversion, authorize a persistent output folder. File Island reuses that authorization later.
6. When complete, choose **Show in Finder**.

JPEG is a good default for photographs and smaller files. PNG suits transparency or lossless pixels. Transparent regions are composited onto white when converting to JPEG. A target-size limit applies to each output file, not to the whole batch combined.

## 4. Convert or split video for sharing

[![Play the video conversion and splitting demo](assets/demos/video-conversion-and-splitting.jpg)](assets/demos/video-conversion-and-splitting.mp4)

> Click the poster to play ordinary conversion and fast splitting.

### Convert

1. Drop a supported video.
2. Select **Convert**.
3. Output uses high-compatibility H.264/AAC MP4.
4. **Source, 1080p, and 720p** are picture-dimension ceilings, not file-size settings. Smaller sources are not enlarged.
5. Native video inputs can also use a per-file target size. File Island may reduce dimensions internally to meet a strict size.
6. Choose **Start** and keep the app running until completion.

### Split for Sharing

This mode creates independently playable pieces for sending a long video.

1. Drop an MP4/MOV containing H.264 video and AAC audio or no audio.
2. Select **Split for Sharing**.
3. Enable a maximum size, a maximum duration, or both.
4. Size supports MB/GB and duration supports seconds/minutes/hours. Changing units preserves the actual limit.
5. Use the slider for common values or enter an exact positive number.
6. Review the estimated segment count and choose **Start**.

The current fast mode copies existing encoded streams at safe keyframes and does not intentionally reduce quality. If the source keyframes cannot satisfy the selected limits, File Island stops without publishing incomplete results. Outputs appear in a complete `Movie — Split` folder with collision-safe numeric suffixes.

## 5. Convert audio

[![Play the audio conversion demo](assets/demos/audio-conversion.jpg)](assets/demos/audio-conversion.mp4)

> Click the poster to play audio batch conversion.

1. Drop one or more audio files.
2. Select M4A, WAV, FLAC, or AIFF output.
3. Choose quality where applicable and whether to remove audio metadata.
4. Choose **Start**.

MP3 is accepted as input but is not offered as output. M4A suits everyday playback and compact files; WAV/AIFF suits PCM workflows; FLAC suits lossless compressed archives.

## 6. Convert a mixed folder

[![Play the mixed-folder demo](assets/demos/mixed-folder.jpg)](assets/demos/mixed-folder.mp4)

> Click the poster to play a folder containing images, video, and audio.

1. Drag an ordinary folder directly to the Island.
2. File Island recursively discovers media while excluding hidden items, apps/packages, and symbolic links.
3. Switch among image, video, and audio groups. Each group shows only applicable controls.
4. Configure every group you want to execute, then choose **Start** once.
5. Output preserves the source folder's relative structure.

The batch uses safe staging and retains final results only after every executable group succeeds. Cancelling or failing rolls back that batch. Unsupported files are not presented as converted. Name collisions receive `-2`, `-3`, and later suffixes; sources are never overwritten.

## 7. Settings, language, and output folder

[![Play the settings demo](assets/demos/settings.jpg)](assets/demos/settings.mp4)

> Click the poster to play the menu-bar and Settings tour.

Choose **Settings** from the File Island menu-bar item:

- **General**: output folder, launch at login, reveal behavior, optional single-output Clipboard copy, and interface language;
- **Conversion**: default image quality and metadata preference;
- **Appearance**: Island opacity;
- **About**: app icon, version, and project links.

Language choices are System, English, and Simplified Chinese. Changes apply immediately without interrupting current conversion work.

## 8. Troubleshooting

### Why does Spotlight show several copies of File Island?

After building with Xcode, Spotlight may index the installed app plus Debug, Release, and Xcode index products. This does not mean the app was installed four times. The normal installation is usually `/Applications/File Island.app`; development copies live under the repository's `build/` folder or `~/Library/Developer/Xcode/DerivedData/`. Quit development builds and remove those generated products to hide stale search results.

### The Island is not visible

Look for the File Island menu-bar item and confirm the app is running. On a notched Mac, the compact drop region sits near the notch. Other displays use a small centered pill.

### A file is unsupported

Check the [format matrix](FORMAT_MATRIX.md). A matching extension does not guarantee that the underlying streams are supported. File Island inspects the media and fails closed when it cannot validate the request.

### Saving fails

Choose a writable folder again in **Settings → General** and confirm sufficient free disk space. Do not choose the read-only mounted DMG as an output location.

### Uninstall

1. Quit File Island from its menu-bar menu.
2. Move **File Island.app** from Applications to the Trash.
3. Remove `~/Library/Containers/com.treafree.FileIsland` only if you also want to erase preferences and the saved output-folder authorization.

Uninstalling does not delete source media or previously generated outputs.

## 9. Report an issue

Use [GitHub Issues](https://github.com/TREAFREE/FileIsland/issues) for reproducible bugs and include the macOS version, File Island version, input format, and steps. Do not attach private media to a public issue. Report unresolved security concerns privately under the [security policy](../SECURITY.md).
