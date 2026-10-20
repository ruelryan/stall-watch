-- Covering indexes for the composite foreign keys.
--
-- WHY. The Performance Advisor reports "Unindexed foreign keys" for the five composite keys
-- (child_id, org_id) → parent (id, org_id). Each child already has an index whose first column
-- is the referencing id, but the linter (and Postgres, when a parent row is updated or deleted)
-- wants an index on the full key. These are small tables, so the cost is negligible and the
-- advisor goes quiet for the real reason, not by dismissal.
--
-- WHAT. One index per composite foreign key:
--   1. builder.project_slots (project_id, org_id)
--   2. builder.selections (slot_id, org_id)
--   3. builder.selection_history (slot_id, org_id)
--   4. builder.alerts (project_id, org_id)
--   5. builder.stall_episodes (project_id, org_id)
--
-- The advisor's "Unused index" notes are expected on a database that has only just been
-- created; they are left alone and should be re-checked after real use.
--
-- NOT SELF-CONTAINED. Nothing.
--
-- ROLLBACK:
--   drop index if exists builder.stall_episodes_project_org_idx;
--   drop index if exists builder.alerts_project_org_idx;
--   drop index if exists builder.selection_history_slot_org_idx;
--   drop index if exists builder.selections_slot_org_idx;
--   drop index if exists builder.project_slots_project_org_idx;

create index if not exists project_slots_project_org_idx     on builder.project_slots (project_id, org_id);
create index if not exists selections_slot_org_idx           on builder.selections (slot_id, org_id);
create index if not exists selection_history_slot_org_idx    on builder.selection_history (slot_id, org_id);
create index if not exists alerts_project_org_idx            on builder.alerts (project_id, org_id);
create index if not exists stall_episodes_project_org_idx    on builder.stall_episodes (project_id, org_id);
