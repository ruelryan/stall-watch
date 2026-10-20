-- Selections (the current pick per slot) and selection_history (every set, change and clear).
--
-- WHY. The stall rule is "no BUILDER activity for 5+ days", and the seed's Unit 7C shows the
-- trap: selections.updated_at moves when staff touch a selection. So activity is read from
-- selection_history.actor_kind, which is filled by a trigger from the CALLER'S MEMBERSHIP,
-- never from a value the app sends. The history trigger is SECURITY DEFINER on purpose: it is
-- the only writer of history, so builders cannot forge or omit rows. History is append-only
-- for everyone, including the owner, via a guard trigger.
--
-- WHAT.
--   1. builder.selections — at most one row per slot (unique slot_id); composite FK
--      (slot_id, org_id) → project_slots (id, org_id) so a selection cannot be written into
--      another org's slot while carrying the writer's own org_id.
--   2. builder.selection_history — org_id, slot_id, action set|change|clear, product_name
--      (null for clears), changed_by (null for seeded rows), actor_kind builder|staff,
--      changed_at. No updated_at / lock_version: it is never updated.
--   3. private.record_selection_history() — after insert/update/delete on selections. A
--      no-op update (same product_name) records nothing and is not activity. actor_kind is
--      'builder' iff auth.uid() is a member of the row's org, else 'staff' (that includes a
--      job or the SQL editor, where auth.uid() is null).
--   4. private.reject_history_mutation() + trg_selection_history_append_only — raises on any
--      update or delete.
--   5. Policies: p_selections_select/insert/update/delete with the org predicate on using and
--      with check (plus selected_by = auth.uid() on writes); p_selection_history_select only.
--      Column grants limit inserts/updates to the business columns, so org_id and slot_id can't
--      be moved by an update.
--
-- NOT SELF-CONTAINED. Nothing.
--
-- ROLLBACK:
--   drop trigger if exists trg_selection_history_append_only on builder.selection_history;
--   drop trigger if exists trg_selections_history on builder.selections;
--   drop function if exists private.reject_history_mutation();
--   drop function if exists private.record_selection_history();
--   drop table if exists builder.selection_history;
--   drop table if exists builder.selections;

create table if not exists builder.selections (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null references public.orgs (id),
  slot_id       uuid not null,
  product_name  text not null check (length(btrim(product_name)) > 0),
  selected_by   uuid references public.users (id),
  created_at    timestamptz not null default now(),
  updated_at    timestamptz not null default now(),
  lock_version  integer not null default 0,
  constraint selections_slot_fk
    foreign key (slot_id, org_id) references builder.project_slots (id, org_id),
  constraint selections_slot_unique unique (slot_id)
);

create index if not exists selections_org_id_idx      on builder.selections (org_id);
create index if not exists selections_selected_by_idx on builder.selections (selected_by);

create table if not exists builder.selection_history (
  id            uuid primary key default gen_random_uuid(),
  org_id        uuid not null references public.orgs (id),
  slot_id       uuid not null,
  action        text not null check (action in ('set', 'change', 'clear')),
  product_name  text,
  changed_by    uuid references public.users (id),
  actor_kind    text not null check (actor_kind in ('builder', 'staff')),
  changed_at    timestamptz not null default now(),
  created_at    timestamptz not null default now(),
  constraint selection_history_slot_fk
    foreign key (slot_id, org_id) references builder.project_slots (id, org_id)
);

create index if not exists selection_history_slot_changed_idx
  on builder.selection_history (slot_id, changed_at desc);
create index if not exists selection_history_org_id_idx     on builder.selection_history (org_id);
create index if not exists selection_history_changed_by_idx on builder.selection_history (changed_by);

alter table builder.selections        enable row level security;
alter table builder.selections        force  row level security;
alter table builder.selection_history enable row level security;
alter table builder.selection_history force  row level security;

grant select on builder.selections, builder.selection_history to authenticated;
grant insert (org_id, slot_id, product_name, selected_by) on builder.selections to authenticated;
grant update (product_name, selected_by)                   on builder.selections to authenticated;
grant delete                                               on builder.selections to authenticated;

drop policy if exists p_selections_select on builder.selections;
create policy p_selections_select on builder.selections
  for select to authenticated
  using (org_id = any (private.current_user_org_ids()) or private.is_staff());

drop policy if exists p_selections_insert on builder.selections;
create policy p_selections_insert on builder.selections
  for insert to authenticated
  with check ((org_id = any (private.current_user_org_ids()) or private.is_staff())
              and selected_by = auth.uid());

drop policy if exists p_selections_update on builder.selections;
create policy p_selections_update on builder.selections
  for update to authenticated
  using      (org_id = any (private.current_user_org_ids()) or private.is_staff())
  with check ((org_id = any (private.current_user_org_ids()) or private.is_staff())
              and selected_by = auth.uid());

drop policy if exists p_selections_delete on builder.selections;
create policy p_selections_delete on builder.selections
  for delete to authenticated
  using (org_id = any (private.current_user_org_ids()) or private.is_staff());

drop policy if exists p_selection_history_select on builder.selection_history;
create policy p_selection_history_select on builder.selection_history
  for select to authenticated
  using (org_id = any (private.current_user_org_ids()) or private.is_staff());

drop trigger if exists trg_selections_set_updated_at on builder.selections;
create trigger trg_selections_set_updated_at
  before update on builder.selections
  for each row execute function private.set_updated_at();

-- History writer. SECURITY DEFINER so that authenticated, which has no insert privilege on
-- selection_history, still gets a history row for every change it makes.
create or replace function private.record_selection_history()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_action   text;
  v_org_id   uuid;
  v_slot_id  uuid;
  v_product  text;
  v_actor    text;
begin
  if tg_op = 'INSERT' then
    v_action := 'set';    v_org_id := new.org_id; v_slot_id := new.slot_id; v_product := new.product_name;
  elsif tg_op = 'UPDATE' then
    if new.product_name = old.product_name then
      return null;  -- nothing changed; not activity
    end if;
    v_action := 'change'; v_org_id := new.org_id; v_slot_id := new.slot_id; v_product := new.product_name;
  else
    v_action := 'clear';  v_org_id := old.org_id; v_slot_id := old.slot_id; v_product := null;
  end if;

  -- Who acted, from the caller's membership. No signed-in user (a job, the SQL editor) is staff.
  v_actor := case
    when auth.uid() is not null and exists (
      select 1 from public.memberships m
       where m.user_id = auth.uid() and m.org_id = v_org_id)
    then 'builder'
    else 'staff'
  end;

  insert into builder.selection_history
    (org_id, slot_id, action, product_name, changed_by, actor_kind)
  values
    (v_org_id, v_slot_id, v_action, v_product, auth.uid(), v_actor);

  return null;
end;
$$;

revoke execute on function private.record_selection_history() from public, anon, authenticated;

drop trigger if exists trg_selections_history on builder.selections;
create trigger trg_selections_history
  after insert or update or delete on builder.selections
  for each row execute function private.record_selection_history();

create or replace function private.reject_history_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception 'builder.selection_history is append-only' using errcode = '42501';
end;
$$;

revoke execute on function private.reject_history_mutation() from public, anon, authenticated;

drop trigger if exists trg_selection_history_append_only on builder.selection_history;
create trigger trg_selection_history_append_only
  before update or delete on builder.selection_history
  for each row execute function private.reject_history_mutation();
