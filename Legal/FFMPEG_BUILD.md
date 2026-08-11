# File Island FFmpeg Build Record

File Island bundles deliberately small `ffmpeg` and `ffprobe` executables from FFmpeg 8.1.2. They run as separate local processes and are not linked into the Swift application. `ffmpeg` provides the audited conversion and segment/remux paths; its sibling `ffprobe` provides machine-readable local media metadata and keyframe inspection.

## Provenance

- Version: FFmpeg 8.1.2 “Hoare”
- Official source: `https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz`
- Source SHA-256: `464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c`
- Detached signature: `https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz.asc`
- Official release key: `https://ffmpeg.org/ffmpeg-devel.asc`
- Verified fingerprint: `FCF986EA15E6E293A5644F10B4322F04D67658D8`
- Repository `ffmpeg` SHA-256: `5669acc7f11a55a7942f88e1ad4f945a898b42c27833dd549635173984c4f954`
- Repository `ffprobe` SHA-256: `c18680b2c08dbc6e151e0162cc22b3df97628367df7389328d470ab45b65991a`
- Architectures: arm64 and x86_64
- Minimum macOS version: 15.0
- Compiler recorded by binary: Apple clang 17.0.0
- Rebuild toolchain: Xcode 26.1.1 (17B100), Apple clang 17.0.0 (clang-1700.4.4.1)

The exact source tarball, detached signature, public key, and LGPL text are committed under `Legal/`. The release signature was verified before compilation. No FFmpeg source changes are applied, so there is no project patch file.

## Reproduction

From the repository root on a Mac with Xcode command-line tools, `curl`, and GnuPG installed:

```sh
./Scripts/build-ffmpeg.sh
```

The script prefers the committed source archive, detached signature, and release key; if any of those three inputs is missing, it downloads the official copies. It checks the pinned source SHA-256, verifies the exact release-key fingerprint, and builds arm64 and x86_64 separately with Apple clang. It then merges and strips both programs, runs the schema-2 fixture capability audit against the temporary candidates, and only after that gate passes installs `Vendor/FFmpeg/ffmpeg` and `Vendor/FFmpeg/ffprobe`.

The hashes above identify the stripped repository artifacts before Xcode or the release script applies a nested code signature. Signing changes executable bytes, so a signed App/DMG must be identified by its own release checksum rather than by these repository-binary hashes.

The common configure selection is:

```text
--target-os=darwin
--disable-everything
--enable-ffmpeg --disable-ffplay --enable-ffprobe
--enable-avcodec --enable-avformat --enable-avfilter --enable-swscale --enable-swresample
--enable-protocol=file,pipe
--enable-demuxer=matroska,avi,mpegps,mpegts,mpegvideo,flv,mov,asf,mp3,wav,aiff,aac,flac,ogg,ac3
--enable-muxer=mov,mp4,ipod,wav,flac,aiff,segment
--enable-decoder=h264,hevc,mpeg4,mpeg1video,mpeg2video,flv,h263,wmv1,wmv2,wmv3,vc1,vp8,vp9,av1,opus,vorbis,aac,mp3,ac3,eac3,flac,alac,wmav1,wmav2,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_s32be,pcm_f32le,pcm_f32be
--enable-encoder=h264_videotoolbox,aac,flac,pcm_s16le,pcm_s16be
--enable-parser=h264,hevc,mpeg4video,mpegvideo,vp8,vp9,av1,opus,vorbis,aac,mpegaudio,ac3,vc1
--enable-filter=scale,format,aresample
--enable-bsf=aac_adtstoasc,extract_extradata,h264_mp4toannexb,hevc_mp4toannexb,vp9_superframe
--enable-videotoolbox --enable-audiotoolbox
--disable-network --disable-autodetect --disable-doc --disable-debug
--enable-small --enable-hardcoded-tables --disable-avdevice --disable-symver
--disable-securetransport --disable-iconv --disable-zlib --disable-bzlib --disable-lzma
--disable-metal --disable-coreimage --disable-appkit --disable-avfoundation --disable-sdl2 --disable-xlib
--cc=clang --prefix=/FileIsland/FFmpeg
```

