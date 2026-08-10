#!/bin/zsh

set -euo pipefail

REPOSITORY_ROOT="${0:A:h:h}"
DERIVED_DATA_PATH="${REPOSITORY_ROOT}/.build/CLIRelease"
PRODUCT_PATH="${DERIVED_DATA_PATH}/Build/Products/Release"
PACKAGE_PATH="${REPOSITORY_ROOT}/.build/fileisland-cli"
SIGN_IDENTITY="${FILEISLAND_SIGN_IDENTITY:--}"

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

SIGNING_ARGUMENTS=(--force --options runtime --sign "${SIGN_IDENTITY}")
if [[ "${SIGN_IDENTITY}" != "-" ]]; then
  SIGNING_ARGUMENTS+=(--timestamp)
fi
codesign "${SIGNING_ARGUMENTS[@]}" "${PACKAGE_PATH}/ffmpeg"
codesign "${SIGNING_ARGUMENTS[@]}" "${PACKAGE_PATH}/fileisland"
codesign --verify --strict "${PACKAGE_PATH}/ffmpeg"
codesign --verify --strict "${PACKAGE_PATH}/fileisland"
lipo "${PACKAGE_PATH}/ffmpeg" -verify_arch arm64 x86_64
lipo "${PACKAGE_PATH}/fileisland" -verify_arch arm64 x86_64
"${PACKAGE_PATH}/fileisland" capabilities --json >/dev/null

echo "CLI package verified at ${PACKAGE_PATH}"
