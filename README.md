# File Island

File Island is a native macOS utility that keeps a compact drop target near the top of the current display. Tasks 001–008 establish the Island interaction, shallow file inspection, image conversion, native and fallback video conversion, and data-driven conversion presets, plus the menu-bar/settings shell. Drag a supported Finder image or video into the compact Island, confirm the settings, and convert without changing the source file.

`DEVELOPMENT_SPEC.md` is the project's only development specification and source of truth.

## Current scope

Implemented through Task 008:

- native SwiftUI + AppKit macOS application;
- non-activating, borderless top panel;
- compact, drag-hover, inspection, and dropped-summary states;
- local Finder file URL drop handling;
- asynchronous shallow file inspection using Foundation and `UTType`;
- exact HEIC, JPG/JPEG, PNG, WebP, MOV, MP4, MKV, and WebM recognition using type conformance first and normalized extension fallback when required;
- broad image, video, audio, and other classification for unknown formats;
- physical-notch height and width derived at runtime from safe-area and auxiliary top-area geometry, with proportional side wings and a floating-pill fallback;
- a pure-black notched silhouette with a 2–3 pt adaptive lower lip reserved for future processing-light feedback;
- top-centered layout that supports non-zero and negative screen coordinates;
- native ImageIO conversion for HEIC → JPEG, PNG → JPEG, and JPEG → PNG;
- original size, 2048 px, and 1280 px longest-edge choices without upscaling;
- JPEG quality choices and optional source-metadata removal;
- per-file target-size choices of 5 MB, 1 MB, and 500 KB, with adaptive JPEG quality and dimension fallback;
- native AVFoundation conversion from MOV/MP4 to high-compatibility H.264/AAC MP4;
- Source, 1080p, and 720p video resolution choices without upscaling smaller inputs;
- real system-reported video progress, cancellation, batch rollback, and output validation for codec, duration, audio, and orientation;
- per-file video target choices of 100 MB, 50 MB, and custom 5 MB steps from 5 MB through 2000 MB;
- duration-aware bitrate budgeting with a 95% safety limit and automatic 2160p/1080p/720p/540p/480p fallback;
- audited FFmpeg 8.1.2 fallback conversion from MKV/WebM to H.264 VideoToolbox/AAC MP4;
- universal arm64/x86_64 bundled executable built from signature-verified official source with networking, GPL, nonfree, and external codecs disabled;
- direct `Process` execution without a shell, machine-readable progress, bounded path-redacted diagnostics, active child-process cancellation, and AVFoundation output validation;
- a versioned bundled JSON preset catalog with strict schema and semantic validation;
- Windows Compatible, Web Friendly, Image for Web, and Under 100 MB presets filtered against the current batch’s real conversion capability;
- editable preset application: changing a parameter returns the UI to manual state instead of claiming the original preset still applies;
- batch conversion with monotonic real progress, cancellation, and rollback on failure;
- collision-safe output naming (`name.jpg`, `name-2.jpg`, …) that never overwrites an input or existing output;
- one-time output-folder selection persisted as an app-scoped security-scoped bookmark, with automatic reuse and stale-bookmark refresh;
- a static menu-bar item with Settings, output-folder, about, license, issue-reporting, and quit actions;
- a reusable centered Settings window for output, login, image defaults, reveal behavior, and Island opacity;
- a wider, thinner action layout with Quick Look thumbnail, source details, and file-type-aware controls;
- physical-notch left/right status wings that keep the runtime-derived central camera region empty;
- structured conversion errors and Reveal in Finder after success;
- unit and integration tests for layout, state mapping, inspection, planning, output policy, and real ImageIO encoding.

Not implemented yet:

- AI or server features;
- exact-byte fallback video targeting, custom bitrate, audio-only conversion, M4V conversion, or media editing;
- advanced notch alignment and polished motion.
- multi-frame variable-speed menu-bar animation and processing border light effects.
- custom presets, remote preset updates, and platform-specific WeChat/Bilibili/Discord rules.

Task 004 keeps the Task 003 image conversion matrix unchanged. It does not inspect video duration/codecs or accept WebP as a conversion source or destination.

Task 005 adds only the native MOV/MP4 video path. It does not add video target-size compression, FFmpeg fallback, or broader container support.

Task 006 adds optional per-file video size ceilings. Source/1080p/720p remain resolution ceilings; when a size target is selected, File Island may automatically use a lower internal resolution tier to satisfy it.

Task 007 adds MKV/WebM fallback conversion. Source/1080p/720p still mean maximum picture dimensions, not file sizes. Target-size controls remain available for native MOV/MP4 conversion, but are intentionally hidden for MKV/WebM because this first hardware-encoded fallback does not promise a byte limit.

Task 008 adds shortcuts over existing conversion capabilities; it does not add a new codec or format. Presets are loaded from `FileIsland/Resources/Presets/built-in-presets.json`, filtered for the current batch, and converted into the same validated intents and plans used by manual controls.

## Requirements

- macOS 15 or newer;
- Xcode 26.1 or newer;
- Swift 6;
- Apple Silicon or Intel Mac supported by the selected macOS SDK.

## Build and test

Open `FileIsland.xcodeproj` in Xcode and run the shared `FileIsland` scheme, or use:

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

## Task 001 smoke test

