#!/usr/bin/env bash
# Uploads the weekly meal-kit PDFs with the credentials from
# tool/supabase/setup.sh.
#
#   tool/supabase/ingest.sh ~/Documents/Recipes
#   tool/supabase/ingest.sh ~/Documents/Recipes --dry-run
#
# Every other argument is passed through to tool/menu_kit_ingest.dart.
set -euo pipefail

_repo_root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
# shellcheck source=env.sh
. "$_repo_root/tool/supabase/env.sh"

exec dart run "$_repo_root/tool/menu_kit_ingest.dart" "$@"
