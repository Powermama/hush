#!/usr/bin/env bash
# Explicit local development path; output cannot enter the public publisher.
set -euo pipefail
SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DERIVED_DATA_DIRECTORY="${HUSH_DERIVED_DATA_PATH:-/tmp/hush-local-release}"
cd "${SCRIPT_DIRECTORY}/.."
xcodebuild -project Hush/Hush.xcodeproj -scheme Hush -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "${DERIVED_DATA_DIRECTORY}" \
  -onlyUsePackageVersionsFromResolvedFile -skipPackagePluginValidation -skipMacroValidation \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  HUSH_PROOF_SERVICE_URL="${HUSH_PROOF_SERVICE_URL:-http://127.0.0.1:3000}" \
  HUSH_PROOF_SHORT_URL="${HUSH_PROOF_SHORT_URL:-http://127.0.0.1:3000/s/}" \
  HUSH_UPDATE_FEED_URL="${HUSH_UPDATE_FEED_URL:-http://127.0.0.1:8088/alpha/appcast.xml}" \
  HUSH_RELEASE_CHANNEL='Local Development' HUSH_RELEASE_SLUG=alpha.1-local build
ARGS=(--local --app "${DERIVED_DATA_DIRECTORY}/Build/Products/Release/hush.app")
[[ $# == 0 ]] || ARGS+=(--output "$1")
"${SCRIPT_DIRECTORY}/release-dmg.sh" "${ARGS[@]}"
