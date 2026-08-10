#!/bin/zsh

set -euo pipefail

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

LEGAL_ROOT="${MOUNT_POINT}/File Island.app/Contents/Resources/Legal"
for legal_file in LICENSE RELEASE_NOTES.md THIRD_PARTY_NOTICES.md COPYING.LGPLv2.1 FFMPEG_BUILD.md; do
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

print -- "DMG layout verified: File Island.app + Applications"
