#!/bin/zsh

set -euo pipefail

REPOSITORY_ROOT="${0:A:h:h}"
VERSION="${FILEISLAND_RELEASE_VERSION:-0.1.0}"
BUILD_NUMBER="${FILEISLAND_BUILD_NUMBER:-1}"
RELEASE_ROOT="${REPOSITORY_ROOT}/.build/release"
DMG_PATH="${RELEASE_ROOT}/FileIsland-${VERSION}-unsigned.dmg"
DMG_CHECKSUM_PATH="${DMG_PATH}.sha256"
SOURCE_NAME="ffmpeg-8.1.2.tar.xz"
SOURCE_PATH="${REPOSITORY_ROOT}/Legal/source/${SOURCE_NAME}"
RELEASE_SOURCE_PATH="${RELEASE_ROOT}/${SOURCE_NAME}"
SOURCE_CHECKSUM_PATH="${RELEASE_SOURCE_PATH}.sha256"
EXPECTED_SOURCE_SHA256="464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c"
TEMP_ROOT="$(mktemp -d /private/tmp/FileIslandRelease.XXXXXX)"
DERIVED_DATA_PATH="${TEMP_ROOT}/DerivedData"
STAGE_PATH="${TEMP_ROOT}/DMG"

cleanup() {
  /bin/rm -rf "${TEMP_ROOT}"
}
trap cleanup EXIT INT TERM

fail() {
  print -u2 -- "error: $1"
  exit 1
}

[[ "${VERSION}" == "0.1.0" ]] || fail "this release script currently supports version 0.1.0 only"
[[ "${BUILD_NUMBER}" == "1" ]] || fail "this release script currently supports build 1 only"
[[ -f "${REPOSITORY_ROOT}/LICENSE" ]] || fail "LICENSE is required before public packaging"
[[ -f "${REPOSITORY_ROOT}/Legal/THIRD_PARTY_NOTICES.md" ]] || fail "third-party notices are missing"
[[ -f "${REPOSITORY_ROOT}/Legal/licenses/COPYING.LGPLv2.1" ]] || fail "LGPL text is missing"
[[ -f "${SOURCE_PATH}" ]] || fail "FFmpeg corresponding source is missing"
[[ -f "${REPOSITORY_ROOT}/docs/releases/v${VERSION}.md" ]] || fail "release notes are missing"

DIRTY_STATUS="$(git -C "${REPOSITORY_ROOT}" status --porcelain --untracked-files=all -- . ':(exclude)测试用文件')"
[[ -z "${DIRTY_STATUS}" ]] || fail "tracked release files must be committed before packaging:\n${DIRTY_STATUS}"

PROJECT_VERSION="$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);/\1/p' "${REPOSITORY_ROOT}/FileIsland.xcodeproj/project.pbxproj" | sort -u)"
PROJECT_BUILD="$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION = \([^;]*\);/\1/p' "${REPOSITORY_ROOT}/FileIsland.xcodeproj/project.pbxproj" | sort -u)"
[[ "${PROJECT_VERSION}" == "${VERSION}" ]] || fail "Xcode marketing version ${PROJECT_VERSION} does not match ${VERSION}"
[[ "${PROJECT_BUILD}" == "${BUILD_NUMBER}" ]] || fail "Xcode build number ${PROJECT_BUILD} does not match ${BUILD_NUMBER}"

ACTUAL_SOURCE_SHA256="$(shasum -a 256 "${SOURCE_PATH}" | awk '{print $1}')"
[[ "${ACTUAL_SOURCE_SHA256}" == "${EXPECTED_SOURCE_SHA256}" ]] || fail "FFmpeg source checksum mismatch"

xcodebuild \
  -project "${REPOSITORY_ROOT}/FileIsland.xcodeproj" \
  -scheme FileIsland \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/FileIsland.app"
MAIN_EXECUTABLE="${APP_PATH}/Contents/MacOS/FileIsland"
FFMPEG_EXECUTABLE="${APP_PATH}/Contents/MacOS/ffmpeg"

[[ -d "${APP_PATH}" ]] || fail "Release app was not produced"
lipo "${MAIN_EXECUTABLE}" -verify_arch arm64 x86_64
lipo "${FFMPEG_EXECUTABLE}" -verify_arch arm64 x86_64
[[ -f "${APP_PATH}/Contents/Resources/Assets.car" ]] || fail "compiled asset catalog is missing"
[[ -f "${APP_PATH}/Contents/Resources/AppIcon.icns" ]] || fail "AppIcon is missing"
[[ -f "${APP_PATH}/Contents/Resources/built-in-presets.json" ]] || fail "preset catalog is missing"

FFMPEG_CONFIGURATION="$("${FFMPEG_EXECUTABLE}" -version 2>&1)"
[[ "${FFMPEG_CONFIGURATION}" != *"--enable-gpl"* ]] || fail "bundled FFmpeg unexpectedly enables GPL components"
[[ "${FFMPEG_CONFIGURATION}" != *"--enable-nonfree"* ]] || fail "bundled FFmpeg unexpectedly enables nonfree components"

codesign --force --options runtime --sign - "${FFMPEG_EXECUTABLE}"
codesign \
  --force \
  --options runtime \
  --entitlements "${REPOSITORY_ROOT}/FileIsland/FileIsland.entitlements" \
  --sign - \
  "${APP_PATH}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"

mkdir -p "${STAGE_PATH}/Open Source Notices"
ditto "${APP_PATH}" "${STAGE_PATH}/File Island.app"
ln -s /Applications "${STAGE_PATH}/Applications"
ditto "${REPOSITORY_ROOT}/LICENSE" "${STAGE_PATH}/LICENSE"
ditto "${REPOSITORY_ROOT}/docs/releases/v${VERSION}.md" "${STAGE_PATH}/README.md"
ditto "${REPOSITORY_ROOT}/Legal/THIRD_PARTY_NOTICES.md" "${STAGE_PATH}/Open Source Notices/THIRD_PARTY_NOTICES.md"
ditto "${REPOSITORY_ROOT}/Legal/licenses/COPYING.LGPLv2.1" "${STAGE_PATH}/Open Source Notices/COPYING.LGPLv2.1"
ditto "${REPOSITORY_ROOT}/Legal/FFMPEG_BUILD.md" "${STAGE_PATH}/Open Source Notices/FFMPEG_BUILD.md"

mkdir -p "${RELEASE_ROOT}"
[[ ! -e "${DMG_PATH}" ]] || fail "release artifact already exists: ${DMG_PATH}"
[[ ! -e "${DMG_CHECKSUM_PATH}" ]] || fail "release checksum already exists: ${DMG_CHECKSUM_PATH}"
[[ ! -e "${RELEASE_SOURCE_PATH}" ]] || fail "release source already exists: ${RELEASE_SOURCE_PATH}"
[[ ! -e "${SOURCE_CHECKSUM_PATH}" ]] || fail "source checksum already exists: ${SOURCE_CHECKSUM_PATH}"

diskutil image create from --format UDZO "${STAGE_PATH}" "${DMG_PATH}"
ditto "${SOURCE_PATH}" "${RELEASE_SOURCE_PATH}"

(
  cd "${RELEASE_ROOT}"
  shasum -a 256 "${DMG_PATH:t}" > "${DMG_CHECKSUM_PATH:t}"
  shasum -a 256 "${RELEASE_SOURCE_PATH:t}" > "${SOURCE_CHECKSUM_PATH:t}"
)

diskutil image info "${DMG_PATH}" >/dev/null
print -- "Release artifacts verified at ${RELEASE_ROOT}"
print -- "Upload all four files from that directory to GitHub Release v${VERSION}."
