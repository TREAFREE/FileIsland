# Changelog

All notable project changes are recorded here.

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
