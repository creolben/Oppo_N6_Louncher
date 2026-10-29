#!/usr/bin/env bash
# Loads the Supabase credentials written by tool/supabase/setup.sh.
#
#   source tool/supabase/env.sh          # in a shell
#   tool/supabase/ingest.sh <pdf-dir>    # or use the wrapper
#
# The file lives outside the repository and is readable only by you:
#   ${XDG_CONFIG_HOME:-$HOME/.config}/pandacode/supabase.env
#
# Override its location with SUPABASE_ENV_FILE.

: "${XDG_CONFIG_HOME:=$HOME/.config}"
_supabase_env_file="${SUPABASE_ENV_FILE:-$XDG_CONFIG_HOME/pandacode/supabase.env}"

if [ ! -f "$_supabase_env_file" ]; then
  echo "No Supabase credentials at $_supabase_env_file" >&2
  echo "Run tool/supabase/setup.sh first (see tool/supabase/README.md)." >&2
  return 1 2>/dev/null || exit 1
fi

set -a
# shellcheck disable=SC1090
. "$_supabase_env_file"
set +a

unset _supabase_env_file
