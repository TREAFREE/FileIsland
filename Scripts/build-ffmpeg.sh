#!/bin/bash

set -euo pipefail

FFMPEG_VERSION="8.1.2"
FFMPEG_ARCHIVE="ffmpeg-${FFMPEG_VERSION}.tar.xz"
FFMPEG_SOURCE_URL="https://ffmpeg.org/releases/${FFMPEG_ARCHIVE}"
FFMPEG_SIGNATURE_URL="${FFMPEG_SOURCE_URL}.asc"
FFMPEG_KEY_URL="https://ffmpeg.org/ffmpeg-devel.asc"
FFMPEG_SHA256="464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c"
FFMPEG_SIGNING_FINGERPRINT="FCF986EA15E6E293A5644F10B4322F04D67658D8"
MACOS_DEPLOYMENT_TARGET="15.0"

SCRIPT_DIRECTORY="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIRECTORY="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
BUILD_DIRECTORY="$(mktemp -d /private/tmp/fileisland-ffmpeg-build.XXXXXX)"
trap 'rm -rf "${BUILD_DIRECTORY}"' EXIT
DOWNLOAD_DIRECTORY="${BUILD_DIRECTORY}/downloads"
SOURCE_DIRECTORY="${BUILD_DIRECTORY}/source"
OUTPUT_DIRECTORY="${PROJECT_DIRECTORY}/Vendor/FFmpeg"
LEGAL_DIRECTORY="${PROJECT_DIRECTORY}/Legal"

mkdir -p "${DOWNLOAD_DIRECTORY}" "${SOURCE_DIRECTORY}" "${OUTPUT_DIRECTORY}"
mkdir -p "${LEGAL_DIRECTORY}/licenses" "${LEGAL_DIRECTORY}/signatures" "${LEGAL_DIRECTORY}/source"

LOCAL_ARCHIVE="${LEGAL_DIRECTORY}/source/${FFMPEG_ARCHIVE}"
LOCAL_SIGNATURE="${LEGAL_DIRECTORY}/signatures/${FFMPEG_ARCHIVE}.asc"
LOCAL_KEY="${LEGAL_DIRECTORY}/signatures/ffmpeg-devel.asc"
if [[ -f "${LOCAL_ARCHIVE}" && -f "${LOCAL_SIGNATURE}" && -f "${LOCAL_KEY}" ]]; then
    cp "${LOCAL_ARCHIVE}" "${DOWNLOAD_DIRECTORY}/${FFMPEG_ARCHIVE}"
    cp "${LOCAL_SIGNATURE}" "${DOWNLOAD_DIRECTORY}/${FFMPEG_ARCHIVE}.asc"
    cp "${LOCAL_KEY}" "${DOWNLOAD_DIRECTORY}/ffmpeg-devel.asc"
else
    curl -L --fail --silent --show-error "${FFMPEG_SOURCE_URL}" -o "${DOWNLOAD_DIRECTORY}/${FFMPEG_ARCHIVE}"
    curl -L --fail --silent --show-error "${FFMPEG_SIGNATURE_URL}" -o "${DOWNLOAD_DIRECTORY}/${FFMPEG_ARCHIVE}.asc"
    curl -L --fail --silent --show-error "${FFMPEG_KEY_URL}" -o "${DOWNLOAD_DIRECTORY}/ffmpeg-devel.asc"
fi

ACTUAL_SHA256="$(shasum -a 256 "${DOWNLOAD_DIRECTORY}/${FFMPEG_ARCHIVE}" | awk '{print $1}')"
if [[ "${ACTUAL_SHA256}" != "${FFMPEG_SHA256}" ]]; then
    echo "FFmpeg source SHA-256 mismatch" >&2
    exit 1
fi

