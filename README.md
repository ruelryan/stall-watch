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
| `npm run lint`, `npm run typecheck`, `npm run build` | What CI runs |

## Repo map

```
app/                    Next.js routes: /login, /projects, /projects/[id], /alerts, /detector
lib/supabase/           Supabase clients (browser, server, proxy) and generated types
supabase/config.toml    Local stack config, including the exposed API schemas
supabase/migrations/    The entire schema. The database is rebuilt from these alone.
supabase/seed.sql       Sample data (provided with the brief, unchanged)
supabase/link-test-users.sql  Links the test users to their orgs (provided)
supabase/tests/         pgTAP tests: RLS hygiene, tenant isolation, detector behaviour
.github/workflows/      CI
```
