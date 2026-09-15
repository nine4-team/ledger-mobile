-- Remaining reviewed portion of the local routing pull, including data backfill.
-- Canonical accounting guards/permissions remain intact; only derived routing changes.
begin;
lock table public.spike_item_placements,public.spike_item_project_categories,
  ledger_private.item_client_payment_connections,ledger_private.item_charge_occurrences,
  ledger_private.collected_invoice_lines in share row exclusive mode;
alter table public.spike_item_project_categories add column sync_is_current boolean not null default false;
alter table ledger_private.item_client_payment_connections add column sync_is_current boolean not null default false;
alter table ledger_private.item_charge_occurrences add column sync_is_current boolean not null default false;
alter table ledger_private.collected_invoice_lines add column sync_is_current boolean not null default false;

-- Exact composite placement FKs already prove Account/Item/Project identity.
-- This flag copies only placement currency, not payment/charge validity.
create function ledger_private.derive_placement_sync_current() returns trigger
language plpgsql security invoker set search_path='' as $$
declare placement_key text;
begin
  if tg_op='UPDATE' and row(new.id,new.account_id,new.project_id,new.item_id,to_jsonb(new)->>'placement_id')
    is distinct from row(old.id,old.account_id,old.project_id,old.item_id,to_jsonb(old)->>'placement_id') then
    -- Keep the canonical guard's identity rejection ahead of routing lookup errors.
    new.sync_is_current:=old.sync_is_current;
    return new;
  end if;
  if tg_table_name='spike_item_project_categories' then placement_key:=new.id;
  else placement_key:=new.placement_id; end if;
  select (p.ended_at is null and p.scope_kind='project') into new.sync_is_current
    from public.spike_item_placements p where p.account_id=new.account_id and p.id=placement_key
      and p.item_id=new.item_id and p.project_id=new.project_id for share;
  if not found then raise exception using errcode='23503',message='Missing exact routing placement'; end if;
  return new;
end;
$$;
create function ledger_private.derive_invoice_line_sync_current() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  new.sync_is_current:=false;
  if new.source_kind='item' then
    -- Use the collection guard's lock before looking up a possibly absent source.
    -- Otherwise concurrent source creation could leave a valid line unrouted.
    perform ledger_private.lock_item_charge_source(new.account_id,new.source_id);
    select c.sync_is_current and c.withdrawn_at is null into new.sync_is_current
      from ledger_private.item_charge_occurrences c
      where c.account_id=new.account_id and c.id=new.source_id for share;
    new.sync_is_current:=coalesce(new.sync_is_current,false);
  end if;
  return new;
end;
$$;
create trigger aaa_categories_derive_sync_current before insert or update on public.spike_item_project_categories
  for each row execute function ledger_private.derive_placement_sync_current();
create trigger aaa_connections_derive_sync_current before insert or update on ledger_private.item_client_payment_connections
  for each row execute function ledger_private.derive_placement_sync_current();
create trigger aaa_charges_derive_sync_current before insert or update on ledger_private.item_charge_occurrences
  for each row execute function ledger_private.derive_placement_sync_current();
create trigger aaa_invoice_lines_derive_sync_current before insert or update on ledger_private.collected_invoice_lines
  for each row execute function ledger_private.derive_invoice_line_sync_current();

-- Preserve each original guard for every canonical change, no-op, deletion and
-- insertion. Only an actual derived-only flag change bypasses its UPDATE guard.
-- Earlier derive triggers overwrite supplied flag values before this condition.
drop trigger spike_item_project_categories_update on public.spike_item_project_categories;
create trigger spike_item_project_categories_update before update on public.spike_item_project_categories
  for each row when (old.sync_is_current is not distinct from new.sync_is_current
    or (to_jsonb(old)-'sync_is_current') is distinct from (to_jsonb(new)-'sync_is_current'))
  execute function ledger_private.guard_item_project_category();
create trigger spike_item_project_categories_delete before delete on public.spike_item_project_categories
  for each row execute function ledger_private.guard_item_project_category();
drop trigger item_client_payment_connection_history on ledger_private.item_client_payment_connections;
create trigger item_client_payment_connection_history before update on ledger_private.item_client_payment_connections
  for each row when (old.sync_is_current is not distinct from new.sync_is_current
    or row(old.id,old.account_id,old.project_id,old.client_id,old.item_id,old.placement_id,
      old.transaction_id,old.started_at,old.started_by_principal_id,old.ended_at,old.ended_by_principal_id)
      is distinct from row(new.id,new.account_id,new.project_id,new.client_id,new.item_id,new.placement_id,
      new.transaction_id,new.started_at,new.started_by_principal_id,new.ended_at,new.ended_by_principal_id))
  execute function ledger_private.guard_item_client_payment_connection();
