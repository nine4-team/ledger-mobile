-- Original vendor and immediate-origin presentation evidence are different.
-- Preserve both raw strings, including explicit blanks; do not infer origin
-- from current placement or mutable Transaction links. Future authorized move
-- commands must maintain current_source atomically while preserving source.
alter table public.spike_items
  add column source text,
  add column current_source text;
grant select (source, current_source) on public.spike_items to authenticated;
-- Existing active-member RLS applies. No defaults, backfill, or writer grants.
