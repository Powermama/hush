#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPOSITORY_DIRECTORY="$(cd "${SCRIPT_DIRECTORY}/.." && pwd)"
UPDATE_ENV_FILE="${HUSH_UPDATE_ENV_FILE:-${REPOSITORY_DIRECTORY}/.env.update.local}"

if [[ -f "${UPDATE_ENV_FILE}" ]]; then
  set -a
  # shellcheck disable=SC1090
  source "${UPDATE_ENV_FILE}"
  set +a
fi

APP_PATH="${HUSH_APP_PATH:-${HUSH_RELEASE_DIRECTORY:-${REPOSITORY_DIRECTORY}/artifacts/release}/export/hush.app}"
UPDATE_CHANNEL="${HUSH_UPDATE_CHANNEL:-alpha}"
UPDATE_DIRECTORY="${HUSH_UPDATE_DIRECTORY:-${REPOSITORY_DIRECTORY}/artifacts/updates/${UPDATE_CHANNEL}}"
R2_BUCKET="${HUSH_R2_BUCKET:-hush}"
R2_ENDPOINT="${HUSH_R2_ENDPOINT:-}"
DMG_PATH="${HUSH_DMG_PATH:-}"

# Never publish a local, unnotarized or damaged candidate, even if credentials exist.
python3 "${SCRIPT_DIRECTORY}/check_distribution.py" "${APP_PATH}" --phase postflight
if [[ -n "${DMG_PATH}" ]]; then
  python3 "${SCRIPT_DIRECTORY}/check_dmg_layout.py" "${DMG_PATH}" --app "${APP_PATH}"
  python3 "${SCRIPT_DIRECTORY}/check_distribution.py" "${DMG_PATH}" --phase postflight
fi

if ! command -v aws >/dev/null 2>&1; then
  echo "AWS CLI is required for Cloudflare R2 publishing" >&2
  exit 1
fi
if [[ -z "${R2_ENDPOINT}" ]]; then
  echo "HUSH_R2_ENDPOINT is required, for example https://ACCOUNT_ID.r2.cloudflarestorage.com" >&2
  exit 1
fi
if [[ -z "${AWS_ACCESS_KEY_ID:-}" || -z "${AWS_SECRET_ACCESS_KEY:-}" ]]; then
  echo "AWS_ACCESS_KEY_ID and AWS_SECRET_ACCESS_KEY are required." >&2
  echo "Add them to ${UPDATE_ENV_FILE} or export them in the release shell." >&2
  exit 1
fi

mkdir -p "${UPDATE_DIRECTORY}"
aws s3 sync "s3://${R2_BUCKET}/${UPDATE_CHANNEL}/" "${UPDATE_DIRECTORY}/" \
  --endpoint-url "${R2_ENDPOINT}" \
  --region auto \
  --exclude 'old_updates/*'

INFO_PLIST="${APP_PATH}/Contents/Info.plist"
if [[ ! -f "${INFO_PLIST}" ]]; then
  echo "Release app Info.plist not found: ${INFO_PLIST}" >&2
  exit 1
fi

VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "${INFO_PLIST}")"
BUILD="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "${INFO_PLIST}")"
RELEASE_SLUG="$(/usr/libexec/PlistBuddy -c 'Print :HushReleaseSlug' "${INFO_PLIST}" 2>/dev/null || true)"
APPCAST_PATH="${UPDATE_DIRECTORY}/appcast.xml"

if [[ -f "${APPCAST_PATH}" ]]; then
  LATEST_PUBLISHED_BUILD="$(xmllint --xpath "string((//*[local-name()='item']/*[local-name()='version'])[1])" "${APPCAST_PATH}")"
  if ! [[ "${LATEST_PUBLISHED_BUILD}" =~ ^[0-9]+$ ]]; then
    echo "Existing appcast has an invalid latest build: ${LATEST_PUBLISHED_BUILD}" >&2
    exit 1
  fi
  if (( BUILD <= LATEST_PUBLISHED_BUILD )); then
    echo "Refusing to publish build ${BUILD}; the latest public build is ${LATEST_PUBLISHED_BUILD}." >&2
    echo "Increment CURRENT_PROJECT_VERSION before every tester release." >&2
    exit 1
  fi
fi

EXPECTED_DMG_NAME="hush-${VERSION}${RELEASE_SLUG:+-${RELEASE_SLUG}}-build.${BUILD}.dmg"
if [[ -n "${DMG_PATH}" && "$(basename "${DMG_PATH}")" != "${EXPECTED_DMG_NAME}" ]]; then
  echo "DMG name does not match its embedded release identity." >&2
  echo "Expected: ${EXPECTED_DMG_NAME}" >&2
  echo "Found:    $(basename "${DMG_PATH}")" >&2
  exit 1
fi

"${SCRIPT_DIRECTORY}/package-update.sh" "${APP_PATH}" "${UPDATE_DIRECTORY}"

# Immutable archives and deltas go first. Publishing the mutable appcast last
# prevents clients from seeing an update whose archive is not yet available.
aws s3 sync "${UPDATE_DIRECTORY}/" "s3://${R2_BUCKET}/${UPDATE_CHANNEL}/" \
  --endpoint-url "${R2_ENDPOINT}" \
  --region auto \
  --exclude 'appcast.xml' \
  --exclude 'old_updates/*' \
  --cache-control 'public,max-age=31536000,immutable'

aws s3 cp "${UPDATE_DIRECTORY}/appcast.xml" "s3://${R2_BUCKET}/${UPDATE_CHANNEL}/appcast.xml" \
  --endpoint-url "${R2_ENDPOINT}" \
  --region auto \
  --content-type 'application/xml' \
  --cache-control 'no-store'

if [[ -n "${DMG_PATH}" ]]; then
  if [[ ! -f "${DMG_PATH}" ]]; then
    echo "DMG not found: ${DMG_PATH}" >&2
    exit 1
  fi
  DMG_NAME="$(basename "${DMG_PATH}")"
  aws s3 cp "${DMG_PATH}" "s3://${R2_BUCKET}/downloads/${DMG_NAME}" \
    --endpoint-url "${R2_ENDPOINT}" \
    --region auto \
    --content-type 'application/x-apple-diskimage' \
    --content-disposition "attachment; filename=\"${DMG_NAME}\"" \
    --cache-control 'public,max-age=31536000,immutable'
  aws s3 cp "${DMG_PATH}" "s3://${R2_BUCKET}/downloads/hush-latest.dmg" \
    --endpoint-url "${R2_ENDPOINT}" \
    --region auto \
    --content-type 'application/x-apple-diskimage' \
    --content-disposition 'attachment; filename="hush-latest.dmg"' \
    --cache-control 'no-store'
fi

echo "Published update feed: https://updates.behu.sh/${UPDATE_CHANNEL}/appcast.xml"
