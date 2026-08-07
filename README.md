# File Island

File Island is a native macOS utility concept that keeps a compact drop target near the top of the current display. Task 001 established the Island interaction, and Task 002 completes shallow file inspection for the first supported input matrix. Dragging a Finder file into the compact Island expands it, and dropping shows the file name, recognized type, and size.

`DEVELOPMENT_SPEC.md` is the project's only development specification and source of truth.

## Current scope

Implemented through Task 002:

- native SwiftUI + AppKit macOS application;
- non-activating, borderless top panel;
- compact, drag-hover, inspection, and dropped-summary states;
- local Finder file URL drop handling;
- asynchronous shallow file inspection using Foundation and `UTType`;
- exact HEIC, JPG/JPEG, PNG, WebP, MOV, MP4, and MKV recognition using type conformance first and normalized extension fallback when required;
- broad image, video, audio, and other classification for unknown formats;
- physical-notch height and width derived at runtime from safe-area and auxiliary top-area geometry, with proportional side wings and a floating-pill fallback;
- a pure-black notched silhouette with a 2–3 pt adaptive lower lip reserved for future processing-light feedback;
- top-centered layout that supports non-zero and negative screen coordinates;
- app sandbox with read-only access to user-selected files;
- unit tests for layout, state mapping, classification, and file inspection.

Not implemented yet:

- conversion actions or a conversion engine implementation;
- FFmpeg or any third-party dependency;
- AI or server features;
- runtime conversion progress, cancellation, or success flows;
- advanced notch alignment and polished motion.

Task 002 deliberately does not decode media content or inspect pixel dimensions, duration, codecs, or container internals.

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

## Repository notes

- No third-party package manager or generated-project tool is required.
- The application is an accessory app in this technical validation, so it has no Dock icon or menu-bar quit item yet. Stop it from Xcode or Activity Monitor.
- The project license remains undecided and must be selected by the maintainer before public distribution.