1. Launch the app from Xcode.
2. On a notched Mac, confirm the compact drop region is hidden in the physical notch; on a non-notched display, confirm a compact `File Island` pill appears at the top center without activating the app.
3. Drag an ordinary file from Finder into the pill and confirm it expands.
4. While still dragging, move against the physical top screen edge and confirm the expanded Island stays open.
5. Move the pointer away before dropping and confirm the pill collapses.
6. Drop an ordinary file and confirm its name, type, and size appear below the physical notch rather than behind it.
7. Repeat on another display when available and confirm the app remains stable.

The drop target begins only at the compact panel boundary: the physical notch gap on a notched Mac, or the visible floating pill on other displays. Detecting a drag outside that boundary would require a global drag monitor or an oversized transparent interception window, both intentionally excluded from Task 001.

## Task 002 inspection check

The automated test target verifies HEIC, JPG, PNG, WebP, MOV, MP4, and MKV as a fixed acceptance matrix. For a manual check, drop one ordinary file of each available type and confirm the summary label reports the expected uppercase format and byte size. These checks validate identification only, not media decodability or conversion support.

## Task 003 image conversion check

1. Launch the app and drag a HEIC or PNG into the Island.
2. Choose **Continue**, select JPEG settings, and choose **Start**.
3. On first use, select an output folder in the system panel. Confirm later conversions reuse it without asking again, collapse to real conversion progress, and then show **Done**.
4. Use **Show in Finder** and open the result in Preview.
5. Repeat with a JPEG and confirm PNG is the available output format.
6. For a batch, confirm colliding names receive `-2`, `-3`, and later suffixes. Cancel a conversion and confirm no partial outputs remain.

The system asks for an output directory only when no valid saved authorization exists. Change it later from **Settings → General**. Cancelling the first-use panel keeps the selected settings and writes nothing.

## Task 004 target-size check

1. Drag a supported image into the Island and choose JPEG or PNG.
2. Choose a per-file target such as **500 KB**, then start conversion.
3. Confirm the output opens in Preview, is non-empty, and does not exceed the selected limit.
4. Repeat with a detailed image and a strict target; confirm JPEG adapts quality before dimensions, while PNG may reduce dimensions.
5. Confirm an unreachable target reports that the selected size is too small and leaves no partial output.

## Task 005 native video check

1. Drag a MOV or MP4 into the Island and confirm the right side shows only MP4, high compatibility, and Source/1080p/720p controls.
2. Start the conversion and confirm the saved output folder is reused without another prompt.
3. Open the result in QuickTime Player and confirm video, audio (when present), duration, and portrait/landscape orientation are correct.
4. Convert a smaller source with 1080p or 720p selected and confirm it is not enlarged.
5. Convert an MP4 into the same folder and confirm the source is preserved and the result uses a collision-safe suffix such as `-2`.
6. Cancel a conversion, then try a batch containing a bad file, and confirm neither operation leaves completed or temporary outputs from that batch.

## Task 006 video target-size check

1. Drag a MOV or MP4 into the Island and choose **100M**, **50M**, or **Custom** under Target.
2. For Custom, use the minus/plus controls and confirm the value changes in 5 MB steps without opening a text field.
3. Start conversion and confirm each output file—not the whole batch combined—stays under the selected target.
4. Try a long or high-resolution source with a strict target and confirm the output remains playable even if File Island lowers the resolution automatically.
5. Confirm **None** preserves the Task 005 resolution-only behavior.
6. Cancel or select an unreachable target and confirm no partial or hidden attempt files remain in the output folder.

## Task 007 FFmpeg fallback check

1. Drag a readable MKV or WebM into the Island and confirm the right side offers MP4, high compatibility, and Source/1080p/720p.
2. Confirm the target-size controls are absent and the engine row identifies the FFmpeg 8.1.2 fallback.
3. Start conversion, open the result in QuickTime Player, and confirm video, audio (when present), duration, and orientation are correct.
4. Confirm the source is preserved, existing output names are not overwritten, and batch progress is monotonic.
5. Cancel a conversion or try a damaged input and confirm no completed or hidden temporary files from that batch remain.
6. From the menu-bar item, open **Open-source Licenses** and confirm the FFmpeg notice is present.

## Task 008 preset check

1. Drag a MOV/MP4 into the Island, open **Presets**, and confirm Windows Compatible, Web Friendly, and Under 100 MB are available.
2. Select Web Friendly and confirm the resolution becomes 1080p; change it manually to 720p and confirm the preset label returns to **Presets**.
3. Drag an MKV/WebM and confirm Under 100 MB is absent while the other two video presets remain available.
4. Drag a PNG or HEIC, select Image for Web, and confirm JPEG, 2048 px, balanced quality, and metadata removal are selected.
5. Drag a JPEG and confirm Image for Web is not offered because Task 008 does not add unsupported JPEG-to-JPEG conversion.
6. Confirm the Island remains the same height when the compact preset menu appears.

## Repository notes

- No third-party package manager or generated-project tool is required. FFmpeg provenance, license, corresponding source, signature, and reproducible build details are under `Legal/`; rebuild with `Scripts/build-ffmpeg.sh` when GnuPG is installed.
- The application is an accessory app with no Dock icon. Use its menu-bar item for Settings, output-folder access, and Quit.
- The project license remains undecided and must be selected by the maintainer before public distribution.
