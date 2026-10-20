-- Constraints, boundaries and the less obvious paths: what the database refuses on its own,
-- and the edges of the stall rule.
begin;
create extension if not exists pgtap with schema extensions;
select plan(24);

-- ── fixtures ────────────────────────────────────────────────────────────────────────────────
-- Start from the seed alone: a local database may also hold real test users, their
-- memberships, and rows left by the end-to-end suite. All of this rolls back with the test.
delete from public.memberships;
delete from builder.alerts;
delete from builder.stall_episodes;
delete from builder.detector_runs;
alter table builder.selections disable trigger trg_selections_history;
delete from builder.selections where selected_by is not null;
alter table builder.selections enable trigger trg_selections_history;
alter table builder.selection_history disable trigger trg_selection_history_append_only;
delete from builder.selection_history where changed_by is not null;
alter table builder.selection_history enable trigger trg_selection_history_append_only;

insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000ff01', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't-staff@stallwatch.test', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't-ana@builder-a.test',   now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-00000000aa02', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't-mia@builder-a.test',   now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-00000000cc01', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't-nobody@example.test',  now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());
insert into public.memberships (user_id, org_id, role) values
  ('00000000-0000-0000-0000-00000000ff01', '00000000-0000-0000-0000-0000000000f0', 'admin'),
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a0', 'admin'),
  ('00000000-0000-0000-0000-00000000aa02', '00000000-0000-0000-0000-0000000000a0', 'member');

create function pg_temp.login_as(p_email text) returns void language plpgsql as $$
declare v_id uuid;
begin
  perform set_config('request.jwt.claims', '', true);
  perform set_config('role', 'none', true);
  if p_email is null then
    return;
  end if;
  select id into v_id from public.users where email = p_email;
  perform set_config('request.jwt.claims',
                     json_build_object('sub', v_id, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);
end $$;

-- ── check constraints: statuses and kinds are text + check ──────────────────────────────────
select throws_ok($$
  insert into public.orgs (name, org_type) values ('X', 'admin')
$$, 23514, null, 'org_type must be staff or builder');
select throws_ok($$
  insert into public.orgs (name, org_type) values ('Second staff', 'staff')
$$, 23505, null, 'there can be only one staff org');
select throws_ok($$
  insert into builder.projects (org_id, name, status, selection_due_date)
  values ('00000000-0000-0000-0000-0000000000a0', 'Bad', 'on_hold', current_date)
$$, 23514, null, 'project status is limited to the four states');
select throws_ok($$
  insert into builder.projects (org_id, name, status, selection_due_date)
  values ('00000000-0000-0000-0000-0000000000a0', 'No clock', 'selection_phase', current_date)
$$, 23514, null, 'a project in selection_phase must have selection_phase_started_at');
select throws_ok($$
  insert into public.memberships (user_id, org_id, role)
  values ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a0', 'admin')
$$, 23505, null, 'one membership row per user per org');
select throws_ok($$
  insert into public.memberships (user_id, org_id, role)
  values ('00000000-0000-0000-0000-00000000cc01', '00000000-0000-0000-0000-0000000000a0', 'owner')
$$, 23514, null, 'membership role is admin or member');
select throws_ok($$
  insert into builder.alerts (org_id, user_id, project_id, kind, message, source_key)
  values ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa01',
          '00000000-0000-0000-0000-00000000a012', 'nudge', 'x', 'k')
$$, 23514, null, 'alert kind is stall or late_change');
select throws_ok($$
  insert into builder.alerts (org_id, user_id, project_id, kind, message, source_key)
  values ('00000000-0000-0000-0000-0000000000b0', '00000000-0000-0000-0000-00000000aa01',
          '00000000-0000-0000-0000-00000000a012', 'stall', 'x', 'k')
$$, 23503, null, 'an alert''s org_id must be the org of its project (composite FK)');

-- ── shared trigger: updated_at and lock_version ─────────────────────────────────────────────
update public.orgs set name = 'Builder A (renamed)' where id = '00000000-0000-0000-0000-0000000000a0';
select is((select lock_version from public.orgs where id = '00000000-0000-0000-0000-0000000000a0'), 1,
  'lock_version is bumped by the shared trigger');
select ok((select updated_at >= created_at from public.orgs where id = '00000000-0000-0000-0000-0000000000a0'),
  'updated_at is stamped by the shared trigger');

-- ── the stall rule at its edges (projects created here, as the database owner) ──────────────
insert into builder.projects (id, org_id, name, status, selection_phase_started_at, selection_due_date) values
  ('00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-0000000000a0', 'Edge exactly 5d', 'selection_phase', now() - interval '5 days', current_date + 10),
  ('00000000-0000-0000-0000-00000000e002', '00000000-0000-0000-0000-0000000000a0', 'Edge 4d23h',     'selection_phase', now() - interval '4 days 23 hours', current_date + 10),
  ('00000000-0000-0000-0000-00000000e003', '00000000-0000-0000-0000-0000000000a0', 'Edge all filled','selection_phase', now() - interval '30 days', current_date + 10),
  ('00000000-0000-0000-0000-00000000e004', '00000000-0000-0000-0000-0000000000a0', 'Edge archived',  'selection_phase', now() - interval '30 days', current_date + 10),
  ('00000000-0000-0000-0000-00000000e005', '00000000-0000-0000-0000-0000000000a0', 'Edge old act.',  'selection_phase', now() - interval '2 days', current_date + 10),
  ('00000000-0000-0000-0000-00000000e006', '00000000-0000-0000-0000-0000000000a0', 'Edge no slots',  'selection_phase', now() - interval '30 days', current_date + 10);
