#!/usr/bin/env bash
# SPDX-License-Identifier: AGPL-3.0-only
# Copyright (c) 2026 Clemens Kressmann
#
# CMS-BACKUP-001: a backup is only proven by a restore. Starts the CMS and its
# database from webapp/compose.yaml, writes a post through the API, backs up,
# restores into a fresh database and compares the content. Run from anywhere:
#   apps/cms/scripts/backup-drill.sh
set -euo pipefail
cd "$(dirname "$0")/../../.."
project="hush-backup-drill-$$"
compose() { docker compose -p "$project" -f compose.yaml "$@"; }
trap 'compose down -v >/dev/null 2>&1 || true' EXIT

compose up -d --build --wait cms >/dev/null
port=$(compose port cms 3100 | cut -d: -f2)
token=$(compose exec -T cms bun run --silent cms:token --name drill --scopes posts:read,posts:write)
curl -sf -X POST "http://127.0.0.1:$port/v1/posts" -H "authorization: Bearer $token" -H 'content-type: application/json' -d '{
  "lang": "en", "slug": "backup-drill", "keyword": "backup drill", "secondaryKeywords": ["restore check"],
  "title": "How to dictate on a Mac without the cloud, step by step",
  "description": "A practical guide to dictating on a Mac with speech models that run locally, what still needs the internet, and how to set everything up in minutes.",
  "type": "how-to", "cluster": "local-dictation", "author": "clemens-kressmann",
  "imageAlt": "A Mac with a dictation waveform.", "markdown": "# Backup drill"
}' >/dev/null

compose exec -T cms bun run --silent cms:backup
compose exec -T cms-postgres createdb -U cms cms_restore
compose exec -T cms bun run --silent cms:restore --target-url postgresql://cms:cms-local@cms-postgres:5432/cms_restore

query='select string_agg(concat_ws(chr(47), p.slug, k.keyword), chr(44) order by p.slug) from posts p join post_secondary_keywords k on k.post_id = p.id'
live=$(compose exec -T cms-postgres psql -U cms -d cms -tAc "$query")
restored=$(compose exec -T cms-postgres psql -U cms -d cms_restore -tAc "$query")
tokens=$(compose exec -T cms-postgres psql -U cms -d cms_restore -tAc 'select count(*) from api_tokens')
if [[ -z "$live" || "$live" != "$restored" || "$tokens" != "1" ]]; then
  echo "Backup drill FAILED: live='$live' restored='$restored' tokens=$tokens" >&2
  exit 1
fi
echo "Backup drill passed: restored '$restored' and $tokens token from the backup."
