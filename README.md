# File Island

File Island is a native macOS utility that keeps a compact drop target near the top of the current display. Tasks 001–008.3 establish the Island interaction, safe file/folder inspection, common image conversion, native and fallback video conversion, data-driven presets, heterogeneous batch execution, and a shared Core with a structured CLI. Milestone 9 adds the restrained motion, real-progress light treatment, and menu-bar feedback that finish the first MVP interaction pass. Drag supported Finder files or an ordinary folder into the compact Island, confirm the settings, and convert without changing the sources.

`DEVELOPMENT_SPEC.md` is the project's only development specification and source of truth.

File Island is **source-available, not open source**. Its original code and branding are All Rights Reserved under [`LICENSE`](LICENSE). Bundled FFmpeg remains independently available under LGPL-2.1-or-later; see [`Legal/THIRD_PARTY_NOTICES.md`](Legal/THIRD_PARTY_NOTICES.md).

## Current scope

Implemented through Milestone 9:

- native SwiftUI + AppKit macOS application;
- non-activating, borderless top panel;
- compact, drag-hover, inspection, and dropped-summary states;
- local Finder file URL drop handling;
- asynchronous shallow file inspection using Foundation and `UTType`;
- exact HEIC, HEIF, JPG/JPEG, PNG, WebP, TIFF, MOV, MP4, M4V, MKV, and WebM recognition using type conformance first and normalized extension fallback when required;
- broad image, video, audio, and other classification for unknown formats;
- physical-notch height and width derived at runtime from safe-area and auxiliary top-area geometry, with proportional side wings and a floating-pill fallback;
- a pure-black notched silhouette with a 2–3 pt adaptive lower lip reserved for future processing-light feedback;
- top-centered layout that supports non-zero and negative screen coordinates;
- native ImageIO decoding for HEIC/HEIF/JPEG/PNG/WebP/TIFF with verified JPEG or PNG output, including same-format resize/compression/metadata processing;
- explicit opaque white compositing when an alpha image is converted to JPEG, while PNG output preserves alpha;
- original size, 2048 px, and 1280 px longest-edge choices without upscaling;
- JPEG quality choices and optional source-metadata removal;
- per-file target-size choices of 5 MB, 1 MB, and 500 KB, with adaptive JPEG quality and dimension fallback;
- native AVFoundation conversion from MOV/MP4/M4V to high-compatibility H.264/AAC MP4;
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
- recursive ordinary-folder discovery outside the main actor, with hidden items, packages, and symbolic links excluded;
- safe relative-path preservation for nested output folders with absolute, parent-component, symlink, and root-escape rejection;
- heterogeneous grouping into images, native videos, fallback videos, and unsupported files, with independent image/video settings and one Start action;
- batch-wide staging, monotonic aggregate progress, current/total file reporting, bounded group scheduling, cancellation, collision-safe publication, and whole-batch rollback;
- batch conversion with monotonic real progress, cancellation, and rollback on failure;
- collision-safe output naming (`name.jpg`, `name-2.jpg`, …) that never overwrites an input or existing output;
- one-time output-folder selection persisted as an app-scoped security-scoped bookmark, with automatic reuse and stale-bookmark refresh;
- a menu-bar item with Settings, output-folder, about, license, issue-reporting, and quit actions, plus an eight-frame conversion animation that slows with real progress;
- a reusable centered Settings window for output, login, image defaults, reveal behavior, and Island opacity;
- a wider, thinner action layout with Quick Look thumbnail, source details, and file-type-aware controls;
- physical-notch left/right status wings that keep the runtime-derived central camera region empty;
- structured conversion errors and Reveal in Finder after success;
- a UI-independent `FileIslandCore` used by both the app and the `fileisland` CLI;
- versioned JSON capability/inspection output and JSON Lines conversion progress with stable exit codes;
- an optional, repository-local Codex Skill for safe structured automation;
- top-anchored 300 ms expansion and 240 ms collapse transitions, coordinated phase-keyed content fades, and a translucent material treatment on floating displays;
- a real fraction-driven lower-edge progress line, restrained preparing comet, compact three-second success hold, and hover-safe automatic collapse;
- Reduce Motion behavior that removes window and continuous decorative movement while retaining static state and progress feedback;
- functional Settings navigation across General, Conversion, Appearance, and About;
- unit and integration tests for layout, state mapping, inspection, planning, output policy, and real ImageIO encoding.

