-- Late-change alert (Part 3 bonus): a builder change on a project in revision alerts staff.
begin;
create extension if not exists pgtap with schema extensions;
select plan(9);

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
  ('00000000-0000-0000-0000-00000000ff02', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't-sam@stallwatch.test',   now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't-ana@builder-a.test',   now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());
insert into public.memberships (user_id, org_id, role) values
  ('00000000-0000-0000-0000-00000000ff01', '00000000-0000-0000-0000-0000000000f0', 'admin'),
  ('00000000-0000-0000-0000-00000000ff02', '00000000-0000-0000-0000-0000000000f0', 'member'),
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a0', 'admin');

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

create function pg_temp.late_alerts() returns int language sql as $$
  select count(*)::int from builder.alerts where kind = 'late_change'
$$;

-- Lot 15 is in revision in the seed. Ana changes its countertop.
select pg_temp.login_as('t-ana@builder-a.test');
update builder.selections s set product_name = 'Leathered Granite', selected_by = '00000000-0000-0000-0000-00000000aa01'
  from builder.project_slots sl
 where sl.id = s.slot_id and sl.project_id = '00000000-0000-0000-0000-00000000a015'
   and sl.room = 'Kitchen' and sl.category = 'Countertop';
select pg_temp.login_as(null);

select is(pg_temp.late_alerts(), 2, 'every staff user (admin and member) gets one late-change alert');
select is(
  (select count(distinct message)::int from builder.alerts where kind = 'late_change'), 1,
  'both alerts carry the same message');
select is(
  (select message from builder.alerts where kind = 'late_change' limit 1),
  'Builder A changed Kitchen – Countertop on Lot 15 after revision.',
  'the message names the builder, the slot and the project');
select is(
  (select count(*)::int from builder.alerts a join public.users u on u.id = a.user_id where u.email = 't-ana@builder-a.test'),
  0, 'the builder who made the change is not alerted');

-- The same change again is a no-op: no history, no alert.
select pg_temp.login_as('t-ana@builder-a.test');
update builder.selections s set product_name = 'Leathered Granite', selected_by = '00000000-0000-0000-0000-00000000aa01'
  from builder.project_slots sl
 where sl.id = s.slot_id and sl.project_id = '00000000-0000-0000-0000-00000000a015'
   and sl.room = 'Kitchen' and sl.category = 'Countertop';
select pg_temp.login_as(null);
select is(pg_temp.late_alerts(), 2, 'a no-op update creates nothing');

-- A clear is a late change too, with its own wording.
select pg_temp.login_as('t-ana@builder-a.test');
delete from builder.selections s
  using builder.project_slots sl
 where sl.id = s.slot_id and sl.project_id = '00000000-0000-0000-0000-00000000a015'
   and sl.room = 'Great Room' and sl.category = 'Flooring';
select pg_temp.login_as(null);
select is(pg_temp.late_alerts(), 4, 'a clear after revision alerts staff too');
select is(
  (select count(*)::int from builder.alerts
    where message = 'Builder A cleared Great Room – Flooring on Lot 15 after revision.'),
  2, 'a clear says cleared, once per staff user');

-- Staff changes after revision are not late changes.
select pg_temp.login_as('t-staff@stallwatch.test');
update builder.selections s set product_name = 'Staff Fix', selected_by = '00000000-0000-0000-0000-00000000ff01'
  from builder.project_slots sl
 where sl.id = s.slot_id and sl.project_id = '00000000-0000-0000-0000-00000000a015'
   and sl.room = 'Kitchen' and sl.category = 'Backsplash';
select pg_temp.login_as(null);
select is(pg_temp.late_alerts(), 4, 'a staff change does not alert');

-- A builder change on a project that is NOT in revision is not a late change.
select pg_temp.login_as('t-ana@builder-a.test');
update builder.selections s set product_name = 'Different Faucet', selected_by = '00000000-0000-0000-0000-00000000aa01'
  from builder.project_slots sl
 where sl.id = s.slot_id and sl.project_id = '00000000-0000-0000-0000-00000000a012'
   and sl.room = 'Kitchen' and sl.category = 'Faucet';
select pg_temp.login_as(null);
select is(pg_temp.late_alerts(), 4, 'a change on a selection_phase project does not alert');

select * from finish();
rollback;
