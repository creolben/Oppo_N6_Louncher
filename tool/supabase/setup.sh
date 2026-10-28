#!/usr/bin/env bash
# Connects this checkout to a Supabase project and stores the credentials
# PandaCode needs, outside the repository.
#
#   SUPABASE_ACCESS_TOKEN=sbp_... tool/supabase/setup.sh <project-ref>
#   SUPABASE_ACCESS_TOKEN=sbp_... tool/supabase/setup.sh --create ChronoFold \
#       --org-id <org-id> --region eu-central-1
#
# What it does:
#   1. logs the Supabase CLI in with the access token;
#   2. creates the project (with --create) or links an existing one;
#   3. reads the project URL and API keys;
#   4. applies supabase/migrations (through the CLI when a database password
#      is known, otherwise through the Management API, which needs no
#      password);
#   5. writes ${XDG_CONFIG_HOME:-$HOME/.config}/pandacode/supabase.env
#      (mode 600) and verifies the result.
#
# Flags:
#   --create <name>       Create a new project instead of linking one.
#   --org-id <id>         Organisation for --create (default: your only org).
#   --region <region>     Region for --create (default: eu-central-1).
#   --project-ref <ref>   Existing project to link (same as the positional).
#   --db-password <pass>  Database password, used for `supabase db push`.
#   --env-file <path>     Where to write the credentials file.
#   --token <token>       Access token (or set SUPABASE_ACCESS_TOKEN).
#
# The access token needs the "projects:write" and "secrets:write" scopes; the
# default token created at https://supabase.com/dashboard/account/tokens has
# all scopes your account has.
set -euo pipefail

_repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$_repo_root"

die() { printf 'setup: %s\n' "$*" >&2; exit 1; }
step() { printf '\n==> %s\n' "$*"; }
note() { printf '    %s\n' "$*"; }

usage() { sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; }

token=${SUPABASE_ACCESS_TOKEN:-}
ref=""
create_name=""
org=""
region="eu-central-1"
db_password=${SUPABASE_DB_PASSWORD:-}
env_file=${SUPABASE_ENV_FILE:-${XDG_CONFIG_HOME:-$HOME/.config}/pandacode/supabase.env}
management_url=${SUPABASE_MANAGEMENT_URL:-https://api.supabase.com}

while (($#)); do
  case $1 in
    --create) create_name=${2:?--create needs a name}; shift 2 ;;
    --org-id) org=${2:?--org-id needs a value}; shift 2 ;;
    --region) region=${2:?--region needs a value}; shift 2 ;;
    --project-ref) ref=${2:?--project-ref needs a value}; shift 2 ;;
    --db-password) db_password=${2:?--db-password needs a value}; shift 2 ;;
    --env-file) env_file=${2:?--env-file needs a path}; shift 2 ;;
    --token) token=${2:?--token needs a value}; shift 2 ;;
    -h | --help) usage; exit 0 ;;
    -*) die "unknown flag: $1 (try --help)" ;;
    *) ref=$1; shift ;;
  esac
done

[[ -n $create_name || -n $ref ]] || {
  usage >&2
  die "pass a project ref, or --create <name>"
}
[[ -n $create_name && -n $ref ]] && die "pass either a project ref or --create, not both"
[[ -n $token ]] || die "set SUPABASE_ACCESS_TOKEN (create one at https://supabase.com/dashboard/account/tokens)"

for cmd in supabase curl jq; do
  command -v "$cmd" >/dev/null || die "$cmd is not installed"
done

step "Logging the Supabase CLI in"
supabase login --token "$token" --name pandacode >/dev/null ||
  die "supabase login failed; check that the token is valid"
note "CLI authenticated"

if [[ -n $create_name ]]; then
  if [[ -z $org ]]; then
    orgs=$(supabase orgs list --output json)
    count=$(jq 'length' <<<"$orgs")
    [[ $count == 1 ]] || {
      jq -r '.[] | "    \(.id)  \(.name)"' <<<"$orgs" >&2
      die "$count organisations; pick one with --org-id"
    }
    org=$(jq -r '.[0].id' <<<"$orgs")
  fi
  if [[ -z $db_password ]]; then
    db_password=$(openssl rand -base64 24 | tr -d '/+=' | cut -c1-24)
    note "Generated a database password; it is saved in $env_file"
  fi
  step "Creating project '$create_name' in $region"
  created=$(supabase projects create "$create_name" \
    --org-id "$org" --region "$region" --db-password "$db_password" \
    --output json 2>&1) || die "project creation failed: $created"
  # The CLI prints progress lines before the JSON body.
  created_json=$(sed -n '/^{/,$p' <<<"$created")
  ref=$(jq -r '.ref // .id // empty' <<<"$created_json" 2>/dev/null || true)
  [[ -n $ref ]] || die "could not read the new project ref from: $created"
  note "project ref $ref"

  step "Waiting for the project to become healthy"
  for _ in $(seq 1 60); do
    status=$(supabase projects list --output json |
      jq -r --arg ref "$ref" '.[] | select(.ref == $ref) | .status' 2>/dev/null || true)
    [[ $status == ACTIVE_HEALTHY ]] && break
    sleep 10
  done
  [[ ${status:-} == ACTIVE_HEALTHY ]] ||
    die "project did not become healthy (last status: ${status:-unknown})"
  note "healthy"
