# File Island FFmpeg Build Record

File Island bundles a deliberately small FFmpeg 8.1.2 executable for local MKV/WebM fallback conversion. It is launched as a separate process and is not linked into the Swift application.

## Provenance

- Version: FFmpeg 8.1.2 “Hoare”
- Official source: `https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz`
- Source SHA-256: `464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c`
- Detached signature: `https://ffmpeg.org/releases/ffmpeg-8.1.2.tar.xz.asc`
- Official release key: `https://ffmpeg.org/ffmpeg-devel.asc`
- Verified fingerprint: `FCF986EA15E6E293A5644F10B4322F04D67658D8`
- Bundled binary SHA-256: `1740a8f65d505dea63fdece2c4c9e78c6012f61423481f5af643ddaa404fc513`
- Architectures: arm64 and x86_64
- Minimum macOS version: 15.0
- Compiler recorded by binary: Apple clang 17.0.0

The exact source tarball, detached signature, public key, and LGPL text are committed under `Legal/`. The release signature was verified before compilation. No FFmpeg source changes are applied, so there is no project patch file.

## Reproduction

From the repository root on a Mac with Xcode command-line tools, `curl`, and GnuPG installed:

```sh
./Scripts/build-ffmpeg.sh
```

The script downloads the official source again, checks the pinned SHA-256, verifies the signature fingerprint, builds arm64 and x86_64 separately with Apple clang, merges them with `lipo`, strips local symbols, and writes `Vendor/FFmpeg/ffmpeg`.

The common configure selection is:

```text
--target-os=darwin
--disable-everything
--enable-ffmpeg --disable-ffplay --disable-ffprobe
--enable-avcodec --enable-avformat --enable-avfilter --enable-swscale --enable-swresample
--enable-protocol=file,pipe
--enable-demuxer=matroska --enable-muxer=mov,mp4
--enable-decoder=h264,hevc,mpeg4,vp8,vp9,av1,opus,vorbis,aac,mp3,ac3,eac3,flac,alac,pcm_s16le,pcm_s24le,pcm_s32le
--enable-encoder=h264_videotoolbox,aac
--enable-parser=h264,hevc,mpeg4video,vp8,vp9,av1,opus,vorbis,aac,mpegaudio,ac3
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
shasum -a 256 Legal/source/ffmpeg-8.1.2.tar.xz Vendor/FFmpeg/ffmpeg
lipo -archs Vendor/FFmpeg/ffmpeg
otool -L Vendor/FFmpeg/ffmpeg
Vendor/FFmpeg/ffmpeg -version
Vendor/FFmpeg/ffmpeg -encoders
Vendor/FFmpeg/ffmpeg -decoders
```

Expected dynamic dependencies are Apple system libraries/frameworks only. Expected encoders are `h264_videotoolbox` and FFmpeg's native `aac`; the network protocol layer is disabled.
