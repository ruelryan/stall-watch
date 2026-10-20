# SETUP

How Supabase, Vercel and GitHub were set up, written for a teammate rebuilding the environment
from nothing. These are the commands that were actually run.

## Order of operations

1. Migrations (`supabase db push`)
2. `seed.sql` (`--include-seed` on the same push, or paste it into the SQL editor)
3. Create the test users in the dashboard
4. `link-test-users.sql` in the SQL editor
5. Expose the `builder` schema (`supabase config push`, or the dashboard setting)
6. Vercel environment variables, then deploy

Steps 1–2 must come before step 5: PostgREST refuses to start when an exposed schema does
not exist yet.

## Supabase

### Local (what CI and local development use)

```bash
npm install
npx supabase start          # pulls images, applies supabase/migrations/* and supabase/seed.sql
npx supabase test db        # pgTAP tests in supabase/tests/
npx supabase db reset       # rebuild from scratch after changing a migration
```

`supabase/config.toml` holds the local settings. The only non-default is
`[api] schemas = ["public", "graphql_public", "builder"]`.

Local test users: `supabase start` prints the local URL and keys. Create the four users in
local Studio (http://127.0.0.1:54323 → Authentication → Add user, Auto Confirm) or with the
local Auth admin API, then run `supabase/link-test-users.sql` against the local database.

### Hosted project

Created in the dashboard (free tier). Nothing else was done in the dashboard except the
items listed under "Dashboard settings" below.

```bash
npx supabase login                          # opens the browser once
npx supabase link --project-ref <ref>       # prompts for the database password, keeps it in the OS keyring
npx supabase db push --include-seed         # applies every migration, then seed.sql
npx supabase config push                    # pushes [api].schemas from config.toml (exposes builder)
```

Then:

1. In the dashboard, **Authentication → Users → Add user** (tick *Auto Confirm User*), with
   passwords that are not committed anywhere:
   - `staff@stallwatch.test`
   - `ana@builder-a.test`
   - `bruno@builder-b.test`
   - `mia@builder-a.test` (Builder A member; useful to check that only admins get stall alerts)
2. Run `supabase/link-test-users.sql` as the database owner. Either paste it into the
   dashboard's **SQL Editor**, or, as was done here, pipe it through `psql` over the session
   pooler (`supabase link` prints the pooler URL; the password is the one chosen at project
   creation):

   ```bash
   psql "postgresql://postgres.<ref>@aws-0-<region>.pooler.supabase.com:5432/postgres" \
     -v ON_ERROR_STOP=1 -f supabase/link-test-users.sql
   ```

   It stops with a clear message if the auth-mirror trigger has not copied the users into
   `public.users`. It is safe to run twice.

3. Optional smoke test of the detector from SQL (what pg_cron does nightly):
   `select private.run_stall_detector('manual', null);` then look at `builder.detector_runs`.
   On the fresh seed the first run flags 3 projects and creates 3 alerts; a second run creates
   nothing.

### Schemas exposed through the Data API

`public` and `builder` (and the default `graphql_public`). `private` is **not** exposed. Set
by `supabase config push` from `config.toml`; equivalent to Project Settings → Data API →
Exposed schemas.

### Extensions

- `pg_cron` — enabled by migration `20261020130900_pg_cron_schedule.sql`
  (`create extension if not exists pg_cron`). It schedules `stall-detector-nightly` at
  09:00 UTC. `cron.job` shows the job; `cron.job_run_details` shows each execution;
  `builder.detector_runs` is the app-level log staff see on /detector.
- `pgtap` — only in the local/CI database, created by the test files themselves.

### Dashboard settings changed

- Exposed schemas: `builder` added (via `supabase config push`).
- `supabase config push` also pushed the `[auth]` block of the local `config.toml` (site URL,
  email confirmation and password settings). None of it affects email + password sign-in
  with pre-created users; listed here because it is a dashboard-level change made by a tool.
- Test users created (above). Their passwords exist only in the dashboard and in the
  one-time-secret links sent to the reviewers.

No schema change was ever made in the dashboard. No service-role key is used anywhere.

### Rebuild check

A fresh project plus the commands above reproduces the whole database. Locally,
`npx supabase db reset && npx supabase test db` is the same check; CI runs it on every PR.

## Vercel

Project created with `vercel link --project stall-watch` and connected to the GitHub repo with
`vercel git connect`, so `main` deploys to production and every PR gets a preview deployment
(the Vercel check appears on each PR). The first production deploy was triggered with
`vercel deploy --prod`; later ones come from merges to `main`.

Production URL: https://stall-watch-ecru.vercel.app

Environment variables were set with
`vercel env add <NAME> --environment <env> --type config --value <value>` for each of the
three environments (the CLI insists on an explicit `--type config` for a `NEXT_PUBLIC_` value
that looks like a key, which is the point: the anon key is public by design).

| Variable | Environments | Exposed to the browser? | What it is |
| --- | --- | --- | --- |
| `NEXT_PUBLIC_SUPABASE_URL` | Production, Preview, Development | Yes | The hosted project's API URL |
| `NEXT_PUBLIC_SUPABASE_ANON_KEY` | Production, Preview, Development | Yes | The anon (publishable) key; grants only what RLS allows |

That is the whole list. There is deliberately no service-role key, no database password and
no cron secret in Vercel: the detector runs inside Postgres via pg_cron, so nothing on Vercel
needs to be scheduled or protected.

Preview deployments point at the same Supabase project as production (one project for this
trial; see *Environments*).

## GitHub

Public repo. CI (`.github/workflows/ci.yml`) runs on every pull request and on pushes to
`main`:

1. `app` job: `npm ci`, `npm run lint`, `npm run typecheck`, `npm run build`.
2. `db` job: `supabase start` on a fresh local Postgres (applies every migration and
   `seed.sql`), `supabase db lint`, then `supabase test db` runs the pgTAP tests in
   `supabase/tests/`.
3. `e2e` job: the full local stack (Postgres, Auth, PostgREST), `npm run build`, then
   Playwright walks the brief's story in Chromium. The app is pointed at the local stack by
   reading `supabase status` into `NEXT_PUBLIC_*`; no hosted project is touched.
4. `secrets` job: gitleaks over the whole git history.

Branches are merged through pull requests with merge commits. A red PR is not merged.

## Environments

One Supabase project was used for this trial. To split it into Sandbox and Production I would
create a second project, link each environment with its own project ref (`supabase link`
in CI with `SUPABASE_ACCESS_TOKEN` and `SUPABASE_DB_PASSWORD` as secrets), and have the
pipeline run `supabase db push` against Sandbox on every merge to `main` and against
Production on a tagged release (or a manual approval step). Migrations only ever move
forward, Sandbox first; Vercel Preview deployments point at Sandbox and Production at
Production through per-environment `NEXT_PUBLIC_*` variables.
