Candidate: Ruel Ryan Rosal
Hours spent: 4

# Stall Watch — design note

## Problem

Builders pick finishes for their homes in the app, start strong, then go quiet. Reverie3D staff
only notice when they happen to open the project, usually after the selection due date has
passed, which holds up ordering and construction. The system should notice for them and tell
the right people inside the app.

## Goals

- Builders see and edit only their own org's projects and selections. Staff see everything.
- A scheduled detector flags projects that are *stalled* (selection phase, not archived, at
  least one empty slot, no builder activity for 5+ days) and creates one in-app alert per admin
  of that builder org. Running it twice never duplicates an alert; a new stall after new
  activity produces a new alert.
- Every detector run is recorded, including failures with their error message.
- The database is the security wall. RLS is enabled and forced on every exposed table; the
  app never holds the service-role key.

## Non-goals

- Email, SMS or any outside notification. Sign-up, password reset, invites.
- Org, member or slot management screens. Styling, mobile layout, lock_version conflict UI.

## Data and permissions (summary; the migrations are the source of truth)

- `public.orgs` (org_type `staff | builder`), `public.users` (mirror of `auth.users`, kept by
  a trigger), `public.memberships` (user, org, role `admin | member`). Identity is never written
  by the app directly.
- `builder.projects`, `builder.project_slots`, `builder.selections` (one current pick per
  slot), `builder.selection_history` (append-only, written only by a trigger, with
  `actor_kind` derived from the caller's membership), `builder.alerts` (one row per
  recipient; only the recipient can read it or mark it read).
- Detector tables, staff-only: `builder.detector_runs` (the run log) and
  `builder.stall_episodes` (one row per distinct stall; this is what prevents duplicates).
- `private.current_user_org_ids()` and `private.is_staff()` are the only RLS helpers. Every
  org-owned table uses `org_id = any (private.current_user_org_ids()) or private.is_staff()`;
  alerts use `user_id = auth.uid()`; detector tables use `private.is_staff()`.
- Child rows carry `org_id` and a composite foreign key `(parent_id, org_id)` so a row can't
  be attached to another org's parent.

## Decisions

1. **org_type is `staff | builder`.** The brief's data-model table says `staff | admin`, but
   the glossary and the provided seed use `builder`, and the seed must load unchanged.
2. **Detector runs in the database with pg_cron (brief option A).** A SECURITY DEFINER
   function `private.run_stall_detector()` does the work, is revoked from `anon` and
   `authenticated`, and is called by a pg_cron job and by `builder.run_stall_detector_now()`,
   whose first line checks `private.is_staff()`. Rejected: Vercel Cron (option B) needs a
   shared secret, a hash table and a hand-inserted row; more parts for the same result.
   What this gives up: the schedule lives in the database, so changing it is a migration, and
   a long-running detector would hold a database connection rather than a serverless one.
3. **Duplicate prevention is a row, not a time window.** `stall_episodes` has
   `unique (project_id, quiet_since)`. *Quiet since* is the later of the last builder
   activity and `selection_phase_started_at`; for a given stall it never changes, so a second
   run hits the unique index and creates nothing. New builder activity moves `quiet_since`
   forward, which is a new episode and a new alert. Overlapping runs are additionally
   serialised with an advisory lock.
4. **The stall rule lives in one view**, `builder.v_projects_overview`, read live by
   `/projects` (badge) and by the detector, so the badge and the alert can't disagree.
5. **A failed run stays visible.** The run row is inserted before the work; the work runs in a
   nested block whose exception handler rolls the work back and records `failed` plus the
   error message on the surviving run row.
6. **Staff activity is not builder activity.** `actor_kind` is set by the history trigger from
   the caller's membership, never from a value the app sends; a change with no signed-in user
   is recorded as staff.

## What I'd build next (Part 3)

**Late-change alert.** When a builder (not staff) sets, changes or clears a selection on a
project that is already in revision, every staff user gets an in-app alert: *"Builder A changed
Kitchen – Countertop on Lot 12 after revision."*

- **Why it's the most valuable next step.** Once a project is in revision, staff have started
  ordering against the selections. A late change is the one event that is both expensive and
  invisible: the stall detector looks for silence, not for the wrong kind of activity. Staff
  today would only notice by re-opening the project. It also reuses everything Part 2 built
  (history with `actor_kind`, alerts with a dedupe key), so it is a small change with a large
  payoff for the people who order materials.
- **How I'd build it.** A database trigger on `builder.selection_history` (after insert). The
  history row already says who acted and what changed, so the trigger needs no new tables: it
  reads the slot's project, returns early unless `actor_kind = 'builder'` and
  `status = 'revision'`, and inserts one alert per member of the staff org with
  `kind = 'late_change'` and `source_key = history.id`. The unique
  `(user_id, kind, source_key)` on alerts makes it impossible to alert twice for one change.
  The function is SECURITY DEFINER because `authenticated` cannot insert alerts, and it is
  revoked from every API role.
