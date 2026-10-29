#!/usr/bin/env bash
# Runs SQL against the linked project through the Management API, using the
# access token (no database password needed).
#
#   tool/supabase/sql.sh "select title, week_start from menu_kits"
#   echo "select count(*) from menu_kit_items" | tool/supabase/sql.sh
#
# Prints the JSON rows returned by the API. Use it for inspection and one-off
# maintenance; schema changes belong in supabase/migrations/.
set -euo pipefail

_repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=env.sh
. "$_repo_root/tool/supabase/env.sh"

if (($#)); then
  query=$*
else
  query=$(cat)
fi
[[ -n ${query//[[:space:]]/} ]] || {
  echo "usage: tool/supabase/sql.sh <sql>  (or pipe it on stdin)" >&2
  exit 2
}

curl -sS --fail-with-body -X POST \
  "${SUPABASE_MANAGEMENT_URL:-https://api.supabase.com}/v1/projects/$SUPABASE_PROJECT_REF/database/query" \
  -H "Authorization: Bearer $SUPABASE_ACCESS_TOKEN" \
  -H 'Content-Type: application/json' \
  -d "$(jq -nc --arg q "$query" '{query: $q}')"
printf '\n'