create trigger item_client_payment_connection_delete before delete on ledger_private.item_client_payment_connections
  for each row execute function ledger_private.guard_item_client_payment_connection();
drop trigger item_charge_occurrences_update on ledger_private.item_charge_occurrences;
create trigger item_charge_occurrences_update before update on ledger_private.item_charge_occurrences
  for each row when (old.sync_is_current is not distinct from new.sync_is_current
    or (to_jsonb(old)-'sync_is_current') is distinct from (to_jsonb(new)-'sync_is_current'))
  execute function ledger_private.guard_item_charge_occurrence();
create trigger item_charge_occurrences_insert_delete before insert or delete on ledger_private.item_charge_occurrences
  for each row execute function ledger_private.guard_item_charge_occurrence();
drop trigger collected_invoice_line_immutable on ledger_private.collected_invoice_lines;
create trigger collected_invoice_line_immutable before update on ledger_private.collected_invoice_lines
  for each row when (old.sync_is_current is not distinct from new.sync_is_current
    or (to_jsonb(old)-'sync_is_current') is distinct from (to_jsonb(new)-'sync_is_current'))
  execute function ledger_private.guard_collected_invoice();
create trigger collected_invoice_line_delete before delete on ledger_private.collected_invoice_lines
  for each row execute function ledger_private.guard_collected_invoice();

create function ledger_private.propagate_placement_sync_current() returns trigger
language plpgsql security invoker set search_path='' as $$
declare is_current boolean:=(new.ended_at is null and new.scope_kind='project');
begin
  update public.spike_item_project_categories set sync_is_current=is_current
    where account_id=new.account_id and id=new.id and sync_is_current is distinct from is_current;
  update ledger_private.item_client_payment_connections set sync_is_current=is_current
    where account_id=new.account_id and placement_id=new.id and sync_is_current is distinct from is_current;
  update ledger_private.item_charge_occurrences set sync_is_current=is_current
    where account_id=new.account_id and placement_id=new.id and sync_is_current is distinct from is_current;
  return null;
end;
$$;
create function ledger_private.propagate_charge_sync_current() returns trigger
language plpgsql security invoker set search_path='' as $$
declare is_current boolean:=new.sync_is_current and new.withdrawn_at is null;
begin
  update ledger_private.collected_invoice_lines set sync_is_current=is_current
    where account_id=new.account_id and source_kind='item' and source_id=new.id
      and sync_is_current is distinct from is_current;
  return null;
end;
$$;
create trigger placements_propagate_sync_current after update on public.spike_item_placements
  for each row execute function ledger_private.propagate_placement_sync_current();
create trigger charges_propagate_sync_current after update on ledger_private.item_charge_occurrences
  for each row when (old.sync_is_current is distinct from new.sync_is_current or old.withdrawn_at is distinct from new.withdrawn_at)
  execute function ledger_private.propagate_charge_sync_current();
revoke all on function ledger_private.derive_placement_sync_current(),ledger_private.derive_invoice_line_sync_current(),
  ledger_private.propagate_placement_sync_current(),ledger_private.propagate_charge_sync_current()
  from public,anon,authenticated,service_role;
update public.spike_item_project_categories c set sync_is_current=true from public.spike_item_placements p
  where c.account_id=p.account_id and c.id=p.id and p.ended_at is null and p.scope_kind='project';
update ledger_private.item_client_payment_connections c set sync_is_current=true from public.spike_item_placements p
  where c.account_id=p.account_id and c.placement_id=p.id and p.ended_at is null and p.scope_kind='project';
update ledger_private.item_charge_occurrences c set sync_is_current=true from public.spike_item_placements p
  where c.account_id=p.account_id and c.placement_id=p.id and p.ended_at is null and p.scope_kind='project';
update ledger_private.collected_invoice_lines l set sync_is_current=true from ledger_private.item_charge_occurrences c
  where l.account_id=c.account_id and l.source_kind='item' and l.source_id=c.id
    and c.sync_is_current and c.withdrawn_at is null and not l.sync_is_current;
commit;
