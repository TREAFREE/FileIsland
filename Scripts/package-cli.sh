#!/bin/zsh

set -euo pipefail

REPOSITORY_ROOT="${0:A:h:h}"
DERIVED_DATA_PATH="${REPOSITORY_ROOT}/.build/CLIRelease"
PRODUCT_PATH="${DERIVED_DATA_PATH}/Build/Products/Release"
PACKAGE_PATH="${REPOSITORY_ROOT}/.build/fileisland-cli"
SIGN_IDENTITY="${FILEISLAND_SIGN_IDENTITY:--}"
SPLIT_AUDIT_PATH="${REPOSITORY_ROOT}/Scripts/audit-ffmpeg-split-capabilities.sh"
SPLIT_FIXTURE_PATH="${REPOSITORY_ROOT}/FileIslandTests/Fixtures/task016-keyframes.mp4"
FFMPEG_MANIFEST_PATH="${REPOSITORY_ROOT}/Vendor/FFmpeg/SOURCE.json"

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

[[ -x "${SPLIT_AUDIT_PATH}" ]] || fail "FFmpeg split capability audit is missing or not executable"
[[ -r "${SPLIT_FIXTURE_PATH}" ]] || fail "FFmpeg split capability fixture is missing or unreadable"
[[ -f "${FFMPEG_MANIFEST_PATH}" ]] || fail "FFmpeg source manifest is missing"
/usr/bin/plutil -convert xml1 -o /dev/null "${FFMPEG_MANIFEST_PATH}" || fail "FFmpeg source manifest is invalid JSON"
EXPECTED_FFMPEG_SHA256="$(/usr/bin/plutil -extract binarySHA256 raw "${FFMPEG_MANIFEST_PATH}")"
EXPECTED_FFPROBE_SHA256="$(/usr/bin/plutil -extract ffprobeBinarySHA256 raw "${FFMPEG_MANIFEST_PATH}")"
ACTUAL_FFMPEG_SHA256="$(shasum -a 256 "${REPOSITORY_ROOT}/Vendor/FFmpeg/ffmpeg" | awk '{print $1}')"
ACTUAL_FFPROBE_SHA256="$(shasum -a 256 "${REPOSITORY_ROOT}/Vendor/FFmpeg/ffprobe" | awk '{print $1}')"
[[ "${ACTUAL_FFMPEG_SHA256}" == "${EXPECTED_FFMPEG_SHA256}" ]] || fail "repository ffmpeg checksum mismatch"
[[ "${ACTUAL_FFPROBE_SHA256}" == "${EXPECTED_FFPROBE_SHA256}" ]] || fail "repository ffprobe checksum mismatch"

xcodebuild \
  -project "${REPOSITORY_ROOT}/FileIsland.xcodeproj" \
  -scheme FileIslandCLI \
  -configuration Release \
  -destination 'generic/platform=macOS' \
  -derivedDataPath "${DERIVED_DATA_PATH}" \
  ARCHS="arm64 x86_64" \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

rm -rf "${PACKAGE_PATH}"
mkdir -p "${PACKAGE_PATH}"
ditto "${PRODUCT_PATH}/fileisland" "${PACKAGE_PATH}/fileisland"
ditto "${PRODUCT_PATH}/built-in-presets.json" "${PACKAGE_PATH}/built-in-presets.json"
ditto "${PRODUCT_PATH}/ffmpeg" "${PACKAGE_PATH}/ffmpeg"
ditto "${PRODUCT_PATH}/ffprobe" "${PACKAGE_PATH}/ffprobe"
ditto "${PRODUCT_PATH}/FileIslandMediaValidator" "${PACKAGE_PATH}/FileIslandMediaValidator"

PACKAGED_FFMPEG_SHA256="$(shasum -a 256 "${PACKAGE_PATH}/ffmpeg" | awk '{print $1}')"
PACKAGED_FFPROBE_SHA256="$(shasum -a 256 "${PACKAGE_PATH}/ffprobe" | awk '{print $1}')"
[[ "${PACKAGED_FFMPEG_SHA256}" == "${EXPECTED_FFMPEG_SHA256}" ]] || fail "packaged ffmpeg checksum mismatch"
[[ "${PACKAGED_FFPROBE_SHA256}" == "${EXPECTED_FFPROBE_SHA256}" ]] || fail "packaged ffprobe checksum mismatch"

