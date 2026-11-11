#!/usr/bin/env bash

set -euo pipefail

FEED_URL="${1:-https://updates.behu.sh/alpha/appcast.xml}"
TEMPORARY_DIRECTORY="$(mktemp -d)"
trap 'rm -rf "${TEMPORARY_DIRECTORY}"' EXIT

curl --fail --silent --show-error --location "${FEED_URL}" \
  --output "${TEMPORARY_DIRECTORY}/appcast.xml"
xmllint --noout "${TEMPORARY_DIRECTORY}/appcast.xml"

ARCHIVE_URL="$(xmllint --xpath 'string(//*[local-name()="enclosure"][1]/@url)' "${TEMPORARY_DIRECTORY}/appcast.xml")"
SIGNATURE="$(xmllint --xpath 'string(//*[local-name()="enclosure"][1]/@*[local-name()="edSignature"])' "${TEMPORARY_DIRECTORY}/appcast.xml")"
if [[ -z "${ARCHIVE_URL}" || -z "${SIGNATURE}" ]]; then
  echo "Appcast is missing a signed enclosure" >&2
  exit 1
fi
curl --fail --silent --show-error --location --head "${ARCHIVE_URL}" >/dev/null

echo "Verified live Sparkle feed and archive:"
echo "  ${FEED_URL}"
echo "  ${ARCHIVE_URL}"
