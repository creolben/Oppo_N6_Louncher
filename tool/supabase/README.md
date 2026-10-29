# Supabase access for PandaCode

The recipe ingest ([`tool/menu_kit_ingest.dart`](../menu_kit_ingest.dart)) and
the schema in [`supabase/`](../../supabase) talk to a hosted Supabase project.
These scripts keep that connection in one place and outside the repository.

## One-time setup

Create a personal access token at
<https://supabase.com/dashboard/account/tokens> (name it `PandaCode`), then
either link an existing project:

```bash
SUPABASE_ACCESS_TOKEN=sbp_... tool/supabase/setup.sh <project-ref>
```

or create one:

```bash
SUPABASE_ACCESS_TOKEN=sbp_... tool/supabase/setup.sh --create ChronoFold \
  --org-id <org-id> --region eu-central-1
```

`setup.sh` logs the CLI in, links the project, applies
`supabase/migrations/`, then writes
`${XDG_CONFIG_HOME:-$HOME/.config}/pandacode/supabase.env` with mode `600`:

| Variable | Purpose |
| --- | --- |
| `SUPABASE_ACCESS_TOKEN` | Management API and CLI login (project create, SQL, keys) |
| `SUPABASE_PROJECT_REF` | Project ref |
| `SUPABASE_URL` | `https://<ref>.supabase.co` |
| `SUPABASE_ANON_KEY` | Publishable key, for a future signed-in app client |
| `SUPABASE_SECRET_KEY` | Secret key, for ingest and admin reads |
| `SUPABASE_DB_PASSWORD` | Only when one was supplied or generated |
When no database password is available, migrations are applied through the
Management API's SQL endpoint and recorded in
`supabase_migrations.schema_migrations`, so a later `supabase db push` does
not repeat them.

## Everyday use

```bash
source tool/supabase/env.sh          # export the credentials
tool/supabase/ingest.sh ~/Documents/Recipes
tool/supabase/verify.sh              # tables, bucket, key permissions
tool/supabase/sql.sh "select title, week_start from menu_kits"
```

`ingest.sh` passes its arguments to `menu_kit_ingest.dart`, so `--dry-run`
works too. Re-running is safe: a week is replaced, not duplicated.

## Revoking access

Delete the file and revoke the token:

```bash
rm ~/.config/pandacode/supabase.env
supabase logout
```

Then remove the token from the dashboard. Rotating just the secret key means
updating `SUPABASE_SECRET_KEY` in the credentials file.
