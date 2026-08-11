# Task 007 Media Fixtures

These deterministic one-second fixtures contain synthetic color bars and sine-wave audio only. They contain no user media.

- `task007-landscape.mkv`: 320×180 H.264/AAC Matroska.
- `task007-portrait.webm`: 180×320 VP9/Opus WebM.
- `task016-keyframes.mp4`: four seconds of the Task 007 H.264/AAC source,
  repeated by `Scripts/generate-task016-fixture.sh`; it contains independently
  decodable video packets near 0, 1, 2, and 3 seconds for probe and segment
  smoke tests.
- `task014-sample.{avi,mpeg,mts,flv,3gp,wmv}`: small real container/codec fixtures (MTS exercises MPEG-TS).
- `task014-sample.{gif,bmp,avif}`: small still-image decoder fixtures.
- `Audio/tone.*`: short audio fixtures covering every v0.2 input format.

They were generated for integration testing with FFmpeg's `testsrc2` and `sine` lavfi sources. The fixture encoder is not shipped with File Island and does not affect the license configuration of the bundled FFmpeg executable.

Large, manually downloaded acceptance-test media is intentionally kept outside this repository. Do not replace these deterministic fixtures with private samples or copy manual test data into Git.
