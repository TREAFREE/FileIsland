# File Island 0.3 format matrix

[简体中文](FORMAT_MATRIX.zh-CN.md)

This matrix describes the v0.3.0 release capability.

| Media | Verified inputs | Verified outputs | Engine / limits |
|---|---|---|---|
| Images | HEIC, HEIF, JPEG/JPG, PNG, WebP, TIFF, GIF, BMP, AVIF | JPEG, PNG | ImageIO; first frame of animated input; WebP output is not claimed |
| Native video | MOV, MP4, M4V | H.264/AAC MP4 | AVFoundation; Source/1080p/720p and optional per-file size target |
| Fallback video | MKV, WebM, AVI, MPEG/MPG, TS/MTS/M2TS, FLV, 3GP, WMV/ASF | H.264/AAC MP4 | Bundled LGPL FFmpeg 8.1.2 + VideoToolbox; no exact-byte target |
| Audio | MP3, WAV, AIFF, M4A, AAC, FLAC, OGG/Vorbis, Opus, AC3 | M4A/AAC, WAV/PCM, FLAC, AIFF/PCM | Bundled LGPL FFmpeg 8.1.2; compact/balanced/high applies to AAC; MP3 output is not claimed |
| Fast split for sharing | MP4 or MOV containing H.264 video and optional AAC audio | MP4 or MOV segments retaining the source H.264 and optional AAC streams | Audited bundled FFmpeg + ffprobe; Custom size and/or duration limits with MB/GB and seconds/minutes/hours UI; keyframe-aligned stream copy with no re-encoding; precise mode and platform rules are not claimed |

Every listed family has a committed real fixture and decoded-output integration coverage. Damaged files, unsupported codecs inside a listed container, packages, symbolic links, and unknown formats fail closed. File Island does not upload media.

Fast splitting preserves encoded media quality but can cut only at safe keyframes. If the available keyframes cannot satisfy either selected limit, File Island fails closed instead of exceeding the limit or silently re-encoding. The App interprets `1 MB` as exactly `1,000,000 bytes` and `1 GB` as `1,000 MB`; changing a display unit preserves the canonical constraint. The CLI accepts exact bytes through `--max-bytes`. At least one size or duration limit is required.
