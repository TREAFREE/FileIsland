#!/bin/zsh

set -euo pipefail

REPOSITORY_ROOT="${0:A:h:h}"
VERSION="${FILEISLAND_RELEASE_VERSION:-0.3.3}"
BUILD_NUMBER="${FILEISLAND_BUILD_NUMBER:-6}"
RELEASE_ROOT="${FILEISLAND_RELEASE_ROOT:-${REPOSITORY_ROOT}/.build/release/v${VERSION}}"
SOURCE_NAME="ffmpeg-8.1.2.tar.xz"
SOURCE_PATH="${REPOSITORY_ROOT}/Legal/source/${SOURCE_NAME}"
FFMPEG_MANIFEST_PATH="${REPOSITORY_ROOT}/Vendor/FFmpeg/SOURCE.json"
SPLIT_AUDIT_PATH="${REPOSITORY_ROOT}/Scripts/audit-ffmpeg-split-capabilities.sh"
SPLIT_FIXTURE_PATH="${REPOSITORY_ROOT}/FileIslandTests/Fixtures/task016-keyframes.mp4"
EXPECTED_SOURCE_SHA256="464beb5e7bf0c311e68b45ae2f04e9cc2af88851abb4082231742a74d97b524c"
TEMP_ROOT="$(mktemp -d /private/tmp/FileIslandRelease.XXXXXX)"
ARTIFACT_ROOT="${TEMP_ROOT}/ReleaseArtifacts"
DMG_PATH="${ARTIFACT_ROOT}/FileIsland-${VERSION}-unsigned.dmg"
DMG_CHECKSUM_PATH="${DMG_PATH}.sha256"
RELEASE_SOURCE_PATH="${ARTIFACT_ROOT}/${SOURCE_NAME}"
SOURCE_CHECKSUM_PATH="${RELEASE_SOURCE_PATH}.sha256"
FINAL_DMG_PATH="${RELEASE_ROOT}/${DMG_PATH:t}"
FINAL_DMG_CHECKSUM_PATH="${RELEASE_ROOT}/${DMG_CHECKSUM_PATH:t}"
FINAL_SOURCE_PATH="${RELEASE_ROOT}/${RELEASE_SOURCE_PATH:t}"
FINAL_SOURCE_CHECKSUM_PATH="${RELEASE_ROOT}/${SOURCE_CHECKSUM_PATH:t}"
DERIVED_DATA_PATH="${TEMP_ROOT}/DerivedData"
STAGE_PATH="${TEMP_ROOT}/DMG"
WRITABLE_DMG_PATH="${TEMP_ROOT}/FileIsland-writable.dmg"
MOUNT_POINT="${TEMP_ROOT}/MountedDMG"
VOLUME_NAME="File Island ${VERSION}"

cleanup() {
  hdiutil detach "${MOUNT_POINT}" -quiet 2>/dev/null || true
  /bin/rm -rf "${TEMP_ROOT}"
}
trap cleanup EXIT INT TERM

fail() {
  print -u2 -- "error: $1"
  exit 1
}

verify_system_dependencies() {
  local executable_path="$1"
  local dependency_listing
  local unexpected_dependencies

  if ! dependency_listing="$(otool -L "${executable_path}")"; then
    fail "otool could not inspect ${executable_path:t}"
  fi

  unexpected_dependencies="$(
    print -r -- "${dependency_listing}" |
      awk '
        /^[[:space:]]/ {
          dependency = $1
          if (dependency !~ /^\/usr\/lib\// && dependency !~ /^\/System\/Library\/Frameworks\//) {
            print dependency
          }
        }
      '
  )"
  [[ -z "${unexpected_dependencies}" ]] ||
    fail "${executable_path:t} has non-system dynamic dependencies:\n${unexpected_dependencies}"
}

require_audit_field() {
  local audit_output="$1"
  local expected_line="$2"
  grep -Fqx -- "${expected_line}" <<<"${audit_output}" ||
    fail "FFmpeg split capability audit is missing '${expected_line}'"
}

