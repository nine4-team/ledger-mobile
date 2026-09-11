-- Historical Firebase notes default creator names to an empty string. Preserve
-- that fact rather than rejecting the note or inventing a name. New-write
-- validation belongs to its command, not this historical storage constraint.
do $$
declare constraint_name text; matching_count integer;
begin
  select count(*), min(conname::text) into matching_count, constraint_name
  from pg_constraint where conrelid = 'public.spike_project_notes'::regclass
    and contype = 'c' and pg_get_constraintdef(oid) like '%creator_display_name%';
  if matching_count <> 1 then
    raise exception 'Expected exactly one historical creator-name constraint';
  end if;
  execute format('alter table public.spike_project_notes drop constraint %I', constraint_name);
end;
$$;
-- PostgreSQL text already rejects NUL. Grants, RLS and principal FKs are unchanged.