GPG_DIRECTORY="${BUILD_DIRECTORY}/gnupg"
mkdir -m 700 "${GPG_DIRECTORY}"
GNUPGHOME="${GPG_DIRECTORY}" gpg --batch --import "${DOWNLOAD_DIRECTORY}/ffmpeg-devel.asc" >/dev/null 2>&1
VERIFY_STATUS="$(GNUPGHOME="${GPG_DIRECTORY}" gpg --batch --status-fd 1 \
    --verify "${DOWNLOAD_DIRECTORY}/${FFMPEG_ARCHIVE}.asc" \
    "${DOWNLOAD_DIRECTORY}/${FFMPEG_ARCHIVE}" 2>/dev/null)"
if ! grep -q "VALIDSIG ${FFMPEG_SIGNING_FINGERPRINT}" <<<"${VERIFY_STATUS}"; then
    echo "FFmpeg source signature verification failed" >&2
    exit 1
fi

tar -xf "${DOWNLOAD_DIRECTORY}/${FFMPEG_ARCHIVE}" -C "${SOURCE_DIRECTORY}"
FFMPEG_SOURCE_DIRECTORY="${SOURCE_DIRECTORY}/ffmpeg-${FFMPEG_VERSION}"

COMMON_OPTIONS=(
    "--target-os=darwin"
    "--disable-everything"
    "--enable-ffmpeg"
    "--disable-ffplay"
    "--enable-ffprobe"
    "--enable-avcodec"
    "--enable-avformat"
    "--enable-avfilter"
    "--enable-swscale"
    "--enable-swresample"
    "--enable-protocol=file,pipe"
    "--enable-demuxer=matroska,avi,mpegps,mpegts,mpegvideo,flv,mov,asf,mp3,wav,aiff,aac,flac,ogg,ac3"
    "--enable-muxer=mov,mp4,ipod,wav,flac,aiff,segment"
    "--enable-decoder=h264,hevc,mpeg4,mpeg1video,mpeg2video,flv,h263,wmv1,wmv2,wmv3,vc1,vp8,vp9,av1,opus,vorbis,aac,mp3,ac3,eac3,flac,alac,wmav1,wmav2,pcm_s16le,pcm_s16be,pcm_s24le,pcm_s24be,pcm_s32le,pcm_s32be,pcm_f32le,pcm_f32be"
    "--enable-encoder=h264_videotoolbox,aac,flac,pcm_s16le,pcm_s16be"
    "--enable-parser=h264,hevc,mpeg4video,mpegvideo,vp8,vp9,av1,opus,vorbis,aac,mpegaudio,ac3,vc1"
    "--enable-filter=scale,format,aresample"
    "--enable-bsf=aac_adtstoasc,extract_extradata,h264_mp4toannexb,hevc_mp4toannexb,vp9_superframe"
    "--enable-videotoolbox"
    "--enable-audiotoolbox"
    "--disable-network"
    "--disable-autodetect"
    "--disable-doc"
    "--disable-debug"
    "--enable-small"
    "--enable-hardcoded-tables"
    "--disable-avdevice"
    "--disable-symver"
    "--disable-securetransport"
    "--disable-iconv"
    "--disable-zlib"
    "--disable-bzlib"
    "--disable-lzma"
    "--disable-metal"
    "--disable-coreimage"
    "--disable-appkit"
    "--disable-avfoundation"
    "--disable-sdl2"
    "--disable-xlib"
    "--cc=clang"
)

build_architecture() {
    local architecture="$1"
    local build_path="${BUILD_DIRECTORY}/build-${architecture}"
    local architecture_options=(
        "--prefix=/FileIsland/FFmpeg"
        "--arch=${architecture}"
        "--extra-cflags=-arch ${architecture} -mmacosx-version-min=${MACOS_DEPLOYMENT_TARGET}"
        "--extra-ldflags=-arch ${architecture} -mmacosx-version-min=${MACOS_DEPLOYMENT_TARGET}"
    )
    if [[ "${architecture}" == "x86_64" ]]; then
        architecture_options+=("--enable-cross-compile" "--disable-x86asm")
    fi

    mkdir -p "${build_path}"
    (
        cd "${build_path}"
        "${FFMPEG_SOURCE_DIRECTORY}/configure" "${COMMON_OPTIONS[@]}" "${architecture_options[@]}"
        make -j8
    )
}

