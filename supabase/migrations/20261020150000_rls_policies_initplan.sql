-- Evaluate auth.uid() once per statement in the per-user policies.
--
-- WHY. The Supabase Performance Advisor flagged "Auth RLS Initialization Plan" on
-- public.users, builder.selections and builder.alerts: a bare auth.uid() in a policy is
-- re-evaluated for every row. Wrapping it as (select auth.uid()) makes it an InitPlan that
-- Postgres computes once per statement. The predicates are unchanged; only their form is.
-- The org-scoped policies are left exactly as the schema rules spell them (they call the STABLE
-- helpers, which the advisor did not flag).
--
-- WHAT.
--   1. p_users_select — recreated with (select auth.uid()).
--   2. p_selections_insert, p_selections_update — same change on the selected_by check.
--   3. p_alerts_select, p_alerts_update — same change on user_id.
--
-- NOT SELF-CONTAINED. Nothing.
--
-- ROLLBACK: recreate the five policies with bare auth.uid(), as in
--   20261020130200_rls_helpers_and_identity_policies.sql,
--   20261020130500_selections_and_history.sql and 20261020130700_alerts.sql.

drop policy if exists p_users_select on public.users;
create policy p_users_select on public.users
  for select to authenticated
  using (id = (select auth.uid()) or private.is_staff());

drop policy if exists p_selections_insert on builder.selections;
create policy p_selections_insert on builder.selections
  for insert to authenticated
  with check ((org_id = any (private.current_user_org_ids()) or private.is_staff())
              and selected_by = (select auth.uid()));

drop policy if exists p_selections_update on builder.selections;
create policy p_selections_update on builder.selections
  for update to authenticated
  using      (org_id = any (private.current_user_org_ids()) or private.is_staff())
  with check ((org_id = any (private.current_user_org_ids()) or private.is_staff())
              and selected_by = (select auth.uid()));

drop policy if exists p_alerts_select on builder.alerts;
create policy p_alerts_select on builder.alerts
  for select to authenticated
  using (user_id = (select auth.uid()));

drop policy if exists p_alerts_update on builder.alerts;
create policy p_alerts_update on builder.alerts
  for update to authenticated
  using      (user_id = (select auth.uid()))
  with check (user_id = (select auth.uid()));