- **What I'd leave out.** Any UI beyond the existing /alerts list; staff-side acknowledgement
  or "accept the change" workflow; alerting builders about their own change; batching several
  changes into one alert. All of those are judgement calls that need a conversation with the
  ordering team first.

**I built it as the bonus:** migration `20261020131000_late_change_alert_trigger.sql`, covered
by `supabase/tests/04_late_change.test.sql` (one alert per staff user, no duplicates on a no-op
update, clears included, staff changes and non-revision projects excluded).

## The stall detector, in one place

- **Where it runs:** inside Postgres. `private.run_stall_detector(p_trigger_kind, p_triggered_by)`
  is SECURITY DEFINER (owner `postgres`), pinned `search_path`, and revoked from `public`,
  `anon` **and** `authenticated`, so nothing over the API can reach it. pg_cron calls it at
  09:00 UTC daily (`stall-detector-nightly`). No Vercel route, no secret, no service-role key.
- **How staff run it:** `builder.run_stall_detector_now()`, also SECURITY DEFINER, whose first
  statement is `if not private.is_staff() then raise exception ... 42501`. It is the only
  function in `builder` that `authenticated` may execute, and the Security Advisor's one
  warning is exactly that: a definer function callable by signed-in users. That is the
  brief's pattern (grant + in-body check), and the test suite proves a builder is rejected.
- **What stops duplicates:** `builder.stall_episodes` with `unique (project_id, quiet_since)`.
  The run also takes `pg_advisory_xact_lock` so two overlapping runs never both do the work.
  `alerts` are additionally unique on `(user_id, kind, source_key)` with the episode id as the
  key, so even a bug in the episode logic could not double-alert a person.
- **What a run records:** `builder.detector_runs` with started/finished (wall clock), trigger
  kind, who triggered it, how many projects were stalled, how many were new, how many alerts
  were created, and on failure the error text. The run row is written before the work and the
  work runs in a nested block, so a failure leaves the row (as `failed`) and nothing else.
- **What I gave up:** changing the schedule is a migration, not a dashboard click; a very long
  run would hold a database connection; and because staff activity does not move
  `quiet_since`, a stall that staff "fix" by filling slots themselves does not restart the
  clock. The last one is the rule as written and I'd rather have it visible here than hidden.

## Verify, don't assume: what I checked

- **pgTAP, 113 assertions** (`supabase/tests/`), locally and in CI on a fresh Postgres built
  from the migrations and seed: schema-rule hygiene read from the catalog; Builder A trying
  to read and write Builder B's data (blocked by RLS and by the composite foreign key); the
  detector on the seed scenarios (Lot 12, Unit 4B, Unit 7C flagged; Ana alerted, Mia not;
  a second run creates nothing; staff activity ignored; a re-stall after new activity is a
  new alert; a failed run is recorded as failed); the late-change alert; constraints and the
  5-day boundary. The same catalog checks were run on the hosted project after the push.
- **Playwright, 8 scenarios** (`e2e/`), in CI on every PR: the brief's story as Ana, staff
  and Bruno, from the signed-out redirect through two detector runs (3/3/3 then 3/0/0) to
  mark-as-read and a selection clearing the badge. Walked by hand first, then automated.
- `supabase db lint` is clean. Security Advisor: 0 errors, 1 warning (the staff RPC, above).
  Performance Advisor items were fixed in two follow-up migrations; "unused index" notes are
  expected on a day-old database.

## Rules bent

- **`org_type` is `staff | builder`,** not `staff | admin` as the data-model table says
  (glossary and seed say `builder`; told Jeff on Oct 20).
- **Two migrations were added after the first push** to the hosted project (the advisor
  fixes) instead of amending the originals, which is the rule; noting it because it means the
  policy text in `20261020130200`, `…130500` and `…130700` is superseded for five policies.
- **`supabase config push`** was used to expose the `builder` schema. It also pushed the
  local `[auth]` defaults from `config.toml` (site URL, email confirmation settings) to the
  hosted project. None of them matter for email-and-password sign-in with pre-created users,
  but it is a dashboard-level change made by a tool, so it is listed in SETUP.md.
- **`selected_by` is set by the app and checked by the policy** (`= auth.uid()`), rather
  than stamped by a trigger. Same guarantee, less machinery; a trigger would be the next step
  if other writers appeared.
- **A small visual pass was done last,** after Parts 1–3 were finished and verified, even
  though the brief says looks are not graded. It adds no dependencies or design system: one
  typeface, a handful of CSS tokens, and plain-English copy. It is one PR and can be
  reverted without touching anything else.
- **Playwright was added after the first submission-ready state,** not during the 6–8 hour
  build. The brief's story was first walked by hand in a real browser (recorded in the PR
  descriptions); the Playwright suite in `e2e/` now automates that walk against the local
  stack and runs in CI, so it stays true as the app changes.

## Environments

One Supabase project. How I'd split it is in SETUP.md under *Environments*.
