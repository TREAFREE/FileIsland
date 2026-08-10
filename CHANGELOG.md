# Changelog

All notable project changes are recorded here.

## 0.8.2 — 2026-08-10

### Added

- Recursive ordinary-folder input scanning that distinguishes explicit files from folder roots while skipping hidden items, packages, and symbolic links.
- Validated safe relative paths for preserving nested output structure without `..`, absolute-path, symlink, or root-escape traversal.
- Structured image, native-video, fallback-video, and unsupported batch groups built through the existing planners and engine router.
- Compact Island group switching with independent image/video configuration and process, skip, and fail-closed counts before one Start action.
- Batch coordinator with bounded sequential group execution, monotonic aggregate progress, current/total file reporting, cancellation, collision-safe publication, and whole-batch rollback.
- Automated coverage for recursive discovery, path safety, grouping, no-op skips, fallback target exclusion, nested publishing, collisions, cancellation, execution failure, publication failure, rollback, and large input sets.

### Changed

- Folder and heterogeneous drops now preserve safe relative subdirectories under the persisted authorized output folder.
- All executable groups convert into hidden staging directories and publish only after the complete batch succeeds.
- Existing homogeneous explicit-file conversion keeps its established direct workflow.

## 0.8.1 — 2026-08-10

### Added

- Central, pure media conversion matrix shared by capability resolution, planners, engines, presets, and presentation state.
- HEIF and TIFF classification plus native ImageIO input support for HEIC/HEIF/JPEG/PNG/WebP/TIFF.
- Same-format JPEG and PNG processing for resizing, target-size compression, and metadata removal without source overwrite.
- Explicit white-background alpha compositing for JPEG output.
- Native M4V input conversion through the existing H.264/AAC MP4 workflow, including target-size and preset behavior.
- Deterministic WebP, TIFF, alpha-image, same-format, and M4V integration coverage.

### Changed

- JPEG and PNG are now the truthful output choices for every supported image batch; WebP remains input-only.
- Native MOV/MP4/M4V and fallback MKV/WebM ownership is derived from one fail-closed matrix.
- Folder batch jobs and CLI automation are specified as Tasks 008.2 and 008.3 and remain intentionally unimplemented.

## 0.8.0 — 2026-08-10

### Added

- Versioned, strictly validated bundled JSON catalog for built-in conversion presets.
- Windows Compatible, Web Friendly, Image for Web, and Under 100 MB definitions composed from existing conversion capabilities.
- Pure preset applicability and intent resolution with native/fallback target-size filtering.
- Compact image/video preset menu that does not increase the expanded Island height.
- Automated coverage for catalog parsing, invalid schema/data, applicability, intent mapping, selection state, fail-closed loading, and final plans.

### Changed

- Manual parameter changes now clear the selected preset indicator while preserving the applied editable values.
- MKV/WebM continue to exclude all target-size behavior, including the Under 100 MB preset.

## 0.7.0 — 2026-08-09

### Added

- FFmpeg 8.1.2 fallback conversion from MKV/WebM to high-compatibility H.264 VideoToolbox/AAC MP4.
- Universal arm64/x86_64 bundled executable built from verified official source with a reproducible script and complete LGPL provenance materials.
- Direct, shell-free process runner with machine-readable progress, bounded path-redacted diagnostics, cancellation, rollback, and output validation.
- WebM classification, fallback capability routing, command construction, parsers, process lifecycle, and real-media integration coverage.

### Changed

- The conversion router now resolves ImageIO first, AVFoundation video second, and FFmpeg fallback last.
- MKV/WebM show Source/1080p/720p resolution ceilings while hiding unsupported target-size controls.
- The menu-bar license action now identifies the bundled FFmpeg component and its license.

## 0.6.0 — 2026-08-09

### Added

- Per-file native video size limits for 100 MB, 50 MB, and custom 5 MB steps.
- Duration-aware bitrate budgeting with AAC reservation and a 95% file-length safety limit.
- Deterministic resolution planning across 2160p, 1080p, 720p, 540p, and 480p tiers.
- Automatic lower-resolution retry, target-size output validation, and retry-safe temporary-file cleanup.
- Automated coverage for planning, batch estimates, real MOV/MP4 limits, unreachable targets, automatic downgrade, and Island target selection.

### Changed

- Source, 1080p, and 720p remain user-selected resolution ceilings while an optional size target may choose a lower internal tier.
- Video progress remains monotonic across retry attempts and batches.
- Settings and Island copy now describe the implemented video target-size behavior.