[[ "${VERSION}" =~ '^[0-9]+\.[0-9]+\.[0-9]+$' ]] || fail "release version must use semantic versioning"
[[ "${BUILD_NUMBER}" =~ '^[1-9][0-9]*$' ]] || fail "build number must be a positive integer"
[[ -f "${REPOSITORY_ROOT}/LICENSE" ]] || fail "LICENSE is required before public packaging"
[[ -f "${REPOSITORY_ROOT}/Legal/THIRD_PARTY_NOTICES.md" ]] || fail "third-party notices are missing"
[[ -f "${REPOSITORY_ROOT}/Legal/licenses/COPYING.LGPLv2.1" ]] || fail "LGPL text is missing"
[[ -f "${SOURCE_PATH}" ]] || fail "FFmpeg corresponding source is missing"
[[ -f "${FFMPEG_MANIFEST_PATH}" ]] || fail "FFmpeg source manifest is missing"
[[ -x "${SPLIT_AUDIT_PATH}" ]] || fail "FFmpeg split capability audit is missing or not executable"
[[ -r "${SPLIT_FIXTURE_PATH}" ]] || fail "FFmpeg split capability fixture is missing or unreadable"
[[ -f "${REPOSITORY_ROOT}/docs/releases/v${VERSION}.md" ]] || fail "release notes are missing"
[[ ! -e "/Volumes/${VOLUME_NAME}" ]] || fail "eject the already mounted '${VOLUME_NAME}' volume before packaging"

DIRTY_STATUS="$(git -C "${REPOSITORY_ROOT}" status --porcelain --untracked-files=all -- .)"
[[ -z "${DIRTY_STATUS}" ]] || fail "tracked release files must be committed before packaging:\n${DIRTY_STATUS}"

PROJECT_VERSION="$(sed -n 's/^[[:space:]]*MARKETING_VERSION = \([^;]*\);/\1/p' "${REPOSITORY_ROOT}/FileIsland.xcodeproj/project.pbxproj" | sort -u)"
PROJECT_BUILD="$(sed -n 's/^[[:space:]]*CURRENT_PROJECT_VERSION = \([^;]*\);/\1/p' "${REPOSITORY_ROOT}/FileIsland.xcodeproj/project.pbxproj" | sort -u)"
[[ "${PROJECT_VERSION}" == "${VERSION}" ]] || fail "Xcode marketing version ${PROJECT_VERSION} does not match ${VERSION}"
[[ "${PROJECT_BUILD}" == "${BUILD_NUMBER}" ]] || fail "Xcode build number ${PROJECT_BUILD} does not match ${BUILD_NUMBER}"

ACTUAL_SOURCE_SHA256="$(shasum -a 256 "${SOURCE_PATH}" | awk '{print $1}')"
[[ "${ACTUAL_SOURCE_SHA256}" == "${EXPECTED_SOURCE_SHA256}" ]] || fail "FFmpeg source checksum mismatch"
/usr/bin/plutil -convert xml1 -o /dev/null "${FFMPEG_MANIFEST_PATH}" || fail "FFmpeg source manifest is invalid JSON"
EXPECTED_FFMPEG_SHA256="$(/usr/bin/plutil -extract binarySHA256 raw "${FFMPEG_MANIFEST_PATH}")"
EXPECTED_FFPROBE_SHA256="$(/usr/bin/plutil -extract ffprobeBinarySHA256 raw "${FFMPEG_MANIFEST_PATH}")"
ACTUAL_FFMPEG_SHA256="$(shasum -a 256 "${REPOSITORY_ROOT}/Vendor/FFmpeg/ffmpeg" | awk '{print $1}')"
ACTUAL_FFPROBE_SHA256="$(shasum -a 256 "${REPOSITORY_ROOT}/Vendor/FFmpeg/ffprobe" | awk '{print $1}')"
[[ "${ACTUAL_FFMPEG_SHA256}" == "${EXPECTED_FFMPEG_SHA256}" ]] || fail "repository ffmpeg checksum mismatch"
[[ "${ACTUAL_FFPROBE_SHA256}" == "${EXPECTED_FFPROBE_SHA256}" ]] || fail "repository ffprobe checksum mismatch"

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
print -- "Release build completed"

APP_PATH="${DERIVED_DATA_PATH}/Build/Products/Release/FileIsland.app"
MAIN_EXECUTABLE="${APP_PATH}/Contents/MacOS/FileIsland"
FFMPEG_EXECUTABLE="${APP_PATH}/Contents/MacOS/ffmpeg"
FFPROBE_EXECUTABLE="${APP_PATH}/Contents/MacOS/ffprobe"
MEDIA_VALIDATOR_EXECUTABLE="${APP_PATH}/Contents/MacOS/FileIslandMediaValidator"

[[ -d "${APP_PATH}" ]] || fail "Release app was not produced"
lipo "${MAIN_EXECUTABLE}" -verify_arch arm64 x86_64
lipo "${FFMPEG_EXECUTABLE}" -verify_arch arm64 x86_64
lipo "${FFPROBE_EXECUTABLE}" -verify_arch arm64 x86_64
lipo "${MEDIA_VALIDATOR_EXECUTABLE}" -verify_arch arm64 x86_64
verify_system_dependencies "${FFMPEG_EXECUTABLE}"
verify_system_dependencies "${FFPROBE_EXECUTABLE}"
verify_system_dependencies "${MEDIA_VALIDATOR_EXECUTABLE}"
[[ -f "${APP_PATH}/Contents/Resources/Assets.car" ]] || fail "compiled asset catalog is missing"
[[ -f "${APP_PATH}/Contents/Resources/AppIcon.icns" ]] || fail "AppIcon is missing"
[[ -f "${APP_PATH}/Contents/Resources/built-in-presets.json" ]] || fail "preset catalog is missing"

