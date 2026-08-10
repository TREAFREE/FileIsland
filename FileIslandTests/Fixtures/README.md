# Task 007 Media Fixtures

These deterministic one-second fixtures contain synthetic color bars and sine-wave audio only. They contain no user media.

- `task007-landscape.mkv`: 320×180 H.264/AAC Matroska.
- `task007-portrait.webm`: 180×320 VP9/Opus WebM.
- `task014-sample.{avi,mpeg,mts,flv,3gp,wmv}`: small real container/codec fixtures (MTS exercises MPEG-TS).
- `task014-sample.{gif,bmp,avif}`: small still-image decoder fixtures.
- `Audio/tone.*`: short audio fixtures covering every v0.2 input format.

They were generated for integration testing with FFmpeg's `testsrc2` and `sine` lavfi sources. The fixture encoder is not shipped with File Island and does not affect the license configuration of the bundled FFmpeg executable.
