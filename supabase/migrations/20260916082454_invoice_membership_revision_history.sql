-- Preserve repeated removal/re-addition in the existing membership facts.
-- Active-only sync identity and exclusive-source/position indexes are unchanged.
alter table ledger_private.live_invoice_memberships
  add column joined_at_revision bigint not null default 1 check(joined_at_revision>0);
alter table ledger_private.live_invoice_memberships drop constraint live_invoice_memberships_pkey;
alter table ledger_private.live_invoice_memberships add primary key
  (account_id,invoice_id,source_kind,source_id,joined_at_revision);

create function ledger_private.guard_live_invoice_membership_history() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if tg_op='UPDATE' and old.released_at is null and new.released_at is not null
    and (to_jsonb(old)-'released_at')=(to_jsonb(new)-'released_at') then
    return new;
  end if;
  raise sqlstate '55000' using message='Invoice membership history is immutable; release and replace';
end;
$$;
revoke all on function ledger_private.guard_live_invoice_membership_history() from public,anon,authenticated,service_role;
create trigger live_invoice_membership_history before update or delete on ledger_private.live_invoice_memberships
  for each row execute function ledger_private.guard_live_invoice_membership_history();
