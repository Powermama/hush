#!/bin/sh
set -eu

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MACOS_ROOT=$(dirname "$SCRIPT_DIR")
WEBAPP_ROOT=$(dirname "$MACOS_ROOT")/webapp

cd "$WEBAPP_ROOT"
bun run api:openapi
cp openapi/hush-provenance.json \
    "$MACOS_ROOT/Packages/HushProvenance/Sources/HushProvenance/openapi.yaml"