## 0.5.0 — 2026-08-08

### Added

- Native AVFoundation MOV/MP4 conversion to high-compatibility H.264/AAC MP4.
- Source, 1080p, and 720p video resolution choices with no upscaling of smaller inputs.
- Real export-session progress, active cancellation, batch rollback, and collision-safe MP4 publishing.
- Post-export validation for playability, codecs, duration, audio presence, display orientation, and non-empty output.
- A conversion-engine router that preserves the existing ImageIO path while adding the native video engine.
- Deterministic real-media fixtures and automated video planning, routing, encoding, progress, cancellation, and rollback coverage.

### Changed

- The Island now presents type-specific video controls for supported MOV/MP4 selections.
- `DEVELOPMENT_SPEC.md` now defines Task 005 boundaries and records Milestone 5 completion.

## 0.4.0 — 2026-08-08

### Added

- Per-file image target presets for 5 MB, 1 MB, and 500 KB.
- Adaptive JPEG encoding with bounded quality search and dimension fallback.
- PNG dimension fallback, output-size enforcement, and post-encode decodability validation.
- Batch target-size estimates and a dedicated error when a target is unreachable.

### Changed

- Image controls show target-size choices and replace fixed JPEG quality with an adaptive indicator when a target is active.
- `DEVELOPMENT_SPEC.md` now defines Task 004 boundaries and records Milestone 4 completion.

## 0.3.1 — 2026-08-08

### Added

- Persistent app-scoped security-scoped bookmark for the default output folder.
- Static menu-bar entry with settings, output, project information, reporting, and quit actions.
- Extensible centered Settings window with General, Conversion, Appearance, and About sections.
- Quick Look source thumbnails and file-type-aware conversion capability routing.
- Runtime-derived physical-notch wing layout for conversion labels and real progress.

### Changed

- Image action selection is wider and thinner, with source information on the left and relevant parameters on the right.
- Video, audio, mixed, and unsupported selections now show a scoped read-only message instead of image options.
- Output folder selection occurs only on first use or after authorization becomes invalid.

## 0.3.0 — 2026-08-08

### Added

- Native ImageIO conversion for HEIC to JPEG, PNG to JPEG, and JPEG to PNG.
- Longest-edge resizing, three JPEG quality choices, and source-metadata removal.
- Batch progress, cancellation, failure rollback, structured errors, and success actions in the Island.
- Collision-safe output allocation that preserves source files and existing outputs.
- Explicit sandbox-safe output-directory selection and user-selected read/write entitlement.
- Automated coverage for conversion planning, real image encoding, output naming, cancellation, rollback, and Island workflow states.

### Changed

- Expanded Island content now accommodates image settings while compact notch geometry remains hardware-derived.
- `DEVELOPMENT_SPEC.md` now defines Task 003 boundaries and records Milestone 3 completion.

## 0.2.0 — 2026-08-08

### Added

- Pure file-type classification with exact HEIC, JPG/JPEG, PNG, WebP, MOV, MP4, and MKV results.
- Milestone 2 acceptance tests covering the complete required input-format matrix.
- Explicit Task 002 scope and implementation plan for shallow file inspection.

### Changed

- `InputFile` now exposes a normalized format label and uses type-first classification with a known-extension fallback.
- Broad media classification now checks audio before generic audiovisual content, preventing MP3 from being labeled as video.

## 0.1.0 — 2026-08-08

### Added

- Native macOS application and test targets.
- Non-activating top Island panel with compact and expanded layouts.
- Physical-notch compact alignment derived from `NSScreen` safe-area and auxiliary top-area geometry, with proportional side wings that preserve the physical notch height, plus a floating-pill fallback for other displays.
- Finder file URL drag-enter, drag-exit, and drop handling.
- Asynchronous shallow file inspection for display name, byte size, and `UTType`.
- Domain contracts for future conversion planning without a conversion implementation.
- Unit coverage for Island geometry, state-to-layout mapping, file classification, and inspection boundaries.
- Task 001 build, run, and smoke-test documentation.

### Changed

- Updated `DEVELOPMENT_SPEC.md` to version 0.2 with explicit Task 001 boundaries and the future compact-progress layout contract.

### Fixed

- Kept the expanded drop target stable when a Finder drag reaches the physical top screen edge.
- Reserved the physical notch as an occluded area so expanded icons and text render below it.
- Removed the physical-notch window shadow and added a proportional black lower lip for a future processing-light treatment.
