-- Initial Firebase Project.notes is distinct from description and individual notes.
-- Preserve exact text, including empty/whitespace-only values; NULL means absent.
-- Existing Project SELECT membership policy applies; no new write grant or RPC.
alter table public.spike_projects add column legacy_notes text;
comment on column public.spike_projects.legacy_notes is
  'Exact imported initial Project.notes; no inferred author or timestamp. Not individual Project notes.';
