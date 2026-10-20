-- Tenant isolation: log in as Builder A and try to read and write Builder B's data.
-- Runs against the provided seed. Test users are created here (the real ones come from the
-- dashboard + link-test-users.sql); the auth-mirror trigger must copy them into public.users.
begin;
create extension if not exists pgtap with schema extensions;
select plan(33);

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
  ('00000000-0000-0000-0000-00000000bb01', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't-bruno@builder-b.test', now(), '{"provider":"email","providers":["email"]}', '{}', now(), now()),
  ('00000000-0000-0000-0000-00000000cc01', '00000000-0000-0000-0000-000000000000', 'authenticated', 'authenticated', 't-nobody@example.test',  now(), '{"provider":"email","providers":["email"]}', '{}', now(), now());

select is((select count(*)::int from public.users where email in
  ('t-staff@stallwatch.test', 't-ana@builder-a.test', 't-mia@builder-a.test', 't-bruno@builder-b.test', 't-nobody@example.test')),
  5, 'auth-mirror trigger copied every auth user into public.users');

-- Same rows link-test-users.sql inserts.
insert into public.memberships (user_id, org_id, role) values
  ('00000000-0000-0000-0000-00000000ff01', '00000000-0000-0000-0000-0000000000f0', 'admin'),
  ('00000000-0000-0000-0000-00000000aa01', '00000000-0000-0000-0000-0000000000a0', 'admin'),
  ('00000000-0000-0000-0000-00000000aa02', '00000000-0000-0000-0000-0000000000a0', 'member'),
  ('00000000-0000-0000-0000-00000000bb01', '00000000-0000-0000-0000-0000000000b0', 'admin');

-- Become a user the way PostgREST does: role authenticated + JWT claims. null = signed out.
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

-- A Builder B slot id that an attacker might have learned out of band. Definer so the test can
-- read it while logged in as Ana, who cannot see the row herself.
create function pg_temp.b_slot_id() returns uuid language sql security definer as $$
  select id from builder.project_slots
   where project_id = '00000000-0000-0000-0000-00000000b04b'
   order by room, category limit 1
$$;

-- ── Ana (Builder A admin) ───────────────────────────────────────────────────────────────────
select pg_temp.login_as('t-ana@builder-a.test');

select is((select count(*)::int from builder.projects), 5, 'Ana sees exactly Builder A''s 5 projects');
select is((select count(*)::int from builder.projects where org_id = '00000000-0000-0000-0000-0000000000b0'), 0,
  'Ana sees none of Builder B''s projects');
select is((select count(*)::int from builder.project_slots where org_id = '00000000-0000-0000-0000-0000000000b0'), 0,
  'Ana sees none of Builder B''s slots');
select is((select count(*)::int from builder.selections where org_id = '00000000-0000-0000-0000-0000000000b0'), 0,
  'Ana sees none of Builder B''s selections');
select is((select count(*)::int from builder.selection_history where org_id = '00000000-0000-0000-0000-0000000000b0'), 0,
  'Ana sees none of Builder B''s history');
select is((select count(*)::int from public.orgs), 1, 'Ana sees only her own org');
select is((select count(*)::int from builder.v_projects_overview), 5, 'the overview view is scoped like projects');

-- Write into Builder B, tagged with B's org_id: the with check blocks it.
select throws_ok($$
  insert into builder.selections (org_id, slot_id, product_name, selected_by)
  values ('00000000-0000-0000-0000-0000000000b0', pg_temp.b_slot_id(), 'Sneaky',
          '00000000-0000-0000-0000-00000000aa01')
$$, 42501, null, 'Ana cannot write a selection into Builder B tagged with B''s org_id (RLS)');

-- Write into Builder B, tagged with A's own org_id (passes an org_id-only policy): the
-- composite foreign key (slot_id, org_id) blocks it.
select throws_ok($$
  insert into builder.selections (org_id, slot_id, product_name, selected_by)
  values ('00000000-0000-0000-0000-0000000000a0', pg_temp.b_slot_id(), 'Sneaky',
          '00000000-0000-0000-0000-00000000aa01')
$$, 23503, null, 'Ana cannot attach a selection to Builder B''s slot with her own org_id (composite FK)');

-- Builders cannot change projects (policy is staff-only; rows filter to nothing).
update builder.projects set name = 'Hacked' where id = '00000000-0000-0000-0000-00000000a012';
select is((select name from builder.projects where id = '00000000-0000-0000-0000-00000000a012'), 'Lot 12',
  'a builder cannot update a project (the update matches no rows)');
select throws_ok($$
  update builder.projects set org_id = '00000000-0000-0000-0000-0000000000b0'
   where id = '00000000-0000-0000-0000-00000000a012'
$$, 42501, null, 'org_id of a project is not updatable at all (column grant)');

-- A builder can set, change and clear a selection in their own org, and history records it.
insert into builder.selections (org_id, slot_id, product_name, selected_by)
select s.org_id, s.id, 'Test Quartz', '00000000-0000-0000-0000-00000000aa01'
  from builder.project_slots s
 where s.project_id = '00000000-0000-0000-0000-00000000a012' and s.room = 'Laundry' and s.category = 'Floor Tile';
select is((select count(*)::int from builder.selections s join builder.project_slots sl on sl.id = s.slot_id
            where sl.project_id = '00000000-0000-0000-0000-00000000a012'), 6, 'Ana set a selection on Lot 12');
