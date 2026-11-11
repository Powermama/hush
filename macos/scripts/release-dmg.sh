#!/usr/bin/env bash
# Package an exported app. Signing is local; Apple submission is explicit opt-in.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIRECTORY="$(cd "${SCRIPT_DIR}/.." && pwd)"
RELEASE_DIRECTORY="${HUSH_RELEASE_DIRECTORY:-${REPOSITORY_DIRECTORY}/artifacts/release}"
APP="${RELEASE_DIRECTORY}/export/hush.app"
OUTPUT=""
LOCAL=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --app) APP="$2"; shift 2 ;;
    --output) OUTPUT="$2"; shift 2 ;;
    --local) LOCAL=1; shift ;;
    -h|--help)
      echo "Usage: $0 [--app exported/hush.app] [--output file.dmg] [--local]"
      echo "Default: signed local candidate. HUSH_NOTARIZE=1 submits to Apple."
      exit 0 ;;
    *) echo "Unknown argument: $1" >&2; exit 1 ;;
  esac
done
if [[ "${LOCAL}" == "0" && "${HUSH_DMG_HEADLESS:-0}" == "1" ]]; then
  echo "Release DMGs require Finder layout. HUSH_DMG_HEADLESS=1 is only allowed with --local." >&2
  exit 1
fi
if ! command -v create-dmg >/dev/null 2>&1; then
  echo "Install create-dmg with Homebrew before packaging." >&2
  exit 1
fi
INFO_PLIST="${APP}/Contents/Info.plist"
[[ -f "${INFO_PLIST}" ]] || { echo "App not found: ${APP}" >&2; exit 1; }
if [[ "${LOCAL}" == "1" && "${HUSH_NOTARIZE:-0}" == "1" ]]; then
  echo "Local development builds cannot be submitted by this script." >&2
  exit 1
fi
if [[ "${LOCAL}" == "0" ]]; then
  python3 "${SCRIPT_DIR}/check_distribution.py" "${APP}" --phase preflight
fi
VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
SLUG="$(/usr/libexec/PlistBuddy -c 'Print :HushReleaseSlug' "${INFO_PLIST}" 2>/dev/null || true)"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
if [[ -z "${OUTPUT}" ]]; then
  OUTPUT="${RELEASE_DIRECTORY}/dist/hush-${VERSION}${SLUG:+-${SLUG}}-build.${BUILD}.dmg"
fi
if [[ -e "${OUTPUT}" ]]; then
  echo "Output already exists; choose another path or resume its notarization: ${OUTPUT}" >&2
  exit 1
fi
mkdir -p "$(dirname "${OUTPUT}")"
ASSET_ARGS=()
[[ -f "${SCRIPT_DIR}/dmg-background.png" ]] || { echo "Installer background is missing." >&2; exit 1; }
ASSET_ARGS+=(--background "${SCRIPT_DIR}/dmg-background.png")
# Headless images are only useful for local development, never distribution.
[[ "${HUSH_DMG_HEADLESS:-0}" != "1" ]] || ASSET_ARGS+=(--skip-jenkins)
create-dmg --volname hush --window-pos 200 120 --window-size 540 380 \
  --icon-size 110 --text-size 13 --icon hush.app 140 180 --app-drop-link 400 180 \
  --hide-extension hush.app ${ASSET_ARGS[@]+"${ASSET_ARGS[@]}"} --no-internet-enable --format UDZO \
  "${OUTPUT}" "${APP}"
if [[ "${LOCAL}" == "0" ]]; then
  python3 "${SCRIPT_DIR}/check_dmg_layout.py" "${OUTPUT}" --app "${APP}"
  # Xcode may choose between renewed certificates with the same display name.
  # Match the exported app's exact public certificate instead of an ambiguous CN.
  CERTIFICATES="$(mktemp -d "${TMPDIR:-/tmp/}hush-dmg-cert.XXXXXX")"
  trap 'rm -rf "${CERTIFICATES}"' EXIT
  codesign --display --extract-certificates="${CERTIFICATES}/cert" "${APP}"
  CERTIFICATE_HASH="$(shasum -a 1 "${CERTIFICATES}/cert0")"
  codesign --sign "${CERTIFICATE_HASH%% *}" --timestamp "${OUTPUT}"
  python3 "${SCRIPT_DIR}/check_distribution.py" "${OUTPUT}" --report "${OUTPUT}.preflight.json"
  if [[ "${HUSH_NOTARIZE:-0}" == "1" ]]; then
    "${SCRIPT_DIR}/notarize-artifact.sh" "${OUTPUT}"
    # The accepted DMG submission also provides a ticket for its nested app.
    # Staple the exported copy for the separate Sparkle ZIP without resubmitting.
    xcrun stapler staple "${APP}"
    python3 "${SCRIPT_DIR}/check_distribution.py" "${APP}" --phase postflight \
      --report "${OUTPUT}.app-postflight.json"
    echo "Notarized installer ready for final install testing: ${OUTPUT}"
  else
    echo "Signed candidate for local review only, not notarized: ${OUTPUT}"
  fi
else
  echo "Local development installer, not for public distribution: ${OUTPUT}"
fi
