Candidate: Ruel Ryan Rosal
Hours spent: (filled in at submission)

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

Late-change alert. (Expanded at the end.)

## Rules bent

None yet. (Updated at the end.)
