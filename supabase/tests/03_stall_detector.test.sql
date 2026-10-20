-- The stall detector against the seed scenarios: who is flagged, who is alerted, no
-- duplicates, a new stall after new activity, failed runs stay visible.
begin;
create extension if not exists pgtap with schema extensions;
select plan(31);

-- ── fixtures ────────────────────────────────────────────────────────────────────────────────
insert into auth.users (id, instance_id, aud, role, email, email_confirmed_at,
                        raw_app_meta_data, raw_user_meta_data, created_at, updated_at)
values
  ('00000000-0000-0000-0000-00000000ff01', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'staff@stallwatch.test', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'ana@builder-a.test',   now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-00000000aa02', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'mia@builder-a.test',   now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-00000000bb01', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 'bruno@builder-b.test', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());
insert into public.memberships (user_id, org_id, role) values
  ('00000000-0000-0000-0000-00000000ff01', '00000000-0000-0000-0000-0000000000f0', 'admin'),
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a0', 'admin'),
  ('00000000-0000-0000-0000-00000000aa02', '00000000-0000-0000-0000-0000000000a0', 'member'),
  ('00000000-0000-0000-0000-00000000bb01', '00000000-0000-0000-0000-0000000000b0', 'admin');

create function pg_temp.login_as(p_email text) returns void language plpgsql as $$
declare v_id uuid;
begin
  -- Always drop back to the session user first: the lookup below must not run under the
  -- previous user's RLS.
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

create function pg_temp.alerts_for(p_email text) returns int language sql as $$
  select count(*)::int from builder.alerts a join public.users u on u.id = a.user_id where u.email = p_email
$$;

-- ── builders can neither see the run log nor run the detector, by either path ───────────────
select pg_temp.login_as('ana@builder-a.test');
select is((select count(*)::int from builder.detector_runs), 0, 'a builder cannot read the detector run log');
select throws_ok($$ select builder.run_stall_detector_now() $$, 42501, null,
  'a builder calling run_stall_detector_now() is rejected');
select throws_ok($$ select private.run_stall_detector('manual', null) $$, 42501, null,
  'a builder cannot reach the worker function');
select pg_temp.login_as(null);

-- ── it is scheduled, and the worker is unreachable over the API ─────────────────────────────
select is((select count(*)::int from cron.job where jobname = 'stall-detector-nightly'),
  1, 'the stall detector is scheduled in pg_cron');
select ok(not has_function_privilege('authenticated', 'private.run_stall_detector(text, uuid)', 'execute'),
  'authenticated cannot execute the detector worker');

-- ── the rule, live ──────────────────────────────────────────────────────────────────────────
select bag_eq(
  $$ select name from builder.v_projects_overview where is_stalled $$,
  $$ values ('Lot 12'), ('Unit 4B'), ('Unit 7C') $$,
  'the live rule flags exactly Lot 12, Unit 4B and Unit 7C on the seed');

-- ── first run (as the scheduler would: no user) ─────────────────────────────────────────────
select lives_ok($$ select private.run_stall_detector('scheduled', null) $$, 'first run succeeds');
select results_eq(
  $$ select status, trigger_kind, projects_flagged, new_episodes, alerts_created, triggered_by
       from builder.detector_runs order by started_at desc limit 1 $$,
  $$ values ('succeeded', 'scheduled', 3, 3, 3, null::uuid) $$,
  'the run is recorded: 3 flagged, 3 new episodes, 3 alerts');
select is((select finished_at is not null from builder.detector_runs order by started_at desc limit 1), true,
  'the run has a finished_at');

select is(pg_temp.alerts_for('ana@builder-a.test'),   1, 'Ana (Builder A admin) got 1 alert (Lot 12)');
select is(pg_temp.alerts_for('mia@builder-a.test'),   0, 'Mia (Builder A member, not admin) got none');
select is(pg_temp.alerts_for('bruno@builder-b.test'), 2, 'Bruno (Builder B admin) got 2 (Unit 4B, Unit 7C)');
select is(pg_temp.alerts_for('staff@stallwatch.test'), 0, 'staff get no stall alerts');

select is(
  (select a.message from builder.alerts a join public.users u on u.id = a.user_id where u.email = 'ana@builder-a.test'),
  'Lot 12 has had no builder activity for 7 days. 3 slots are still empty.',
  'the alert message reads as the brief describes');
select is(
  (select a.org_id from builder.alerts a join public.users u on u.id = a.user_id where u.email = 'ana@builder-a.test'),
  '00000000-0000-0000-0000-0000000000a0'::uuid,
  'the alert''s org_id is the project''s builder org');

