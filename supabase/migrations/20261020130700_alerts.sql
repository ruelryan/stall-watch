-- In-app alerts, one row per recipient.
--
-- WHY. The detector (and the late-change trigger) tell people inside the app. Alerts are
-- narrower than org scope: only the recipient can read one or mark it read, and "mark read"
-- may change read_at and nothing else. RLS cannot limit columns, so that is a column grant.
-- Staff cannot read other people's alerts. An alert's org_id is the builder org of the
-- project it is about, even when the recipient is staff, enforced by the composite FK.
-- (user_id, kind, source_key) is unique: the writer names the thing the alert is about (a stall
-- episode id, a history row id), so the same event can never produce two alerts for one person.
--
-- WHAT.
--   1. builder.alerts — org_id, user_id, project_id, kind (stall | late_change), message,
--      source_key, read_at; composite FK (project_id, org_id) → projects.
--   2. p_alerts_select and p_alerts_update, both user_id = auth.uid(); no insert or delete
--      for authenticated (alerts are created only by definer code).
--   3. grant update (read_at) only.
--
-- NOT SELF-CONTAINED. Nothing.
--
-- ROLLBACK:
--   drop table if exists builder.alerts;

create table if not exists builder.alerts (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null references public.orgs (id),
  user_id       uuid not null references public.users (id),
  project_id    uuid not null,
  kind          text not null check (kind in ('stall', 'late_change')),
  message       text not null,
  source_key    text not null,
  read_at       timestamptz,
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  lock_version  integer not null default 0,
  constraint alerts_project_fk
    foreign key (project_id, org_id) references builder.projects (id, org_id),
  constraint alerts_once_per_event unique (user_id, kind, source_key)
);

create index if not exists alerts_user_created_idx on builder.alerts (user_id, created_at desc);
create index if not exists alerts_org_id_idx       on builder.alerts (org_id);
create index if not exists alerts_project_id_idx   on builder.alerts (project_id);

alter table builder.alerts enable row level security;
alter table builder.alerts force  row level security;

grant select           on builder.alerts to authenticated;
grant update (read_at) on builder.alerts to authenticated;

drop policy if exists p_alerts_select on builder.alerts;
create policy p_alerts_select on builder.alerts
  for select to authenticated
  using (user_id = auth.uid());

drop policy if exists p_alerts_update on builder.alerts;
create policy p_alerts_update on builder.alerts
  for update to authenticated
  using      (user_id = auth.uid())
  with check (user_id = auth.uid());

drop trigger if exists trg_alerts_set_updated_at on builder.alerts;
create trigger trg_alerts_set_updated_at
  before update on builder.alerts
  for each row execute function private.set_updated_at();
