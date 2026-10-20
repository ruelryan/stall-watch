# Stall Watch

A small app for Reverie3D's builders to pick finishes for their projects, with a scheduled
**stall detector** that notices when a project has gone quiet and alerts the right people
inside the app.

Built for the Reverie3D Automation Engineer trial. The design note is [DESIGN.md](DESIGN.md),
the platform setup is [SETUP.md](SETUP.md), and the migration ledger is
[MIGRATIONS.md](MIGRATIONS.md).

## Stack

- Next.js (App Router, TypeScript) on Vercel
- Supabase (Postgres + Auth); the detector runs inside Postgres with pg_cron
- GitHub Actions for CI (lint, typecheck, build, and pgTAP tests against a fresh database)

## Run it locally

Requires Node 22+ and Docker (for the local Supabase stack).

```bash
npm install
npm run db:start          # starts local Supabase, applies migrations + supabase/seed.sql
cp .env.example .env.local
# paste the API URL and anon key printed by `npx supabase status` into .env.local
npm run dev               # http://localhost:3000
```

To create local test users, open Studio (http://127.0.0.1:54323) → Authentication → Add user
(tick "Auto Confirm User") for the emails listed in `supabase/link-test-users.sql`, then run
that file in Studio's SQL editor.

Useful scripts:

| Script | What it does |
| --- | --- |
| `npm run db:reset` | Drop and rebuild the local database from migrations + seed |
| `npm run db:test` | Run the pgTAP tests in `supabase/tests/` |
| `npm run db:types` | Regenerate `lib/supabase/database.types.ts` from the local schema |
| `npm run db:lint` | `plpgsql_check` over every function in the local database |
| `npm run test:e2e` | Playwright: the brief's story in a real browser against the local stack |
| `npm run lint`, `npm run typecheck`, `npm run build` | What CI runs |

## Tests

- **pgTAP** (`supabase/tests/`, 113 assertions): schema-rule hygiene read from the catalog,
  Builder A trying to read and write Builder B's data, the detector on the seed scenarios
  (no duplicates, re-stall after new activity, failed runs recorded), the late-change alert,
  and constraints and edges (check constraints, the 5-day boundary, members vs admins,
  users with no membership, anon). Every file resets to seed-only state and rolls back.
- **Playwright** (`e2e/`, 8 scenarios): sign-in and redirects, Ana's isolation, staff running
  the detector twice (3/3/3 then 3/0/0), Bruno's alerts and mark-as-read, Mia getting none,
  Ana's selection clearing the badge, an empty product refused. `e2e/global-setup.ts`
  creates the four local test users through the local Auth admin API, links them with the
  provided `link-test-users.sql`, and removes anything a previous run left behind.
- **CI** runs all of it on every PR, plus `supabase db lint` and a gitleaks scan of the
  whole history.

## Repo map

```
app/                    Next.js routes: /login, /projects, /projects/[id], /alerts, /detector
lib/supabase/           Supabase clients (browser, server, proxy) and generated types
supabase/config.toml    Local stack config, including the exposed API schemas
supabase/migrations/    The entire schema. The database is rebuilt from these alone.
supabase/seed.sql       Sample data (provided with the brief, unchanged)
supabase/link-test-users.sql  Links the test users to their orgs (provided)
supabase/tests/         pgTAP tests: RLS hygiene, tenant isolation, detector behaviour, edges
e2e/                    Playwright tests and their setup (local stack only)
.github/workflows/      CI
```
