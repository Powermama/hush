#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${1:-${HUSH_RELEASE_DIRECTORY:-${SCRIPT_DIRECTORY}/../artifacts/release}/export/hush.app}"
OUTPUT_DIRECTORY="${2:-${SCRIPT_DIRECTORY}/../artifacts/updates/alpha}"
UPDATE_ORIGIN="${HUSH_UPDATE_ORIGIN:-https://updates.behu.sh}"
UPDATE_CHANNEL="${HUSH_UPDATE_CHANNEL:-alpha}"
SPARKLE_ACCOUNT="${HUSH_SPARKLE_ACCOUNT:-behu.sh}"
SPARKLE_BIN_DIRECTORY="${HUSH_SPARKLE_BIN_DIRECTORY:-}"

if [[ ! -d "${APP_PATH}" ]]; then
  echo "App bundle not found: ${APP_PATH}" >&2
  exit 1
fi

python3 "${SCRIPT_DIRECTORY}/check_distribution.py" "${APP_PATH}" --phase postflight

INFO_PLIST="${APP_PATH}/Contents/Info.plist"
BUNDLE_IDENTIFIER="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "${INFO_PLIST}")"
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
RELEASE_SLUG="$(/usr/libexec/PlistBuddy -c 'Print :HushReleaseSlug' "${INFO_PLIST}" 2>/dev/null || true)"

if [[ "${BUNDLE_IDENTIFIER}" != "com.decentralfreedom.hush" ]]; then
  echo "Refusing to publish unexpected bundle identifier: ${BUNDLE_IDENTIFIER}" >&2
  exit 1
fi
if ! [[ "${BUILD}" =~ ^[0-9]+$ ]]; then
  echo "CFBundleVersion must be an increasing integer, found: ${BUILD}" >&2
  exit 1
fi
if [[ -n "${RELEASE_SLUG}" ]] && ! [[ "${RELEASE_SLUG}" =~ ^(alpha|beta|rc)\.[1-9][0-9]*$ ]]; then
  echo "HushReleaseSlug must be alpha.N, beta.N, rc.N, or empty for stable releases; found: ${RELEASE_SLUG}" >&2
  exit 1
fi

if [[ -z "${SPARKLE_BIN_DIRECTORY}" ]]; then
  DERIVED_DATA_DIRECTORY="${HUSH_DERIVED_DATA_PATH:-/tmp/hush-release}"
  CANDIDATE="${DERIVED_DATA_DIRECTORY}/SourcePackages/artifacts/sparkle/Sparkle/bin"
  if [[ -x "${CANDIDATE}/generate_appcast" ]]; then
    SPARKLE_BIN_DIRECTORY="${CANDIDATE}"
  fi
fi
if [[ ! -x "${SPARKLE_BIN_DIRECTORY}/generate_appcast" ]]; then
  echo "Sparkle tools not found. Build Hush once or set HUSH_SPARKLE_BIN_DIRECTORY." >&2
  exit 1
fi

mkdir -p "${OUTPUT_DIRECTORY}"
SUFFIX="${RELEASE_SLUG:+-${RELEASE_SLUG}}"
ARCHIVE_NAME="hush-${VERSION}${SUFFIX}-build.${BUILD}.zip"
ARCHIVE_PATH="${OUTPUT_DIRECTORY}/${ARCHIVE_NAME}"
rm -f "${ARCHIVE_PATH}"
ditto -c -k --sequesterRsrc --keepParent "${APP_PATH}" "${ARCHIVE_PATH}"

if [[ -n "${HUSH_RELEASE_NOTES_FILE:-}" ]]; then
  if [[ ! -f "${HUSH_RELEASE_NOTES_FILE}" ]]; then
    echo "Release notes file not found: ${HUSH_RELEASE_NOTES_FILE}" >&2
    exit 1
  fi
  cp "${HUSH_RELEASE_NOTES_FILE}" "${ARCHIVE_PATH%.*}.md"
fi

"${SPARKLE_BIN_DIRECTORY}/generate_appcast" \
  --account "${SPARKLE_ACCOUNT}" \
  --download-url-prefix "${UPDATE_ORIGIN%/}/${UPDATE_CHANNEL}/" \
  --link "https://behu.sh" \
  --maximum-versions 3 \
  --maximum-deltas 3 \
  --delta-compression lzfse \
  -o "${OUTPUT_DIRECTORY}/appcast.xml" \
  "${OUTPUT_DIRECTORY}"

APPCAST_PATH="${OUTPUT_DIRECTORY}/appcast.xml"
# Sparkle 2.9+ infers this from the arm64 app. Verify the generated metadata
# rather than editing an automatically generated appcast after signing.
HARDWARE_REQUIREMENT="$(xmllint --xpath "string(//*[local-name()='item'][*[local-name()='version' and text()='${BUILD}']]/*[local-name()='hardwareRequirements'])" "${APPCAST_PATH}")"
if [[ "${HARDWARE_REQUIREMENT}" != "arm64" ]]; then
  echo "Generated appcast must restrict this update to Apple Silicon." >&2
  exit 1
fi
ARCHIVE_URL="$(xmllint --xpath "string(//*[local-name()='item'][*[local-name()='version' and text()='${BUILD}']]/*[local-name()='enclosure']/@url)" "${APPCAST_PATH}")"
ARCHIVE_SIGNATURE="$(xmllint --xpath "string(//*[local-name()='item'][*[local-name()='version' and text()='${BUILD}']]/*[local-name()='enclosure']/@*[local-name()='edSignature'])" "${APPCAST_PATH}")"
if [[ -z "${ARCHIVE_URL}" || -z "${ARCHIVE_SIGNATURE}" ]]; then
  echo "Generated appcast is missing the signed enclosure for build ${BUILD}" >&2
  exit 1
fi
if [[ "$(basename "${ARCHIVE_URL}")" != "${ARCHIVE_NAME}" ]]; then
  echo "Generated appcast points to an unexpected archive: ${ARCHIVE_URL}" >&2
  exit 1
fi
"${SPARKLE_BIN_DIRECTORY}/sign_update" \
  --account "${SPARKLE_ACCOUNT}" \
  --verify "${ARCHIVE_PATH}" \
  "${ARCHIVE_SIGNATURE}"

echo "Packaged signed Sparkle update:"
echo "  ${ARCHIVE_PATH}"
echo "  ${OUTPUT_DIRECTORY}/appcast.xml"
