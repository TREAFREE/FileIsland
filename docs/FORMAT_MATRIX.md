# File Island 0.2 format matrix

[简体中文](FORMAT_MATRIX.zh-CN.md)

| Media | Verified inputs | Verified outputs | Engine / limits |
|---|---|---|---|
| Images | HEIC, HEIF, JPEG/JPG, PNG, WebP, TIFF, GIF, BMP, AVIF | JPEG, PNG | ImageIO; first frame of animated input; WebP output is not claimed |
| Native video | MOV, MP4, M4V | H.264/AAC MP4 | AVFoundation; Source/1080p/720p and optional per-file size target |
| Fallback video | MKV, WebM, AVI, MPEG/MPG, TS/MTS/M2TS, FLV, 3GP, WMV/ASF | H.264/AAC MP4 | Bundled LGPL FFmpeg 8.1.2 + VideoToolbox; no exact-byte target |
| Audio | MP3, WAV, AIFF, M4A, AAC, FLAC, OGG/Vorbis, Opus, AC3 | M4A/AAC, WAV/PCM, FLAC, AIFF/PCM | Bundled LGPL FFmpeg 8.1.2; compact/balanced/high applies to AAC; MP3 output is not claimed |

Every listed family has a committed real fixture and decoded-output integration coverage. Damaged files, unsupported codecs inside a listed container, packages, symbolic links, and unknown formats fail closed. File Island does not upload media.