Each architecture additionally uses `--arch`, `-arch`, and `-mmacosx-version-min=15.0`; x86_64 uses `--enable-cross-compile --disable-x86asm`. The script never enables GPL, nonfree, or an external codec library.

## Audit commands

```sh
shasum -a 256 Legal/source/ffmpeg-8.1.2.tar.xz \
  Vendor/FFmpeg/ffmpeg Vendor/FFmpeg/ffprobe
lipo Vendor/FFmpeg/ffmpeg -verify_arch arm64 x86_64
lipo Vendor/FFmpeg/ffprobe -verify_arch arm64 x86_64
otool -L Vendor/FFmpeg/ffmpeg
otool -L Vendor/FFmpeg/ffprobe
Vendor/FFmpeg/ffmpeg -version
Vendor/FFmpeg/ffprobe -version
Vendor/FFmpeg/ffmpeg -encoders
Vendor/FFmpeg/ffmpeg -decoders
Scripts/audit-ffmpeg-split-capabilities.sh \
  Vendor/FFmpeg/ffmpeg \
  FileIslandTests/Fixtures/task016-keyframes.mp4
```

Expected dynamic dependencies for both programs are Apple system libraries/frameworks only. Expected encoders are `h264_videotoolbox` and FFmpeg's native `aac`; the network protocol layer remains disabled and only the local `file` and `pipe` protocols are enabled. The generic local `segment` muxer and `ffprobe` are part of the same unmodified LGPL-2.1-or-later FFmpeg source; no GPL, nonfree, or external codec component is enabled.

## Split-for-sharing capability audit

Task 016A-0 added a reproducible capability inventory. Task 016B strengthened it to schema 2 so readiness also requires a real H.264/AAC fixture, matching `ffmpeg`/`ffprobe` versions, a valid machine-readable keyframe table, and a real multi-file MP4 stream-copy segment smoke test. From the repository root, run:

```sh
Scripts/audit-ffmpeg-split-capabilities.sh \
  Vendor/FFmpeg/ffmpeg \
  FileIslandTests/Fixtures/task016-keyframes.mp4
```

The audit invokes both executables directly—never through a generated shell command string—and inspects only the `ffprobe` sibling beside the supplied `ffmpeg`; Homebrew, `PATH`, and other external installations cannot satisfy the gate. It validates JSON with macOS `plutil`, derives ordered keyframe packet timestamps, uses those timestamps with the generic segment muxer, and checks every generated segment for non-empty H.264/AAC content and a key first video packet. A complete audit exits with status 0 even when a capability result is false; packaging and CI separately require the literal line `fast_split_ready=true`.

The 2026-08-11 schema-2 audit of repository `ffmpeg` SHA-256 `5669acc7f11a55a7942f88e1ad4f945a898b42c27833dd549635173984c4f954` and `ffprobe` SHA-256 `c18680b2c08dbc6e151e0162cc22b3df97628367df7389328d470ab45b65991a` recorded:

| Capability | Result |
| --- | --- |
| Audit schema | `2` |
| FFmpeg / ffprobe version | `8.1.2` / `8.1.2` |
| Versions match | `true` |
| MP4 muxer | `true` |
| MOV muxer | `true` |
| Generic segment muxer | `true` |
| Bundled sibling `ffprobe` | `true` |
| Machine-readable keyframe probe | `true` |
| Fixture keyframe count | `4` |
| Fixture segment stream-copy smoke | `true` |
| Fast split execution ready | `true` |

This capability result proves the bundled-tool supply-chain gate only. It does not by itself prove the complete Task 016B runtime: the structured command builder, production probe, typed one-to-many publication, validators, recursive re-splitting, cancellation, rollback, GUI/CLI routing, and cross-architecture behavior retain their own tests and release gates.