update builder.projects set archived_at = now() where id = '00000000-0000-0000-0000-00000000e004';

insert into builder.project_slots (org_id, project_id, room, category)
select '00000000-0000-0000-0000-0000000000a0', p.id, 'Kitchen', 'Countertop'
  from builder.projects p
 where p.id in ('00000000-0000-0000-0000-00000000e001', '00000000-0000-0000-0000-00000000e002',
                '00000000-0000-0000-0000-00000000e003', '00000000-0000-0000-0000-00000000e004',
                '00000000-0000-0000-0000-00000000e005');

-- Edge all filled: a selection in its only slot (written as the owner; the trigger records staff).
insert into builder.selections (org_id, slot_id, product_name)
select s.org_id, s.id, 'Filled' from builder.project_slots s
 where s.project_id = '00000000-0000-0000-0000-00000000e003';

-- Edge old activity: a builder history row 10 days ago on a project whose phase began 2 days ago.
insert into builder.selection_history (org_id, slot_id, action, product_name, actor_kind, changed_at)
select s.org_id, s.id, 'set', 'Old', 'builder', now() - interval '10 days'
  from builder.project_slots s where s.project_id = '00000000-0000-0000-0000-00000000e005';

select is((select is_stalled from builder.v_projects_overview where id = '00000000-0000-0000-0000-00000000e001'), true,
  'quiet for exactly 5 days counts as 5+ days: stalled');
select is((select is_stalled from builder.v_projects_overview where id = '00000000-0000-0000-0000-00000000e002'), false,
  'quiet for 4 days 23 hours is not stalled');
select is((select is_stalled from builder.v_projects_overview where id = '00000000-0000-0000-0000-00000000e003'), false,
  'no empty slot: not stalled however quiet');
select is((select is_stalled from builder.v_projects_overview where id = '00000000-0000-0000-0000-00000000e004'), false,
  'archived: not stalled');
select is((select is_stalled from builder.v_projects_overview where id = '00000000-0000-0000-0000-00000000e005'), false,
  'quiet since is the LATER of last builder activity and phase start');
select is((select is_stalled from builder.v_projects_overview where id = '00000000-0000-0000-0000-00000000e006'), false,
  'a project with no slots has no empty slot: not stalled');

-- ── roles at the edges ──────────────────────────────────────────────────────────────────────
-- A member (not admin) of the builder org may set selections.
select pg_temp.login_as('t-mia@builder-a.test');
select lives_ok($$
  insert into builder.selections (org_id, slot_id, product_name, selected_by)
  select s.org_id, s.id, 'Member pick', '00000000-0000-0000-0000-00000000aa02'
    from builder.project_slots s
   where s.project_id = '00000000-0000-0000-0000-00000000a012' and s.room = 'Primary Bath' and s.category = 'Vanity Top'
$$, 'a builder member (not admin) can set a selection');

-- A signed-in user with no membership can do nothing, loudly or silently.
select pg_temp.login_as('t-nobody@example.test');
select is((select count(*)::int from builder.project_slots), 0, 'no membership: sees no slots');
select throws_ok($$
  insert into builder.selections (org_id, slot_id, product_name, selected_by)
  values ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000e001', 'x',
          '00000000-0000-0000-0000-00000000cc01')
$$, 42501, null, 'no membership: cannot insert a selection even with a guessed org_id');

-- Builders cannot write the tables that only definer code writes.
select pg_temp.login_as('t-ana@builder-a.test');
select throws_ok($$
  insert into builder.alerts (org_id, user_id, project_id, kind, message, source_key)
  values ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa01',
          '00000000-0000-0000-0000-00000000a012', 'stall', 'forged', 'k')
$$, 42501, null, 'a builder cannot insert an alert');
select throws_ok($$
  insert into builder.selection_history (org_id, slot_id, action, actor_kind)
  values ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000e001', 'set', 'builder')
$$, 42501, null, 'a builder cannot write history directly');
select throws_ok($$
  insert into builder.detector_runs (trigger_kind) values ('manual')
$$, 42501, null, 'a builder cannot write the run log');
select throws_ok($$
  delete from builder.alerts
$$, 42501, null, 'a builder cannot delete alerts');

-- Anonymous callers cannot run the detector.
select pg_temp.login_as(null);
set local role anon;
select throws_ok($$ select builder.run_stall_detector_now() $$, 42501, null,
  'anon cannot call run_stall_detector_now()');
reset role;

select * from finish();
rollback;
