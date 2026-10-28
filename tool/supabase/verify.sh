#!/usr/bin/env bash
# Checks that the credentials from tool/supabase/setup.sh work: the CLI is
# authenticated, the project is linked, the tables exist and the private
# PDF bucket is reachable with the secret key.
#
#   tool/supabase/verify.sh
set -euo pipefail

_repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=env.sh
. "$_repo_root/tool/supabase/env.sh"

ok=0
fail=0
pass() { printf '  ok    %s\n' "$*"; ok=$((ok + 1)); }
warn() { printf '  FAIL  %s\n' "$*"; fail=$((fail + 1)); }

printf 'Project: %s (%s)\n\n' "${SUPABASE_PROJECT_REF:-?}" "${SUPABASE_URL:-?}"

if ! command -v supabase >/dev/null; then
  warn "supabase CLI not installed"
else
  if supabase_link=$(cd "$_repo_root" && supabase projects list --output json 2>/dev/null) &&
    jq -e --arg ref "${SUPABASE_PROJECT_REF:-}" \
      '.[] | select(.ref == $ref)' <<<"$supabase_link" >/dev/null; then
    pass "CLI is authenticated and can see the project"
  else
    warn "CLI cannot see the project (token expired? run setup.sh again)"
  fi
fi

# Legacy JWT keys also need a bearer token; sb_secret_ keys go in apikey only.
auth=(-H "apikey: ${SUPABASE_SECRET_KEY:-}")
if [[ ${SUPABASE_SECRET_KEY:-} == eyJ* ]]; then
  auth+=(-H "Authorization: Bearer ${SUPABASE_SECRET_KEY}")
fi

rest_count() { # <table> -> prints the row count, or "missing"
  local table=$1 body headers code total
  body=$(mktemp)
  headers=$(mktemp)
  code=$(curl -sS -o "$body" -D "$headers" -w '%{http_code}' \
    "$SUPABASE_URL/rest/v1/$table?select=*&limit=1" "${auth[@]}" || true)
  if [[ $code != 200 ]]; then
    rm -f "$body" "$headers"
    echo "missing"
    return
  fi
  total=$(tr -d '\r' <"$headers" | sed -n 's/^[Cc]ontent-[Rr]ange:.*\/\([0-9]*\)$/\1/p' | tail -1)
  rm -f "$body" "$headers"
  echo "${total:-0}"
}

for table in menu_kits menu_kit_dishes menu_kit_items menu_kit_recipes \
  menu_kit_recipe_ingredients; do
  count=$(rest_count "$table")
  if [[ $count == missing ]]; then
    warn "table $table is not readable"
  else
    pass "table $table ($count rows)"
  fi
done

bucket_code=$(curl -sS -o /dev/null -w '%{http_code}' \
  "$SUPABASE_URL/storage/v1/bucket/menu-kits" "${auth[@]}" || true)
if [[ $bucket_code == 200 ]]; then
  pass "private bucket menu-kits"
else
  warn "bucket menu-kits not reachable (HTTP $bucket_code)"
fi

if [[ ${SUPABASE_ANON_KEY:-} ]]; then
  anon_body=$(mktemp)
  anon_headers=$(mktemp)
  anon_code=$(curl -sS -o "$anon_body" -D "$anon_headers" -w '%{http_code}' \
    "$SUPABASE_URL/rest/v1/menu_kits?select=id&limit=1" \
    -H "apikey: $SUPABASE_ANON_KEY" || true)
  anon_total=$(tr -d '\r' <"$anon_headers" |
    sed -n 's/^[Cc]ontent-[Rr]ange:.*\/\([0-9]*\)$/\1/p' | tail -1)
  rm -f "$anon_body" "$anon_headers"
  if [[ $anon_code == 401 || $anon_code == 403 ]]; then
    pass "anon key is refused (HTTP $anon_code)"
  elif [[ $anon_code == 200 && ${anon_total:-1} == 0 ]]; then
    pass "anon key is granted no rows"
  else
    warn "anon key can read menu_kits (HTTP $anon_code, ${anon_total:-?} rows)"
  fi
fi

if [[ $fail == 0 ]]; then
  printf '\n%d checks passed.\n' "$ok"
else
  printf '\n%d passed, %d failed.\n' "$ok" "$fail"
  exit 1
fi
