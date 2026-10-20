# SETUP

How the platforms were set up, written for a teammate rebuilding the environment from nothing.
(Filled in as each platform is set up; the final version matches the commands actually run.)

## Supabase

_TBD_

## Vercel

_TBD_

## GitHub

CI (`.github/workflows/ci.yml`) runs on every pull request and on pushes to `main`:

1. `app` job: `npm ci`, `npm run lint`, `npm run typecheck`, `npm run build`.
2. `db` job: `supabase start` on a fresh local Postgres (applies every migration and
   `seed.sql`), then `supabase test db` runs the pgTAP tests in `supabase/tests/`.

A red PR is not merged.

## Environments

_TBD_
