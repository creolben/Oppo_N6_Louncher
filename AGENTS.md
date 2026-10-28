# Agent notes

## Supabase

Credentials for the hosted Supabase project are **not** in this repository.
They live in `${XDG_CONFIG_HOME:-$HOME/.config}/pandacode/supabase.env`
(mode 600), written by `tool/supabase/setup.sh`. Do not copy them into the
repo, logs, commits or test fixtures.

Load them before any Supabase work:

```bash
source tool/supabase/env.sh
```

Available once loaded: `SUPABASE_ACCESS_TOKEN`, `SUPABASE_PROJECT_REF`,
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SECRET_KEY`, and
`SUPABASE_DB_PASSWORD` when known.

Helpers:

- `tool/supabase/verify.sh` — checks auth, tables and the private bucket.
- `tool/supabase/ingest.sh <pdf-dir>` — uploads the weekly meal-kit PDFs.
- `tool/supabase/sql.sh "<sql>"` — runs SQL through the Management API.

Schema changes go in `supabase/migrations/`, applied with
`supabase db push` (with a database password) or `tool/supabase/setup.sh`
(Management API fallback). See `tool/supabase/README.md` for the full flow.