FFMPEG_CONFIGURATION="$("${FFMPEG_EXECUTABLE}" -version 2>&1)"
FFPROBE_CONFIGURATION="$("${FFPROBE_EXECUTABLE}" -version 2>&1)"
[[ "${FFMPEG_CONFIGURATION}" == ffmpeg\ version\ 8.1.2* ]] || fail "bundled ffmpeg version is not 8.1.2"
[[ "${FFPROBE_CONFIGURATION}" == ffprobe\ version\ 8.1.2* ]] || fail "bundled ffprobe version is not 8.1.2"
[[ "${FFMPEG_CONFIGURATION}" != *"--enable-gpl"* ]] || fail "bundled FFmpeg unexpectedly enables GPL components"
[[ "${FFMPEG_CONFIGURATION}" != *"--enable-nonfree"* ]] || fail "bundled FFmpeg unexpectedly enables nonfree components"
[[ "${FFPROBE_CONFIGURATION}" != *"--enable-gpl"* ]] || fail "bundled ffprobe unexpectedly enables GPL components"
[[ "${FFPROBE_CONFIGURATION}" != *"--enable-nonfree"* ]] || fail "bundled ffprobe unexpectedly enables nonfree components"
[[ "${FFMPEG_CONFIGURATION}" == *"--disable-network"* ]] || fail "bundled FFmpeg must disable network support"
[[ "${FFPROBE_CONFIGURATION}" == *"--disable-network"* ]] || fail "bundled ffprobe must disable network support"

SPLIT_AUDIT_OUTPUT="$("${SPLIT_AUDIT_PATH}" "${FFMPEG_EXECUTABLE}" "${SPLIT_FIXTURE_PATH}")"
require_audit_field "${SPLIT_AUDIT_OUTPUT}" "audit_schema_version=2"
require_audit_field "${SPLIT_AUDIT_OUTPUT}" "ffmpeg_version=8.1.2"
require_audit_field "${SPLIT_AUDIT_OUTPUT}" "ffprobe_version=8.1.2"
require_audit_field "${SPLIT_AUDIT_OUTPUT}" "ffprobe_version_matches=true"
require_audit_field "${SPLIT_AUDIT_OUTPUT}" "keyframe_fixture_probe=true"
require_audit_field "${SPLIT_AUDIT_OUTPUT}" "segment_fixture_smoke=true"
require_audit_field "${SPLIT_AUDIT_OUTPUT}" "fast_split_ready=true"
MEDIA_VALIDATOR_OUTPUT="$("${MEDIA_VALIDATOR_EXECUTABLE}" --first-frame "${SPLIT_FIXTURE_PATH}")"
[[ "${MEDIA_VALIDATOR_OUTPUT}" == '{"decodable":true,"schemaVersion":1}' ]] ||
  fail "bundled AVFoundation media validator rejected the audited fixture"

LEGAL_RESOURCE_PATH="${APP_PATH}/Contents/Resources/Legal"
mkdir -p "${LEGAL_RESOURCE_PATH}"
ditto "${REPOSITORY_ROOT}/LICENSE" "${LEGAL_RESOURCE_PATH}/LICENSE"
ditto "${REPOSITORY_ROOT}/docs/releases/v${VERSION}.md" "${LEGAL_RESOURCE_PATH}/RELEASE_NOTES.md"
ditto "${REPOSITORY_ROOT}/Legal/THIRD_PARTY_NOTICES.md" "${LEGAL_RESOURCE_PATH}/THIRD_PARTY_NOTICES.md"
ditto "${REPOSITORY_ROOT}/Legal/licenses/COPYING.LGPLv2.1" "${LEGAL_RESOURCE_PATH}/COPYING.LGPLv2.1"
ditto "${REPOSITORY_ROOT}/Legal/FFMPEG_BUILD.md" "${LEGAL_RESOURCE_PATH}/FFMPEG_BUILD.md"
ditto "${REPOSITORY_ROOT}/docs/USER_GUIDE.md" "${LEGAL_RESOURCE_PATH}/USER_GUIDE.md"
ditto "${REPOSITORY_ROOT}/docs/USER_GUIDE.zh-CN.md" "${LEGAL_RESOURCE_PATH}/USER_GUIDE.zh-CN.md"
ditto "${REPOSITORY_ROOT}/docs/FORMAT_MATRIX.md" "${LEGAL_RESOURCE_PATH}/FORMAT_MATRIX.md"
ditto "${REPOSITORY_ROOT}/docs/FORMAT_MATRIX.zh-CN.md" "${LEGAL_RESOURCE_PATH}/FORMAT_MATRIX.zh-CN.md"