-- ── second run: staff presses Run now; nothing duplicates ───────────────────────────────────
select pg_temp.login_as('staff@stallwatch.test');
select lives_ok($$ select builder.run_stall_detector_now() $$, 'staff can run it on demand');
select pg_temp.login_as(null);

select results_eq(
  $$ select status, trigger_kind, projects_flagged, new_episodes, alerts_created, triggered_by
       from builder.detector_runs order by started_at desc limit 1 $$,
  $$ values ('succeeded', 'manual', 3, 0, 0, '00000000-0000-0000-0000-00000000ff01'::uuid) $$,
  'the manual run still flags 3 but creates no new episodes or alerts');
select is(pg_temp.alerts_for('ana@builder-a.test'), 1, 'Ana still has exactly 1 alert');
select throws_ok($$
  insert into builder.stall_episodes (project_id, org_id, quiet_since, detector_run_id)
  select project_id, org_id, quiet_since, detector_run_id from builder.stall_episodes limit 1
$$, 23505, null, 'the unique (project_id, quiet_since) key refuses a second episode for the same stall');

-- ── staff activity does not un-stall ────────────────────────────────────────────────────────
select pg_temp.login_as('staff@stallwatch.test');
update builder.selections s set product_name = 'Staff Touch', selected_by = '00000000-0000-0000-0000-00000000ff01'
  from builder.project_slots sl
 where sl.id = s.slot_id and sl.project_id = '00000000-0000-0000-0000-00000000b07c' and sl.room = 'Living';
select pg_temp.login_as(null);
select is((select is_stalled from builder.v_projects_overview where name = 'Unit 7C'), true,
  'a staff change does not count as builder activity (Unit 7C stays stalled)');

-- ── Ana acts: Lot 12 is no longer stalled, and the badge clears immediately ─────────────────
select pg_temp.login_as('ana@builder-a.test');
insert into builder.selections (org_id, slot_id, product_name, selected_by)
select s.org_id, s.id, 'Honed Marble', '00000000-0000-0000-0000-00000000aa01'
  from builder.project_slots s
 where s.project_id = '00000000-0000-0000-0000-00000000a012' and s.room = 'Laundry' and s.category = 'Floor Tile';
select pg_temp.login_as(null);

select is((select is_stalled from builder.v_projects_overview where name = 'Lot 12'), false,
  'Lot 12 is no longer stalled the moment Ana picks a product');
select lives_ok($$ select private.run_stall_detector('scheduled', null) $$, 'third run succeeds');
select is((select projects_flagged from builder.detector_runs order by started_at desc limit 1), 2,
  'the third run flags only Unit 4B and Unit 7C');
select is((select resolved_at is not null from builder.stall_episodes
            where project_id = '00000000-0000-0000-0000-00000000a012'), true,
  'Lot 12''s episode is marked resolved');
select is(pg_temp.alerts_for('ana@builder-a.test'), 1, 'no new alert for Ana while she is active');

-- ── Ana goes quiet again for 5+ days: a NEW stall, a NEW alert ──────────────────────────────
-- Simulate time passing by backdating her last activity (the append-only guard is a trigger;
-- it is disabled here only because this is a test transaction that rolls back).
alter table builder.selection_history disable trigger trg_selection_history_append_only;
update builder.selection_history h
   set changed_at = now() - interval '6 days'
  from builder.project_slots sl
 where sl.id = h.slot_id and sl.project_id = '00000000-0000-0000-0000-00000000a012'
   and sl.room = 'Laundry' and h.actor_kind = 'builder';
alter table builder.selection_history enable trigger trg_selection_history_append_only;

select is((select is_stalled from builder.v_projects_overview where name = 'Lot 12'), true,
  'after 6 quiet days Lot 12 is stalled again');
select lives_ok($$ select private.run_stall_detector('scheduled', null) $$, 'fourth run succeeds');
select is((select new_episodes from builder.detector_runs order by started_at desc limit 1), 1,
  'the fourth run sees Lot 12 as a new stall');
select is(pg_temp.alerts_for('ana@builder-a.test'), 2, 'Ana gets a second, new alert for the new stall');

-- ── a failed run is recorded as failed, with its error, and leaves no half-finished work ────
alter table builder.stall_episodes rename to stall_episodes_broken;
select lives_ok($$ select private.run_stall_detector('scheduled', null) $$,
  'a run whose work errors does not raise to the caller');
alter table builder.stall_episodes_broken rename to stall_episodes;
select results_eq(
  $$ select status, error_message ilike '%stall_episodes%', finished_at is not null
       from builder.detector_runs order by started_at desc limit 1 $$,
  $$ values ('failed', true, true) $$,
  'the failed run shows as failed with its error message');

select * from finish();
rollback;