fi

step "Linking project $ref"
link_args=(--project-ref "$ref")
[[ -n $db_password ]] && link_args+=(--password "$db_password")
supabase link "${link_args[@]}" >/dev/null || die "supabase link failed"
note "linked"

step "Reading the project's API keys"
keys=$(supabase projects api-keys --project-ref "$ref" --reveal --output json) ||
  die "could not read API keys"
anon_key=$(jq -r '
  [.[] | select((.name // "") == "anon" or (.type // "") == "publishable")][0].api_key
  // [.[] | select((.api_key // "") | startswith("sb_publishable_"))][0].api_key
  // empty' <<<"$keys")
secret_key=$(jq -r '
  [.[] | select((.name // "") == "service_role" or (.type // "") == "secret")][0].api_key
  // [.[] | select((.api_key // "") | startswith("sb_secret_"))][0].api_key
  // empty' <<<"$keys")
[[ -n $anon_key && -n $secret_key ]] ||
  die "could not find both an anon and a secret key in the CLI output"
note "anon key and secret key found"

project_url=${SUPABASE_PROJECT_URL:-https://$ref.supabase.co}

step "Applying database migrations"
if [[ -n $db_password ]]; then
  supabase db push --linked --include-all --yes --password "$db_password" ||
    die "supabase db push failed"
  note "applied with supabase db push"
else
  # No database password: use the Management API's SQL endpoint, which
  # authenticates with the access token. The migration is recorded in
  # supabase_migrations.schema_migrations so a later `supabase db push`
  # treats it as applied.
  mgmt_sql() {
    curl -sS --fail-with-body -X POST \
      "$management_url/v1/projects/$ref/database/query" \
      -H "Authorization: Bearer $token" \
      -H 'Content-Type: application/json' \
      -d "$(jq -nc --arg q "$1" '{query: $q}')"
  }
  mgmt_sql 'create schema if not exists supabase_migrations;
    create table if not exists supabase_migrations.schema_migrations (
      version text primary key, statements text[], name text
    );' >/dev/null || die "could not create the migration history table"

  shopt -s nullglob
  files=(supabase/migrations/*.sql)
  shopt -u nullglob
  ((${#files[@]})) || die "no migrations in supabase/migrations"
  for file in "${files[@]}"; do
    base=$(basename "$file" .sql)
    version=${base%%_*}
    name=${base#*_}
    applied=$(mgmt_sql "select count(*)::int as n
      from supabase_migrations.schema_migrations where version = '$version'" |
      jq -r '.[0].n // 0' 2>/dev/null || echo 0)
    if [[ $applied != 0 ]]; then
      note "skip $base (already applied)"
      continue
    fi
    mgmt_sql "$(cat "$file")" >/dev/null || die "migration $base failed"
    mgmt_sql "insert into supabase_migrations.schema_migrations (version, name)
      values ('$version', '$name') on conflict (version) do nothing" >/dev/null ||
      die "could not record migration $base"
    note "applied $base"
  done
fi

step "Saving credentials to $env_file"
mkdir -p "$(dirname "$env_file")"
umask 077
{
  echo "# Supabase credentials for PandaCode. Generated by tool/supabase/setup.sh."
  echo "# Do not commit. Revoke the access token at"
  echo "# https://supabase.com/dashboard/account/tokens if this file leaks."
  printf 'SUPABASE_ACCESS_TOKEN=%q\n' "$token"
  printf 'SUPABASE_PROJECT_REF=%q\n' "$ref"
  printf 'SUPABASE_URL=%q\n' "$project_url"
  printf 'SUPABASE_ANON_KEY=%q\n' "$anon_key"
  printf 'SUPABASE_SECRET_KEY=%q\n' "$secret_key"
  [[ -n $db_password ]] && printf 'SUPABASE_DB_PASSWORD=%q\n' "$db_password"
} >"$env_file"
chmod 600 "$env_file"
note "mode 600, outside the repository"

step "Verifying"
SUPABASE_ENV_FILE=$env_file "$_repo_root/tool/supabase/verify.sh" ||
  die "credentials were saved, but verification failed (see above)"

printf '\nDone. PandaCode can now reach project %s.\n' "$ref"
printf 'Next: tool/supabase/ingest.sh ~/Documents/Recipes\n'
