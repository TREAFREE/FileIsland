# File Island

File Island is a native macOS utility concept that keeps a compact drop target near the top of the current display. Task 001 validates the application skeleton and the Island interaction only: dragging a Finder file into the compact Island expands it, and dropping shows the file name, initial type, and size.

`DEVELOPMENT_SPEC.md` is the project's only development specification and source of truth.

## Current scope

Implemented in Task 001:

- native SwiftUI + AppKit macOS application;
- non-activating, borderless top panel;
- compact, drag-hover, inspection, and dropped-summary states;
- local Finder file URL drop handling;
- shallow file inspection using Foundation and `UTType`;
- physical-notch height and width derived at runtime from safe-area and auxiliary top-area geometry, with proportional side wings and a floating-pill fallback;
- top-centered layout that supports non-zero and negative screen coordinates;
- app sandbox with read-only access to user-selected files;
- unit tests for layout, state mapping, classification, and file inspection.

Not implemented yet:

- conversion actions or a conversion engine implementation;
- FFmpeg or any third-party dependency;
- AI or server features;
- runtime conversion progress, cancellation, or success flows;
- advanced notch alignment and polished motion.

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
4. Move the pointer away before dropping and confirm the pill collapses.
5. Drop an ordinary file and confirm its name, type, and size appear.
6. Repeat on another display when available and confirm the app remains stable.

The drop target begins only at the compact panel boundary: the physical notch gap on a notched Mac, or the visible floating pill on other displays. Detecting a drag outside that boundary would require a global drag monitor or an oversized transparent interception window, both intentionally excluded from Task 001.

## Repository notes

- No third-party package manager or generated-project tool is required.
- The application is an accessory app in this technical validation, so it has no Dock icon or menu-bar quit item yet. Stop it from Xcode or Activity Monitor.
- The project license remains undecided and must be selected by the maintainer before public distribution.
