-- builder schema: projects and project_slots.
--
-- WHY. Everything a builder touches lives in the builder schema, exposed through the Data API
-- next to public. A project is one home, owned by one builder org; a slot is one thing the
-- project needs picked (room + category). Builders only read these; staff may update projects
-- (status, dates). Both tables carry org_id so every policy is the plain org predicate, and
-- slots carry a composite foreign key (project_id, org_id) so a slot can never claim a
-- different org than its project.
--
-- WHAT.
--   1. schema builder — usage for anon and authenticated (PostgREST switches to those roles);
--      table privileges only for authenticated, and only what the policies can allow.
--   2. builder.projects — status is text + check; a project in selection_phase must have
--      selection_phase_started_at (the stall clock needs it); unique (id, org_id) so children
--      can reference the pair.
--   3. builder.project_slots — unique (project_id, room, category); unique (id, org_id) for
--      the selections' composite key.
--   4. RLS enabled and forced; p_projects_select / p_project_slots_select with the org
--      predicate; p_projects_update for staff only, limited by a column grant to the fields a
--      status change touches, so org_id and id cannot move.
--   5. updated_at / lock_version triggers; indexes on every foreign key.
--
-- NOT SELF-CONTAINED. builder must be listed in [api].schemas (supabase/config.toml) and in
-- the hosted project's "Exposed schemas" setting, or the app cannot reach these tables.
--
-- ROLLBACK:
--   drop table if exists builder.project_slots;
--   drop table if exists builder.projects;
--   drop schema if exists builder;

create schema if not exists builder;

revoke all on schema builder from public;
grant usage on schema builder to anon, authenticated;

create table if not exists builder.projects (
  id                          uuid primary key default gen_random_uuid(),
  org_id                      uuid not null references public.orgs (id),
  name                        text not null,
  status                      text not null default 'pending_kickoff'
    check (status in ('pending_kickoff', 'selection_phase', 'revision', 'complete')),
  selection_phase_started_at  timestamptz,
  selection_due_date          date not null,
  archived_at                 timestamptz,
  created_at                  timestamptz not null default now(),
  updated_at                  timestamptz not null default now(),
  lock_version                integer not null default 0,
  constraint projects_selection_phase_has_start
    check (status <> 'selection_phase' or selection_phase_started_at is not null),
  constraint projects_id_org_unique unique (id, org_id)
);

create index if not exists projects_org_id_idx on builder.projects (org_id);

create table if not exists builder.project_slots (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null references public.orgs (id),
  project_id    uuid not null,
  room          text not null,
  category      text not null,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  lock_version  integer not null default 0,
  constraint project_slots_project_fk
    foreign key (project_id, org_id) references builder.projects (id, org_id),
  constraint project_slots_id_org_unique unique (id, org_id),
  constraint project_slots_project_room_category_unique unique (project_id, room, category)
);

create index if not exists project_slots_org_id_idx on builder.project_slots (org_id);

alter table builder.projects      enable row level security;
alter table builder.projects      force  row level security;
alter table builder.project_slots enable row level security;
alter table builder.project_slots force  row level security;

grant select on builder.projects, builder.project_slots to authenticated;
grant update (name, status, selection_phase_started_at, selection_due_date, archived_at)
  on builder.projects to authenticated;

drop policy if exists p_projects_select on builder.projects;
create policy p_projects_select on builder.projects
  for select to authenticated
  using (org_id = any (private.current_user_org_ids()) or private.is_staff());

drop policy if exists p_projects_update on builder.projects;
create policy p_projects_update on builder.projects
  for update to authenticated
  using      (private.is_staff())
  with check (private.is_staff());

drop policy if exists p_project_slots_select on builder.project_slots;
create policy p_project_slots_select on builder.project_slots
  for select to authenticated
  using (org_id = any (private.current_user_org_ids()) or private.is_staff());

drop trigger if exists trg_projects_set_updated_at on builder.projects;
create trigger trg_projects_set_updated_at
  before update on builder.projects
  for each row execute function private.set_updated_at();

drop trigger if exists trg_project_slots_set_updated_at on builder.project_slots;
create trigger trg_project_slots_set_updated_at
  before update on builder.project_slots
  for each row execute function private.set_updated_at();