select results_eq($$
  select h.action, h.actor_kind, h.changed_by
    from builder.selection_history h join builder.project_slots sl on sl.id = h.slot_id
   where sl.project_id = '00000000-0000-0000-0000-00000000a012' and sl.room = 'Laundry'
$$, $$ values ('set', 'builder', '00000000-0000-0000-0000-00000000aa01'::uuid) $$,
  'history records the set as builder activity by Ana');

update builder.selections s set product_name = 'Test Quartz', selected_by = '00000000-0000-0000-0000-00000000aa01'
  from builder.project_slots sl
 where sl.id = s.slot_id and sl.project_id = '00000000-0000-0000-0000-00000000a012' and sl.room = 'Laundry';
select is((select count(*)::int from builder.selection_history h join builder.project_slots sl on sl.id = h.slot_id
            where sl.project_id = '00000000-0000-0000-0000-00000000a012' and sl.room = 'Laundry'),
  1, 'a no-op update (same product) records no history');

update builder.selections s set product_name = 'Test Porcelain', selected_by = '00000000-0000-0000-0000-00000000aa01'
  from builder.project_slots sl
 where sl.id = s.slot_id and sl.project_id = '00000000-0000-0000-0000-00000000a012' and sl.room = 'Laundry';
select is((select count(*)::int from builder.selection_history h join builder.project_slots sl on sl.id = h.slot_id
            where sl.project_id = '00000000-0000-0000-0000-00000000a012' and sl.room = 'Laundry'
              and h.action = 'change' and h.actor_kind = 'builder'),
  1, 'a real change is recorded as a builder change');

select throws_ok($$
  insert into builder.selections (org_id, slot_id, product_name, selected_by)
  select s.org_id, s.id, 'Forged', '00000000-0000-0000-0000-00000000aa02'
    from builder.project_slots s
   where s.project_id = '00000000-0000-0000-0000-00000000a012' and s.room = 'Primary Bath' and s.category = 'Wall Tile'
$$, 42501, null, 'selected_by must be the caller');

-- ── Staff ───────────────────────────────────────────────────────────────────────────────────
select pg_temp.login_as('t-staff@stallwatch.test');

select is((select count(*)::int from builder.projects), 9, 'staff see every project');
select is((select count(*)::int from public.orgs), 3, 'staff see every org');

update builder.selections s set product_name = 'Staff Pick', selected_by = '00000000-0000-0000-0000-00000000ff01'
  from builder.project_slots sl
 where sl.id = s.slot_id and sl.project_id = '00000000-0000-0000-0000-00000000a012' and sl.room = 'Laundry';
select is((select count(*)::int from builder.selection_history h join builder.project_slots sl on sl.id = h.slot_id
            where sl.project_id = '00000000-0000-0000-0000-00000000a012' and sl.room = 'Laundry'
              and h.actor_kind = 'staff' and h.changed_by = '00000000-0000-0000-0000-00000000ff01'),
  1, 'a staff change is recorded with actor_kind = staff');

update builder.projects set status = 'revision' where id = '00000000-0000-0000-0000-00000000a012';
select is((select status from builder.projects where id = '00000000-0000-0000-0000-00000000a012'), 'revision',
  'staff can change a project''s status');
select is((select lock_version from builder.projects where id = '00000000-0000-0000-0000-00000000a012'), 1,
  'lock_version is bumped on update');

-- ── Bruno (Builder B admin) ─────────────────────────────────────────────────────────────────
select pg_temp.login_as('t-bruno@builder-b.test');
select is((select count(*)::int from builder.projects), 4, 'Bruno sees exactly Builder B''s 4 projects');

-- ── A signed-in user with no membership sees nothing ────────────────────────────────────────
select pg_temp.login_as('t-nobody@example.test');
select is((select count(*)::int from builder.projects), 0, 'a user with no membership sees no projects');
select is((select count(*)::int from public.orgs), 0, 'a user with no membership sees no orgs');

-- ── Alerts: only the recipient ──────────────────────────────────────────────────────────────
select pg_temp.login_as(null);
insert into builder.alerts (org_id, user_id, project_id, kind, message, source_key)
values ('00000000-0000-0000-0000-0000000000a0', '00000000-0000-0000-0000-00000000aa01',
        '00000000-0000-0000-0000-00000000a012', 'stall', 'test alert', 'test-1');

select pg_temp.login_as('t-bruno@builder-b.test');
select is((select count(*)::int from builder.alerts), 0, 'Bruno cannot see Ana''s alert');
select pg_temp.login_as('t-staff@stallwatch.test');
select is((select count(*)::int from builder.alerts), 0, 'staff cannot see Ana''s alert either');

select pg_temp.login_as('t-ana@builder-a.test');
select is((select count(*)::int from builder.alerts), 1, 'Ana sees her alert');
select throws_ok($$ update builder.alerts set message = 'edited' $$, 42501, null,
  'the recipient cannot change anything but read_at (column grant)');
update builder.alerts set read_at = now();
select is((select count(*)::int from builder.alerts where read_at is not null), 1, 'the recipient can mark it read');

-- ── Anonymous: nothing ──────────────────────────────────────────────────────────────────────
select pg_temp.login_as(null);
set local role anon;
select throws_ok($$ select count(*) from builder.projects $$, 42501, null, 'anon cannot read projects');
reset role;

-- ── History is append-only even for the owner ───────────────────────────────────────────────
select throws_ok($$ update builder.selection_history set product_name = 'x' $$, 42501, null,
  'history rows cannot be updated');
select throws_ok($$ delete from builder.selection_history $$, 42501, null,
  'history rows cannot be deleted');

select * from finish();
rollback;
