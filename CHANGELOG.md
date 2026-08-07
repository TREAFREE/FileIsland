# Changelog

All notable project changes are recorded here.

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
