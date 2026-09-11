-- Read-only source metadata, distinct from billing/accounting state. Preserve
-- unknown legacy status strings and absent bookmark evidence without defaults.
alter table public.spike_items
  add column workflow_status text,
  add column bookmark boolean;
grant select (workflow_status, bookmark) on public.spike_items to authenticated;
-- Existing active-member RLS applies; no INSERT/UPDATE/DELETE authority added.
