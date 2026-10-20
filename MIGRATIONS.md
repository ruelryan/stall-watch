# Migrations ledger

One row per file in `supabase/migrations/`, in order. The files are the source of truth; this
table is the index. Never edit an applied migration; add a new one.

| File | What it does |
| --- | --- |
| `20261020130000_private_schema_and_updated_at.sql` | `private` schema and the shared `private.set_updated_at()` trigger (stamps `updated_at`, bumps `lock_version`) |
| `20261020130100_identity_tables.sql` | `public.orgs`, `public.users`, `public.memberships`; RLS enabled + forced; write privileges revoked from the API roles |
| `20261020130200_rls_helpers_and_identity_policies.sql` | `private.current_user_org_ids()`, `private.is_staff()`; select policies on the three identity tables |
| `20261020130300_auth_mirror_trigger.sql` | `trg_auth_user_mirror` on `auth.users` copies users into `public.users` |
| `20261020130400_builder_projects_and_slots.sql` | `builder` schema; `builder.projects`, `builder.project_slots`; org-scoped select policies, staff-only project update |
| `20261020130500_selections_and_history.sql` | `builder.selections`, append-only `builder.selection_history`, the history trigger that derives `actor_kind` from the caller's membership |
| `20261020130600_projects_overview_view.sql` | `builder.v_projects_overview` (security_invoker): slot counts, last builder activity, `quiet_since`, `is_stalled` |
| `20261020130700_alerts.sql` | `builder.alerts`, recipient-only policies, `update (read_at)` column grant, unique `(user_id, kind, source_key)` |
