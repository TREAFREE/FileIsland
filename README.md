# File Island

<p align="center">
  <img src="docs/assets/FileIslandLogo.png" width="112" alt="File Island icon">
</p>

<p align="center">
  <strong>Drop images, videos, audio, or a whole folder at the top of your Mac and convert locally.</strong><br>
  File Island stays quietly near the notch until you need it. No media upload and no separate FFmpeg installation.
</p>

<p align="center">
  <a href="README.zh-CN.md">简体中文</a> ·
  <a href="https://github.com/TREAFREE/FileIsland/releases/latest">Download</a> ·
  <a href="docs/USER_GUIDE.md">User guide</a> ·
  <a href="docs/FORMAT_MATRIX.md">Format matrix</a>
</p>

<p align="center">
  <a href="https://github.com/TREAFREE/FileIsland/actions/workflows/ci.yml"><img src="https://github.com/TREAFREE/FileIsland/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="https://github.com/TREAFREE/FileIsland/releases/latest"><img src="https://img.shields.io/github/v/release/TREAFREE/FileIsland" alt="Latest release"></a>
  <a href="https://github.com/TREAFREE/FileIsland/releases"><img src="https://img.shields.io/github/downloads/TREAFREE/FileIsland/total" alt="Downloads"></a>
  <img src="https://img.shields.io/badge/macOS-15%2B-111111?logo=apple" alt="macOS 15+">
  <img src="https://img.shields.io/badge/Apple%20Silicon%20%7C%20Intel-Universal-555555" alt="Universal">
  <img src="https://img.shields.io/badge/local--first-no%20upload-2f855a" alt="Local first">
</p>

## See it in 11 seconds