build_architecture arm64
build_architecture x86_64

CANDIDATE_DIRECTORY="${BUILD_DIRECTORY}/candidate"
mkdir -p "${CANDIDATE_DIRECTORY}"

for executable_name in ffmpeg ffprobe; do
    lipo -create \
        "${BUILD_DIRECTORY}/build-arm64/${executable_name}" \
        "${BUILD_DIRECTORY}/build-x86_64/${executable_name}" \
        -output "${CANDIDATE_DIRECTORY}/${executable_name}"
    strip -x "${CANDIDATE_DIRECTORY}/${executable_name}"
    chmod 755 "${CANDIDATE_DIRECTORY}/${executable_name}"
    /usr/bin/xattr -c "${CANDIDATE_DIRECTORY}/${executable_name}"
done

SPLIT_FIXTURE="${PROJECT_DIRECTORY}/FileIslandTests/Fixtures/task016-keyframes.mp4"
AUDIT_OUTPUT="$(
    "${SCRIPT_DIRECTORY}/audit-ffmpeg-split-capabilities.sh" \
        "${CANDIDATE_DIRECTORY}/ffmpeg" \
        "${SPLIT_FIXTURE}"
)"
printf '%s\n' "${AUDIT_OUTPUT}"
if ! grep -q '^fast_split_ready=true$' <<<"${AUDIT_OUTPUT}"; then
    echo "Candidate FFmpeg split capability audit failed" >&2
    exit 1
fi

for executable_name in ffmpeg ffprobe; do
    install -m 755 \
        "${CANDIDATE_DIRECTORY}/${executable_name}" \
        "${OUTPUT_DIRECTORY}/.${executable_name}.new"
done
mv "${OUTPUT_DIRECTORY}/.ffprobe.new" "${OUTPUT_DIRECTORY}/ffprobe"
mv "${OUTPUT_DIRECTORY}/.ffmpeg.new" "${OUTPUT_DIRECTORY}/ffmpeg"

cp "${DOWNLOAD_DIRECTORY}/${FFMPEG_ARCHIVE}" "${LEGAL_DIRECTORY}/source/${FFMPEG_ARCHIVE}"
cp "${DOWNLOAD_DIRECTORY}/${FFMPEG_ARCHIVE}.asc" "${LEGAL_DIRECTORY}/signatures/${FFMPEG_ARCHIVE}.asc"
cp "${DOWNLOAD_DIRECTORY}/ffmpeg-devel.asc" "${LEGAL_DIRECTORY}/signatures/ffmpeg-devel.asc"
cp "${FFMPEG_SOURCE_DIRECTORY}/COPYING.LGPLv2.1" "${LEGAL_DIRECTORY}/licenses/COPYING.LGPLv2.1"
/usr/bin/xattr -c "${OUTPUT_DIRECTORY}/ffmpeg"
/usr/bin/xattr -c "${OUTPUT_DIRECTORY}/ffprobe"
/usr/bin/xattr -c "${LEGAL_DIRECTORY}/source/${FFMPEG_ARCHIVE}"
/usr/bin/xattr -c "${LEGAL_DIRECTORY}/signatures/${FFMPEG_ARCHIVE}.asc"
/usr/bin/xattr -c "${LEGAL_DIRECTORY}/signatures/ffmpeg-devel.asc"
/usr/bin/xattr -c "${LEGAL_DIRECTORY}/licenses/COPYING.LGPLv2.1"

echo "Built ${OUTPUT_DIRECTORY}/ffmpeg"
lipo -archs "${OUTPUT_DIRECTORY}/ffmpeg"
"${OUTPUT_DIRECTORY}/ffmpeg" -version | sed -n '1,4p'
echo "Built ${OUTPUT_DIRECTORY}/ffprobe"
lipo -archs "${OUTPUT_DIRECTORY}/ffprobe"
"${OUTPUT_DIRECTORY}/ffprobe" -version | sed -n '1,4p'
