-- Descriptive evidence only; preserve unknown versus explicit empty notes.
alter table public.spike_items add column notes text;
grant select (notes) on public.spike_items to authenticated;
-- Existing active-membership RLS applies; no command or financial grants.