[![File Island mixed-folder demo](docs/assets/demos/mixed-folder.jpg)](https://treafree.top/FileIsland/#mixed-folder)

> Click the poster to play in your browser. One folder containing images, video, and audio can be configured by media type and converted as a single batch.

## Why File Island

Full commercial conversion suites can be capable but may use one-time or subscription pricing. Browser converters are convenient but usually require an upload. FFmpeg is exceptionally flexible, but not everyone wants to memorize commands. File Island offers a native Mac alternative: a quiet Finder-first interface for common local media work, with safe batching and an automation API when you need it.

| Workflow | File Island | Browser converters | Single-purpose GUI apps | FFmpeg CLI |
| --- | --- | --- | --- | --- |
| Images, video, and audio in one place | ✅ | Varies | Usually one media family | ✅ |
| Mixed-folder batch processing | ✅ | Usually upload-limited | Varies | Requires commands/scripts |
| Media stays on the Mac | ✅ | Usually uploaded | ✅ | ✅ |
| Finder drag-and-drop controls | ✅ | ✅ | ✅ | — |
| Structured CLI / agent use | ✅ | — | Uncommon | ✅ |
| Extra runtime setup | None; included in DMG | Browser | Varies | Install and maintain separately |

File Island does not try to replace a professional editor or claim formats and sharing rules that have not been verified. It fails closed and preserves sources when a request cannot be completed safely.

## Highlights

- native SwiftUI + AppKit interface for notched and non-notched Macs;
- single files, multiple selections, and ordinary-folder drops;
- type-aware image, video, and audio groups with independent controls;
- heterogeneous folder batches with relative folder structure preserved;
- JPEG/PNG image output with dimensions, quality, target size, and metadata controls;
- high-compatibility H.264/AAC MP4 video output with Source, 1080p, 720p, and target-size choices;
- M4A, WAV, FLAC, and AIFF audio output;
- fast size- and/or duration-constrained splitting for eligible H.264 MP4/MOV files without re-encoding the streams;
- one-time output-folder authorization, collision-safe names, optional single-output Clipboard copy, and no source overwrite;
- local-only processing with no account, ads, analytics SDK, or media upload;
- bundled universal FFmpeg/ffprobe and an isolated media validator—Homebrew is not required;
- English, Simplified Chinese, and System language modes;
- a shared conversion core for the app and structured `fileisland` CLI.

See the [format matrix](docs/FORMAT_MATRIX.md) for the exact verified input and output scope.

## Download, install, and use

Install with Homebrew:

```sh
brew install --cask treafree/tap/file-island
```

Or install the DMG manually:

1. Download the DMG and matching SHA-256 from [GitHub Releases](https://github.com/TREAFREE/FileIsland/releases/latest).
2. Verify the checksum, open the DMG, and drag **File Island.app** to **Applications**.

Then launch File Island from Applications, drag media or a folder from Finder to the Island at the top of the screen, configure each media group, and choose **Start**. Authorize a persistent output folder on first use; later conversions reuse that folder automatically.

The current early-access build is not signed with Apple Developer ID and is not notarized. macOS may block its first launch. Try to open it once, then use **System Settings → Privacy & Security → Open Anyway** only for a checksum-verified DMG from this repository's official Release. Never disable Gatekeeper.

The Homebrew cask installs the same unsigned release artifact, so the same first-launch warning may apply. Future releases require a version and checksum update in the [`TREAFREE/homebrew-tap`](https://github.com/TREAFREE/homebrew-tap) repository before `brew upgrade --cask file-island` can install them.

For illustrated, step-by-step videos, read the [complete user guide](docs/USER_GUIDE.md).

## Demos

| Image conversion | Video conversion and splitting |
| --- | --- |
| [![Image conversion](docs/assets/demos/image-conversion.jpg)](https://treafree.top/FileIsland/#image) | [![Video conversion and splitting](docs/assets/demos/video-conversion-and-splitting.jpg)](https://treafree.top/FileIsland/#video) |
| [▶ Play image demo](https://treafree.top/FileIsland/#image) | [▶ Play video demo](https://treafree.top/FileIsland/#video) |

| Audio conversion | Settings and language |
| --- | --- |
| [![Audio conversion](docs/assets/demos/audio-conversion.jpg)](https://treafree.top/FileIsland/#audio) | [![Settings](docs/assets/demos/settings.jpg)](https://treafree.top/FileIsland/#settings) |
| [▶ Play audio demo](https://treafree.top/FileIsland/#audio) | [▶ Play settings demo](https://treafree.top/FileIsland/#settings) |

## Current limitations

- macOS 15 or newer is required;
- MP3 is accepted as input but is not offered as output;
- WebP is currently input-only;
- fast splitting accepts H.264 MP4/MOV with AAC audio or no audio;
- fast splitting depends on existing source keyframes and fails safely when the selected limits cannot be met;
- RAW, animated-image output, precise re-encoded splitting, general editing/merging, and natural-language commands are not implemented;
- platform presets for services such as WeChat, Bilibili, or Discord are not published until their rules can be verified.

## Build from source

Requirements: macOS 15+, Xcode 16.4+, and Swift 6.

```sh
xcodebuild -project FileIsland.xcodeproj \
  -scheme FileIsland \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

```sh
xcodebuild -project FileIsland.xcodeproj \
  -scheme FileIsland \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  test
```

## Command-line interface

Build the shared `FileIslandCLI` scheme. Keep these five adjacent runtime files together: `fileisland`, `ffmpeg`, `ffprobe`, `FileIslandMediaValidator`, and `built-in-presets.json`.

```sh
xcodebuild -project FileIsland.xcodeproj \
  -scheme FileIslandCLI \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Always query the machine-readable capabilities before generating a call:

```sh
.build/DerivedData/Build/Products/Debug/fileisland capabilities --json
```

Convert a heterogeneous folder:

```sh
.build/DerivedData/Build/Products/Debug/fileisland convert \
  '/path/input folder' --recursive \
  --output '/path/output folder' \
  --image-format jpeg --image-max-dimension 2048 --strip-metadata \
  --video-resolution 1080p \
  --audio-format m4a --audio-quality balanced --strip-audio-metadata \
  --json
```

Split an eligible video at safe keyframes without re-encoding:

```sh
.build/DerivedData/Build/Products/Debug/fileisland split \
  '/path/movie.mp4' \
  --output '/path/output folder' \
  --max-duration-seconds 300 \
  --mode fast-keyframe-copy \
  --json
```

The CLI uses the caller's filesystem permissions and does not reuse the app's saved output-folder bookmark. Sources are never overwritten. Exit codes and exact options are reported by `--help` and `capabilities --json`.

## Privacy, licensing, and feedback

File Island is **source-available, not open source**. Original code, branding, and assets are All Rights Reserved under [`LICENSE`](LICENSE). Bundled FFmpeg remains independently available under LGPL-2.1-or-later.

- [User guide](docs/USER_GUIDE.md)
- [Format matrix](docs/FORMAT_MATRIX.md)
- [Changelog](CHANGELOG.md)
- [Privacy policy](PRIVACY.md)
- [Security reporting](SECURITY.md)
- [Third-party notices](Legal/THIRD_PARTY_NOTICES.md)
- [FFmpeg build and source record](Legal/FFMPEG_BUILD.md)

Use [GitHub Issues](https://github.com/TREAFREE/FileIsland/issues) for ordinary bug reports. Report unresolved security issues privately as described in [`SECURITY.md`](SECURITY.md), and do not attach private media to public issues.