Not implemented yet:

- AI or server features;
- exact-byte fallback video targeting, custom bitrate, audio-only conversion, or media editing;
- WebP image output, animated images, RAW conversion, or unstructured natural-language automation;
- custom presets, remote preset updates, and platform-specific WeChat/Bilibili/Discord rules.

Task 006 adds optional per-file video size ceilings. Source/1080p/720p remain resolution ceilings; when a size target is selected, File Island may automatically use a lower internal resolution tier to satisfy it.

Task 007 adds MKV/WebM fallback conversion. Source/1080p/720p still mean maximum picture dimensions, not file sizes. Target-size controls remain available for native MOV/MP4/M4V conversion, but are intentionally hidden for MKV/WebM because this first hardware-encoded fallback does not promise a byte limit.

Task 008 adds shortcuts over existing conversion capabilities; it does not add a new codec or format. Presets are loaded from `FileIsland/Resources/Presets/built-in-presets.json`, filtered for the current batch, and converted into the same validated intents and plans used by manual controls.

Task 008.1 centralizes the executable media matrix. WebP is input-only because the target ImageIO runtime has no WebP destination and the bundled FFmpeg build has no WebP encoder; JPEG and PNG are the only verified image outputs.

Task 008.2 adds safe ordinary-folder discovery and heterogeneous batches. Folder structure is preserved relative to each dropped root, unsupported files remain fail-closed, and every executable group must succeed before any batch output is kept.

Task 008.3 adds `FileIslandCore` and the `fileisland` command-line target. The App and CLI compose the same scanner, capability matrix, preset resolver, planners, coordinator, and engines. The CLI never reads the GUI bookmark and never invokes a shell.

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

## Command-line interface

Build the shared `FileIslandCLI` scheme. The product consists of three adjacent files: `fileisland`, `built-in-presets.json`, and `ffmpeg`.

```sh
xcodebuild -project FileIsland.xcodeproj \
  -scheme FileIslandCLI \
  -destination 'platform=macOS' \
  -derivedDataPath .build/DerivedData \
  CODE_SIGNING_ALLOWED=NO \
  build
```

Query the machine-readable capability matrix before choosing parameters:

```sh
.build/DerivedData/Build/Products/Debug/fileisland capabilities --json
```

Inspect explicit files, or opt into recursive traversal for an ordinary folder:

```sh
.build/DerivedData/Build/Products/Debug/fileisland inspect \
  '/path/含 空格的文件夹' --recursive --json
```

Convert a heterogeneous folder with independent image and video settings:

```sh
.build/DerivedData/Build/Products/Debug/fileisland convert \
  '/path/input folder' --recursive \
  --output '/path/output folder' \
  --image-format jpeg --image-max-dimension 2048 --strip-metadata \
  --video-resolution 1080p --json
```

For preset-driven calls, use `--image-preset <id>` or `--video-preset <id>` instead of the corresponding manual options. `stdout` is versioned JSON for capabilities/inspection and JSON Lines for conversion events; diagnostics go to `stderr`. Exit codes are `0` success, `2` invalid arguments, `3` unsupported request, `4` permission denied, `5` cancelled, `6` conversion failure, and `7` success with skipped or fail-closed inputs.

Paths are accessed with the caller's existing filesystem permissions. CLI calls do not reuse the App's security-scoped output bookmark. The output directory must already exist, source files are never overwritten, and paths beginning with `-` can be passed after `--` where positional arguments are accepted.

For a distributable adjacent-file bundle, run `Scripts/package-cli.sh`. It creates `.build/fileisland-cli/`, verifies arm64/x86_64 slices in both executables and the runtime resources, and ad-hoc signs local builds by default. Set `FILEISLAND_SIGN_IDENTITY` to a Developer ID Application identity for distribution; notarization and release packaging remain maintainer release steps.

## Release readiness

The current Release build is runtime-self-contained: `FileIsland.app` and its bundled FFmpeg executable are universal arm64/x86_64 binaries, the preset catalog is inside the app bundle, and FFmpeg depends only on Apple system libraries and frameworks. A user of a properly packaged release will not need Homebrew, a separate FFmpeg download, Python, Node.js, or another runtime.

