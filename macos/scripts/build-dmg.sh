#!/usr/bin/env bash
# Developer ID distribution. Use build-local-dmg.sh for local development.
set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIRECTORY="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
DERIVED_DATA_DIRECTORY="${HUSH_DERIVED_DATA_PATH:-/tmp/hush-release}"
RELEASE_DIRECTORY="${HUSH_RELEASE_DIRECTORY:-${REPOSITORY_DIRECTORY}/artifacts/release}"
TEAM="${HUSH_DEVELOPMENT_TEAM:-3A22UK7C9L}"
IDENTITY="${HUSH_CODE_SIGN_IDENTITY:-Developer ID Application}"
APP_PATH="${RELEASE_DIRECTORY}/export/hush.app"
export HUSH_DEVELOPMENT_TEAM="${TEAM}"
export HUSH_NOTARY_KEYCHAIN_PROFILE="${HUSH_NOTARY_KEYCHAIN_PROFILE:-HushNotary}"

if [[ $# -gt 1 || ! "${HUSH_NOTARIZE:-0}" =~ ^[01]$ ]]; then
  echo "Usage: $0 [output.dmg]. Submission requires explicit HUSH_NOTARIZE=1." >&2
  exit 1
fi
if [[ -e "${RELEASE_DIRECTORY}/Hush.xcarchive" || -e "${RELEASE_DIRECTORY}/export" ]]; then
  echo "Release output already exists. Resume notarization or choose a new HUSH_RELEASE_DIRECTORY." >&2
  exit 1
fi
mkdir -p "${RELEASE_DIRECTORY}/reports"
cd "${REPOSITORY_DIRECTORY}"
git rev-parse HEAD > "${RELEASE_DIRECTORY}/reports/source-revision.txt"
git diff --binary HEAD > "${RELEASE_DIRECTORY}/reports/source-changes.patch"
xcodebuild -version > "${RELEASE_DIRECTORY}/reports/xcode-version.txt"
cp Hush/Hush.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved \
  "${RELEASE_DIRECTORY}/reports/Package.resolved"
cp "${SCRIPT_DIRECTORY}/DeveloperID-ExportOptions.plist" "${RELEASE_DIRECTORY}/ExportOptions.plist"
/usr/libexec/PlistBuddy -c "Set :teamID ${TEAM}" "${RELEASE_DIRECTORY}/ExportOptions.plist"
/usr/libexec/PlistBuddy -c "Set :signingCertificate ${IDENTITY}" "${RELEASE_DIRECTORY}/ExportOptions.plist"

RELEASE_ARGUMENTS=()
[[ -z "${HUSH_RELEASE_CHANNEL:-}" ]] || RELEASE_ARGUMENTS+=(HUSH_RELEASE_CHANNEL="${HUSH_RELEASE_CHANNEL}")
[[ -z "${HUSH_RELEASE_SLUG:-}" ]] || RELEASE_ARGUMENTS+=(HUSH_RELEASE_SLUG="${HUSH_RELEASE_SLUG}")
# Explicit trust in reviewed pinned packages, never global Xcode defaults.
TRUST_ARGUMENTS=()
if [[ "${HUSH_TRUST_PINNED_BUILD_TOOLS:-0}" == "1" ]]; then
  TRUST_ARGUMENTS+=(-skipMacroValidation -skipPackagePluginValidation)
fi

xcodebuild -project Hush/Hush.xcodeproj -scheme Hush -configuration Release \
  -destination 'generic/platform=macOS' -derivedDataPath "${DERIVED_DATA_DIRECTORY}" \
  -onlyUsePackageVersionsFromResolvedFile ${TRUST_ARGUMENTS[@]+"${TRUST_ARGUMENTS[@]}"} \
  CODE_SIGN_STYLE=Manual CODE_SIGN_IDENTITY="${IDENTITY}" DEVELOPMENT_TEAM="${TEAM}" \
  ARCHS=arm64 ONLY_ACTIVE_ARCH=NO \
  HUSH_PROOF_SERVICE_URL="${HUSH_PROOF_SERVICE_URL:-https://behu.sh}" \
  HUSH_PROOF_SHORT_URL="${HUSH_PROOF_SHORT_URL:-https://behu.sh/s/}" \
  HUSH_UPDATE_FEED_URL="${HUSH_UPDATE_FEED_URL:-https://updates.behu.sh/alpha/appcast.xml}" \
  ${RELEASE_ARGUMENTS[@]+"${RELEASE_ARGUMENTS[@]}"} archive -archivePath "${RELEASE_DIRECTORY}/Hush.xcarchive" \
  2>&1 | tee "${RELEASE_DIRECTORY}/reports/archive.log"

xcodebuild -exportArchive -archivePath "${RELEASE_DIRECTORY}/Hush.xcarchive" \
  -exportOptionsPlist "${RELEASE_DIRECTORY}/ExportOptions.plist" \
  -exportPath "${RELEASE_DIRECTORY}/export" \
  2>&1 | tee "${RELEASE_DIRECTORY}/reports/export.log"
python3 "${SCRIPT_DIRECTORY}/check_assistant_release.py" "${APP_PATH}/Contents/MacOS/hush"
python3 "${SCRIPT_DIRECTORY}/check_distribution.py" "${APP_PATH}" \
  --report "${RELEASE_DIRECTORY}/reports/app-preflight.json"
# Submit the outermost distribution container once; Apple also checks its app.
DMG_ARGUMENTS=(--app "${APP_PATH}")
[[ $# == 0 ]] || DMG_ARGUMENTS+=(--output "$1")
"${SCRIPT_DIRECTORY}/release-dmg.sh" "${DMG_ARGUMENTS[@]}"
if [[ "${HUSH_NOTARIZE:-0}" == "0" ]]; then
  echo "Local candidate prepared. Nothing submitted to Apple or published."
fi