lipo "${PACKAGE_PATH}/ffmpeg" -verify_arch arm64 x86_64
lipo "${PACKAGE_PATH}/ffprobe" -verify_arch arm64 x86_64
lipo "${PACKAGE_PATH}/FileIslandMediaValidator" -verify_arch arm64 x86_64
lipo "${PACKAGE_PATH}/fileisland" -verify_arch arm64 x86_64
verify_system_dependencies "${PACKAGE_PATH}/ffmpeg"
verify_system_dependencies "${PACKAGE_PATH}/ffprobe"
verify_system_dependencies "${PACKAGE_PATH}/FileIslandMediaValidator"
FFMPEG_CONFIGURATION="$("${PACKAGE_PATH}/ffmpeg" -version 2>&1)"
FFPROBE_CONFIGURATION="$("${PACKAGE_PATH}/ffprobe" -version 2>&1)"
[[ "${FFMPEG_CONFIGURATION}" == ffmpeg\ version\ 8.1.2* ]] || fail "packaged ffmpeg version is not 8.1.2"
[[ "${FFPROBE_CONFIGURATION}" == ffprobe\ version\ 8.1.2* ]] || fail "packaged ffprobe version is not 8.1.2"
for configuration in "${FFMPEG_CONFIGURATION}" "${FFPROBE_CONFIGURATION}"; do
  [[ "${configuration}" != *"--enable-gpl"* ]] || fail "packaged FFmpeg tools unexpectedly enable GPL components"
  [[ "${configuration}" != *"--enable-nonfree"* ]] || fail "packaged FFmpeg tools unexpectedly enable nonfree components"
  [[ "${configuration}" == *"--disable-network"* ]] || fail "packaged FFmpeg tools must disable network support"
done

SPLIT_AUDIT_OUTPUT="$("${SPLIT_AUDIT_PATH}" "${PACKAGE_PATH}/ffmpeg" "${SPLIT_FIXTURE_PATH}")"
require_audit_field "${SPLIT_AUDIT_OUTPUT}" "audit_schema_version=2"
require_audit_field "${SPLIT_AUDIT_OUTPUT}" "ffmpeg_version=8.1.2"
require_audit_field "${SPLIT_AUDIT_OUTPUT}" "ffprobe_version=8.1.2"
require_audit_field "${SPLIT_AUDIT_OUTPUT}" "ffprobe_version_matches=true"
require_audit_field "${SPLIT_AUDIT_OUTPUT}" "keyframe_fixture_probe=true"
require_audit_field "${SPLIT_AUDIT_OUTPUT}" "segment_fixture_smoke=true"
require_audit_field "${SPLIT_AUDIT_OUTPUT}" "fast_split_ready=true"
MEDIA_VALIDATOR_OUTPUT="$("${PACKAGE_PATH}/FileIslandMediaValidator" --first-frame "${SPLIT_FIXTURE_PATH}")"
[[ "${MEDIA_VALIDATOR_OUTPUT}" == '{"decodable":true,"schemaVersion":1}' ]] ||
  fail "packaged AVFoundation media validator rejected the audited fixture"

SIGNING_ARGUMENTS=(--force --options runtime --sign "${SIGN_IDENTITY}")
if [[ "${SIGN_IDENTITY}" != "-" ]]; then
  SIGNING_ARGUMENTS+=(--timestamp)
fi
codesign "${SIGNING_ARGUMENTS[@]}" "${PACKAGE_PATH}/ffmpeg"
codesign "${SIGNING_ARGUMENTS[@]}" "${PACKAGE_PATH}/ffprobe"
codesign "${SIGNING_ARGUMENTS[@]}" "${PACKAGE_PATH}/FileIslandMediaValidator"
codesign "${SIGNING_ARGUMENTS[@]}" "${PACKAGE_PATH}/fileisland"
codesign --verify --strict "${PACKAGE_PATH}/ffmpeg"
codesign --verify --strict "${PACKAGE_PATH}/ffprobe"
codesign --verify --strict "${PACKAGE_PATH}/FileIslandMediaValidator"
codesign --verify --strict "${PACKAGE_PATH}/fileisland"
"${PACKAGE_PATH}/fileisland" capabilities --json >/dev/null

echo "CLI package verified with sibling ffmpeg, ffprobe, and AVFoundation validator at ${PACKAGE_PATH}"
