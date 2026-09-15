-- Reviewed local db pull: omit local replication/owner grants and false drops
-- of private functions hidden from the CLI role. Include data backfill explicitly.
-- This is a derived replication predicate, not Item history or an editable count.
begin;
lock table public.spike_item_placements in share row exclusive mode;
alter table public.spike_spaces add column sync_current_item_count bigint not null default 0
  constraint spike_spaces_sync_current_item_count_check check (sync_current_item_count >= 0);
update public.spike_spaces space set sync_current_item_count = present.count
from (select account_id,space_id,count(*) as count from public.spike_item_placements
  where ended_at is null and space_id is not null group by account_id,space_id) present
where space.account_id=present.account_id and space.id=present.space_id;

create function ledger_private.update_space_sync_item_count() returns trigger
language plpgsql security invoker set search_path='' as $$
declare delta record;
begin
  if tg_op='INSERT' then
    for delta in select account_id,space_id,count(*) as amount from new_placements
      where ended_at is null and space_id is not null
      group by account_id,space_id order by account_id,space_id
    loop
      update public.spike_spaces set sync_current_item_count=sync_current_item_count+delta.amount
        where account_id=delta.account_id and id=delta.space_id;
      if not found then raise exception using errcode='23503', message='Missing exact Space parent'; end if;
    end loop;
  elsif tg_op='UPDATE' then
    -- guard_item_placement_history permits only closing an active interval.
    -- It forbids reparenting/reopening, so each old current row leaves once.
    for delta in select account_id,space_id,count(*) as amount from old_placements
      where ended_at is null and space_id is not null
      group by account_id,space_id order by account_id,space_id
    loop
      update public.spike_spaces set sync_current_item_count=sync_current_item_count-delta.amount
        where account_id=delta.account_id and id=delta.space_id;
      if not found then raise exception using errcode='23503', message='Missing exact Space parent'; end if;
    end loop;
  end if;
  return null;
end;
$$;
revoke all on function ledger_private.update_space_sync_item_count() from public,anon,authenticated,service_role;
create trigger spike_item_placements_sync_space_insert after insert on public.spike_item_placements
  referencing new table as new_placements for each statement execute function ledger_private.update_space_sync_item_count();
create trigger spike_item_placements_sync_space_close after update on public.spike_item_placements
  referencing old table as old_placements for each statement execute function ledger_private.update_space_sync_item_count();
commit;
