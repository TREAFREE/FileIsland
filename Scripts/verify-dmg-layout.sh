#!/bin/zsh

set -euo pipefail

REPOSITORY_ROOT="${0:A:h:h}"
SPLIT_AUDIT_PATH="${REPOSITORY_ROOT}/Scripts/audit-ffmpeg-split-capabilities.sh"
SPLIT_FIXTURE_PATH="${REPOSITORY_ROOT}/FileIslandTests/Fixtures/task016-keyframes.mp4"
DMG_PATH="${1:-}"
[[ -n "${DMG_PATH}" && -f "${DMG_PATH}" ]] || {
  print -u2 -- "usage: Scripts/verify-dmg-layout.sh FILE.dmg"
  exit 64
}

MOUNT_POINT="$(mktemp -d /private/tmp/FileIslandDMGVerify.XXXXXX)"
cleanup() {
  hdiutil detach "${MOUNT_POINT}" -quiet 2>/dev/null || true
  /bin/rmdir "${MOUNT_POINT}" 2>/dev/null || true
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

[[ -x "${SPLIT_AUDIT_PATH}" ]] || fail "FFmpeg split capability audit is missing or not executable"
[[ -r "${SPLIT_FIXTURE_PATH}" ]] || fail "FFmpeg split capability fixture is missing or unreadable"

hdiutil attach "${DMG_PATH}" -readonly -nobrowse -mountpoint "${MOUNT_POINT}" -quiet

VISIBLE_ITEMS="$(find "${MOUNT_POINT}" -mindepth 1 -maxdepth 1 ! -name '.*' -print | sed 's#^.*/##' | sort)"
EXPECTED_ITEMS=$'Applications\nFile Island.app'
[[ "${VISIBLE_ITEMS}" == "${EXPECTED_ITEMS}" ]] || {
  print -u2 -- "error: unexpected visible DMG items:\n${VISIBLE_ITEMS}"
  exit 1
}

[[ -L "${MOUNT_POINT}/Applications" ]] || {
  print -u2 -- "error: Applications must be a symlink"
  exit 1
}
[[ "$(readlink "${MOUNT_POINT}/Applications")" == "/Applications" ]] || {
  print -u2 -- "error: Applications symlink has the wrong target"
  exit 1
}

APP_ROOT="${MOUNT_POINT}/File Island.app"
MAIN_EXECUTABLE="${APP_ROOT}/Contents/MacOS/FileIsland"
FFMPEG_EXECUTABLE="${APP_ROOT}/Contents/MacOS/ffmpeg"
FFPROBE_EXECUTABLE="${APP_ROOT}/Contents/MacOS/ffprobe"
MEDIA_VALIDATOR_EXECUTABLE="${APP_ROOT}/Contents/MacOS/FileIslandMediaValidator"
for executable_path in "${MAIN_EXECUTABLE}" "${FFMPEG_EXECUTABLE}" "${FFPROBE_EXECUTABLE}" "${MEDIA_VALIDATOR_EXECUTABLE}"; do
  [[ -x "${executable_path}" ]] || fail "missing executable ${executable_path:t} in final DMG"
  lipo "${executable_path}" -verify_arch arm64 x86_64
done
verify_system_dependencies "${FFMPEG_EXECUTABLE}"
verify_system_dependencies "${FFPROBE_EXECUTABLE}"
verify_system_dependencies "${MEDIA_VALIDATOR_EXECUTABLE}"

# Verify code-directory integrity before executing anything from the mounted
# image. An ad-hoc signature does not authenticate the publisher, but it does
# let this local release check reject a modified Mach-O before launch.
codesign --verify --strict "${FFMPEG_EXECUTABLE}"
codesign --verify --strict "${FFPROBE_EXECUTABLE}"
codesign --verify --strict "${MEDIA_VALIDATOR_EXECUTABLE}"
codesign --verify --deep --strict "${APP_ROOT}"

FFMPEG_CONFIGURATION="$("${FFMPEG_EXECUTABLE}" -version 2>&1)"
FFPROBE_CONFIGURATION="$("${FFPROBE_EXECUTABLE}" -version 2>&1)"
[[ "${FFMPEG_CONFIGURATION}" == ffmpeg\ version\ 8.1.2* ]] || fail "DMG ffmpeg version is not 8.1.2"
[[ "${FFPROBE_CONFIGURATION}" == ffprobe\ version\ 8.1.2* ]] || fail "DMG ffprobe version is not 8.1.2"
for configuration in "${FFMPEG_CONFIGURATION}" "${FFPROBE_CONFIGURATION}"; do
  [[ "${configuration}" != *"--enable-gpl"* ]] || fail "DMG FFmpeg tools unexpectedly enable GPL components"
  [[ "${configuration}" != *"--enable-nonfree"* ]] || fail "DMG FFmpeg tools unexpectedly enable nonfree components"
  [[ "${configuration}" == *"--disable-network"* ]] || fail "DMG FFmpeg tools must disable network support"
done

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
  fail "DMG AVFoundation media validator rejected the audited fixture"

LEGAL_ROOT="${APP_ROOT}/Contents/Resources/Legal"
for legal_file in LICENSE RELEASE_NOTES.md THIRD_PARTY_NOTICES.md COPYING.LGPLv2.1 FFMPEG_BUILD.md USER_GUIDE.md USER_GUIDE.zh-CN.md FORMAT_MATRIX.md FORMAT_MATRIX.zh-CN.md; do
  [[ -f "${LEGAL_ROOT}/${legal_file}" ]] || {
    print -u2 -- "error: missing embedded legal file ${legal_file}"
    exit 1
  }
done

[[ -f "${MOUNT_POINT}/.background/background.png" ]] || {
  print -u2 -- "error: styled DMG background is missing"
  exit 1
}
[[ -f "${MOUNT_POINT}/.DS_Store" ]] || {
  print -u2 -- "error: Finder layout metadata is missing"
  exit 1
}

print -- "DMG layout and offline universal ffmpeg/ffprobe/AVFoundation runtime verified"