codesign --force --options runtime --sign - "${FFMPEG_EXECUTABLE}"
codesign --force --options runtime --sign - "${FFPROBE_EXECUTABLE}"
codesign --force --options runtime --sign - "${MEDIA_VALIDATOR_EXECUTABLE}"
codesign \
  --force \
  --options runtime \
  --entitlements "${REPOSITORY_ROOT}/FileIsland/FileIsland.entitlements" \
  --sign - \
  "${APP_PATH}"
codesign --verify --strict --verbose=2 "${FFMPEG_EXECUTABLE}"
codesign --verify --strict --verbose=2 "${FFPROBE_EXECUTABLE}"
codesign --verify --strict --verbose=2 "${MEDIA_VALIDATOR_EXECUTABLE}"
codesign --verify --deep --strict --verbose=2 "${APP_PATH}"
print -- "Universal slices, FFmpeg/ffprobe configuration, isolated AVFoundation validation, resources, and nested signatures verified"

mkdir -p "${STAGE_PATH}/.background"
ditto "${APP_PATH}" "${STAGE_PATH}/File Island.app"
ln -s /Applications "${STAGE_PATH}/Applications"
xcrun swift \
  -module-cache-path "${TEMP_ROOT}/SwiftModuleCache" \
  "${REPOSITORY_ROOT}/Scripts/render-dmg-background.swift" \
  "${STAGE_PATH}/.background/background.png"
print -- "DMG staging directory prepared"

mkdir -p "${ARTIFACT_ROOT}"
[[ ! -e "${FINAL_DMG_PATH}" ]] || fail "release artifact already exists: ${FINAL_DMG_PATH}"
[[ ! -e "${FINAL_DMG_CHECKSUM_PATH}" ]] || fail "release checksum already exists: ${FINAL_DMG_CHECKSUM_PATH}"
[[ ! -e "${FINAL_SOURCE_PATH}" ]] || fail "release source already exists: ${FINAL_SOURCE_PATH}"
[[ ! -e "${FINAL_SOURCE_CHECKSUM_PATH}" ]] || fail "source checksum already exists: ${FINAL_SOURCE_CHECKSUM_PATH}"

hdiutil create \
  -volname "${VOLUME_NAME}" \
  -srcfolder "${STAGE_PATH}" \
  -format UDRW \
  -ov \
  "${WRITABLE_DMG_PATH}" >/dev/null
print -- "Writable DMG created"

mkdir -p "${MOUNT_POINT}"
hdiutil attach "${WRITABLE_DMG_PATH}" -readwrite -noverify -noautoopen -mountpoint "${MOUNT_POINT}" >/dev/null
print -- "Writable DMG mounted"
osascript "${REPOSITORY_ROOT}/Scripts/style-dmg.applescript" "${MOUNT_POINT}"
print -- "Finder DMG layout applied"
sync
hdiutil detach "${MOUNT_POINT}" -quiet
print -- "Writable DMG detached"

hdiutil convert "${WRITABLE_DMG_PATH}" -format UDZO -imagekey zlib-level=9 -o "${DMG_PATH}" >/dev/null
print -- "Compressed DMG created"
ditto "${SOURCE_PATH}" "${RELEASE_SOURCE_PATH}"

(
  cd "${ARTIFACT_ROOT}"
  shasum -a 256 "${DMG_PATH:t}" > "${DMG_CHECKSUM_PATH:t}"
  shasum -a 256 "${RELEASE_SOURCE_PATH:t}" > "${SOURCE_CHECKSUM_PATH:t}"
)

hdiutil imageinfo "${DMG_PATH}" >/dev/null
"${REPOSITORY_ROOT}/Scripts/verify-dmg-layout.sh" "${DMG_PATH}"
mkdir -p "${RELEASE_ROOT}"
mv "${DMG_PATH}" "${FINAL_DMG_PATH}"
mv "${DMG_CHECKSUM_PATH}" "${FINAL_DMG_CHECKSUM_PATH}"
mv "${RELEASE_SOURCE_PATH}" "${FINAL_SOURCE_PATH}"
mv "${SOURCE_CHECKSUM_PATH}" "${FINAL_SOURCE_CHECKSUM_PATH}"
print -- "Release artifacts verified before publication at ${RELEASE_ROOT}"
print -- "Upload all four files from that directory to GitHub Release v${VERSION}."
