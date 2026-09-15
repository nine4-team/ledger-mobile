-- Importing observed custody does not establish the date of a physical move.
alter table public.spike_item_placements
  add column start_evidence text not null default 'recorded_move'
  check (start_evidence in ('recorded_move','import_observation'));
grant select (start_evidence) on public.spike_item_placements to authenticated;

create function ledger_private.guard_placement_start_evidence() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if new.start_evidence is distinct from old.start_evidence then
    raise exception using errcode='55000', message='Placement start evidence is immutable';
  end if;
  return new;
end;
$$;
revoke all on function ledger_private.guard_placement_start_evidence() from public,anon,authenticated,service_role;
create trigger spike_item_placements_start_evidence before update on public.spike_item_placements
  for each row execute function ledger_private.guard_placement_start_evidence();