The first public artifact is `v0.1.0`, an explicitly **unsigned/ad-hoc signed early-access build** available from [GitHub Releases](https://github.com/TREAFREE/FileIsland/releases). It is not signed with Apple Developer ID and has not been notarized by Apple. Verify the attached SHA-256 checksum before installation.

macOS will normally block the first launch. Try to open File Island once, then use **System Settings → Privacy & Security → Open Anyway** only when the DMG came from the official Release and its checksum matched. Do not disable Gatekeeper. Managed Macs may prohibit this override.

Each binary Release includes or links all of the following:

- the universal arm64/x86_64 File Island app and bundled FFmpeg;
- File Island's proprietary source-available terms;
- the complete LGPL text, third-party notice, exact corresponding FFmpeg source, signature/build provenance, and checksums;
- release notes, privacy policy, security reporting, supported formats, and known limitations.

Maintainers can reproduce the artifact with `Scripts/package-release.sh`. The complete checklist and future Developer ID/notarization upgrade path are documented in [`docs/RELEASE_DMG_GUIDE.zh-CN.md`](docs/RELEASE_DMG_GUIDE.zh-CN.md). A future trusted one-click build still requires Apple Developer Program membership, Developer ID signing, notarization, stapling, and clean-machine Gatekeeper verification.

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

The automated test target verifies HEIC, HEIF, JPG, PNG, WebP, TIFF, MOV, MP4, M4V, MKV, and WebM as a fixed acceptance matrix. For a manual check, drop one ordinary file of each available type and confirm the summary label reports the expected uppercase format and byte size. These checks validate identification only; engine integration tests separately verify media decodability and output.

## Task 003 image conversion check

1. Launch the app and drag a HEIC or PNG into the Island.
2. Choose **Continue**, select JPEG settings, and choose **Start**.
3. On first use, select an output folder in the system panel. Confirm later conversions reuse it without asking again, collapse to real conversion progress, and then show **Done**.
4. Use **Show in Finder** and open the result in Preview.
5. Repeat with a JPEG and confirm both JPEG processing and PNG conversion are available.
6. For a batch, confirm colliding names receive `-2`, `-3`, and later suffixes. Cancel a conversion and confirm no partial outputs remain.

The system asks for an output directory only when no valid saved authorization exists. Change it later from **Settings → General**. Cancelling the first-use panel keeps the selected settings and writes nothing.

## Task 004 target-size check

1. Drag a supported image into the Island and choose JPEG or PNG.
2. Choose a per-file target such as **500 KB**, then start conversion.
3. Confirm the output opens in Preview, is non-empty, and does not exceed the selected limit.
4. Repeat with a detailed image and a strict target; confirm JPEG adapts quality before dimensions, while PNG may reduce dimensions.
5. Confirm an unreachable target reports that the selected size is too small and leaves no partial output.

## Task 005 native video check

1. Drag a MOV, MP4, or M4V into the Island and confirm the right side shows only MP4, high compatibility, and Source/1080p/720p controls.
2. Start the conversion and confirm the saved output folder is reused without another prompt.
3. Open the result in QuickTime Player and confirm video, audio (when present), duration, and portrait/landscape orientation are correct.
4. Convert a smaller source with 1080p or 720p selected and confirm it is not enlarged.
5. Convert an MP4 into the same folder and confirm the source is preserved and the result uses a collision-safe suffix such as `-2`.
6. Cancel a conversion, then try a batch containing a bad file, and confirm neither operation leaves completed or temporary outputs from that batch.

## Task 006 video target-size check

1. Drag a MOV, MP4, or M4V into the Island and choose **100M**, **50M**, or **Custom** under Target.
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
6. From the menu-bar item, open **Third-party Licenses** and confirm the FFmpeg notice is present.

## Task 008 preset check

1. Drag a MOV/MP4/M4V into the Island, open **Presets**, and confirm Windows Compatible, Web Friendly, and Under 100 MB are available.
2. Select Web Friendly and confirm the resolution becomes 1080p; change it manually to 720p and confirm the preset label returns to **Presets**.
3. Drag an MKV/WebM and confirm Under 100 MB is absent while the other two video presets remain available.
4. Drag a PNG or HEIC, select Image for Web, and confirm JPEG, 2048 px, balanced quality, and metadata removal are selected.
5. Drag a JPEG and confirm Image for Web is offered as a same-format resize/compression/metadata workflow and never overwrites the source.
6. Confirm the Island remains the same height when the compact preset menu appears.

## Task 008.1 common media check

1. Drag a small WebP and a TIFF, choose JPEG or PNG, and confirm each result opens in Preview and the original remains unchanged.
2. Convert a transparent PNG to JPEG and confirm transparent areas are composited onto opaque white; convert it to PNG and confirm transparency remains.
3. Choose JPEG for a JPEG or PNG for a PNG, change size/target/metadata settings, and confirm File Island creates a collision-safe processed copy rather than overwriting the source.
4. Drag a readable M4V with audio and confirm the output is a playable H.264/AAC MP4; exercise a size target and confirm it behaves like MOV/MP4.
5. Confirm a native-video plus MKV/WebM mixed batch is rejected instead of silently routing part of the batch through the wrong engine.

## Task 008.2 folder and heterogeneous batch check

1. Create an ordinary folder with nested supported images, MOV/MP4/M4V, MKV/WebM, an unknown text file, a hidden file, a package, and symbolic links; drag the folder into the Island.
2. Confirm only ordinary visible files appear, then use the compact Image, Video, and Other group controls and verify their counts.
3. Configure image and video parameters separately, switch between the groups, and confirm both sets of choices remain intact.
4. Before starting, confirm the Island reports process, skip, and fail-closed counts; click Start once.
5. Confirm outputs appear beneath the persisted output folder using the source-relative nested directories and collision-safe names.
6. Cancel a larger batch and confirm no new output or `.fileisland-*` staging directory remains.
7. Cause a later group to fail and confirm earlier group outputs are also absent, then convert one explicit file and confirm the established single-file behavior is unchanged.

## Task 008.3 CLI check

1. Build the `FileIslandCLI` scheme and confirm the executable, preset JSON, and FFmpeg are adjacent in the products directory.
2. Run `capabilities --json` and confirm it reports schema version 1 without launching File Island.
3. Inspect Unicode and space-containing paths; confirm a folder is rejected without `--recursive` and accepted with it.
4. Convert a small image into an existing output directory and confirm JSON Lines report preparing, running, and completed states without printing the absolute output path.
5. Confirm unknown input, invalid arguments, cancellation, and partial skips use distinct documented exit codes.
6. Run `Scripts/package-cli.sh` and verify `.build/fileisland-cli/fileisland capabilities --json` succeeds.

## Milestone 9 UX check

1. On the built-in notched display, drag a supported file into the physical notch and confirm expansion remains centered and attached to the top edge, with no content inside the camera occlusion.
2. Move rapidly in and out of the target and confirm the 300 ms expansion and 240 ms collapse remain interruptible without jumping away from the top edge.
3. Start a conversion and confirm the Island contracts, the lower-edge line shows real conversion progress, Cancel remains usable, and the menu-bar frame rate gradually slows as progress approaches completion.
4. Confirm the one-row completion state remains visible for about three seconds, stays open while the pointer is over the Island, and collapses after the pointer leaves. Confirm failures do not auto-collapse.
5. Enable **System Settings → Accessibility → Display → Reduce motion** and repeat: window and continuous highlight movement should stop while progress, copy, and semantic icons remain visible.
6. When an external non-notched display is available, repeat the path and confirm the compact Island uses the restrained translucent floating-pill material.
7. Open Settings and switch through General, Conversion, Appearance, and About; confirm every pane redraws immediately.

## Repository notes

- No third-party package manager or generated-project tool is required. FFmpeg provenance, license, corresponding source, signature, and reproducible build details are under `Legal/`; rebuild with `Scripts/build-ffmpeg.sh` when GnuPG is installed.
- The application is an accessory app with no Dock icon. Use its menu-bar item for Settings, output-folder access, and Quit.
- After changing synchronized target membership, an old repository-local DerivedData cache can expose a stale Swift module. If types unexpectedly disappear during testing, run the documented `xcodebuild ... clean` once and rerun the same build/test command.
- File Island's original source and branding use the proprietary source-available terms in `LICENSE`; external code contributions are not accepted without a future written contribution agreement.
- Privacy, security reporting, asset provenance, FFmpeg obligations, and commercialization gates are documented in `PRIVACY.md`, `SECURITY.md`, and `Legal/`.
