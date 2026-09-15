-- Reviewed local db pull. Omit local service roles/grants and visibility-induced
-- false drops of private functions, views and existing attachment tables.
begin;
-- Canonical parents remain authority. Freeze writes while installing/backfilling
-- derived routing; no native/API writer is responsible for these columns.
lock table public.spike_transactions, public.transaction_receipt_items,
  public.transaction_attachment_sets, public.transaction_attachment_references in share row exclusive mode;
alter table public.transaction_receipt_items
  add column sync_scope_kind text, add column sync_project_id text, add column sync_category_id text;
alter table public.transaction_attachment_sets
  add column sync_scope_kind text, add column sync_project_id text, add column sync_category_id text;
alter table public.transaction_attachment_references
  add column sync_scope_kind text, add column sync_project_id text, add column sync_category_id text,
  add column sync_is_current boolean,
  add column sync_content_sha256 text, add column sync_byte_count bigint,
  add column sync_media_type text, add column sync_storage_path text;

create function ledger_private.derive_transaction_sync_scope() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  select t.scope_kind,t.project_id,t.category_id
    into new.sync_scope_kind,new.sync_project_id,new.sync_category_id
    from public.spike_transactions t where t.account_id=new.account_id and t.id=new.transaction_id for share;
  if not found then raise exception using errcode='23503',message='Missing exact Transaction sync parent'; end if;
  return new;
end;
$$;
create function ledger_private.derive_transaction_attachment_sync_reference() returns trigger
language plpgsql security invoker set search_path='' as $$
declare current_revision bigint;
begin
  -- The earlier alphabetic scope trigger locks the Transaction first.
  select s.revision into current_revision from public.transaction_attachment_sets s
    where s.account_id=new.account_id and s.transaction_id=new.transaction_id and s.section=new.section for share;
  if not found then raise exception using errcode='23503',message='Missing exact Transaction attachment marker'; end if;
  new.sync_is_current := new.set_revision=current_revision;
  -- Objects are already immutable. Copy their protected descriptor, never bytes,
  -- so current scoped references need no bucket per object to obtain it offline.
  select o.content_sha256,o.byte_count,o.media_type,o.storage_path
    into new.sync_content_sha256,new.sync_byte_count,new.sync_media_type,new.sync_storage_path
    from public.item_image_objects o where o.account_id=new.account_id and o.id=new.attachment_id;
  if not found then raise exception using errcode='23503',message='Missing exact Transaction attachment object'; end if;
  return new;
end;
$$;
create function ledger_private.propagate_transaction_sync_scope() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  update public.transaction_receipt_items set sync_scope_kind=new.scope_kind,
    sync_project_id=new.project_id,sync_category_id=new.category_id
    where account_id=new.account_id and transaction_id=new.id;
  update public.transaction_attachment_sets set sync_scope_kind=new.scope_kind,
    sync_project_id=new.project_id,sync_category_id=new.category_id
    where account_id=new.account_id and transaction_id=new.id;
  -- Marker propagation also updates its references in this same transaction.
  return null;
end;
$$;
create function ledger_private.propagate_transaction_attachment_sync_marker() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  update public.transaction_attachment_references set sync_is_current=(set_revision=new.revision),
    sync_scope_kind=new.sync_scope_kind,sync_project_id=new.sync_project_id,sync_category_id=new.sync_category_id
    where account_id=new.account_id and transaction_id=new.transaction_id and section=new.section;
  return null;
end;
$$;
revoke all on function ledger_private.derive_transaction_sync_scope(),
  ledger_private.derive_transaction_attachment_sync_reference(),
  ledger_private.propagate_transaction_sync_scope(),ledger_private.propagate_transaction_attachment_sync_marker()
  from public,anon,authenticated,service_role;
create trigger transaction_receipt_items_sync_scope before insert or update on public.transaction_receipt_items
  for each row execute function ledger_private.derive_transaction_sync_scope();
create trigger transaction_attachment_sets_sync_scope before insert or update on public.transaction_attachment_sets
  for each row execute function ledger_private.derive_transaction_sync_scope();
create trigger transaction_attachment_references_sync_1_scope before insert or update on public.transaction_attachment_references
  for each row execute function ledger_private.derive_transaction_sync_scope();
create trigger transaction_attachment_references_sync_2_descriptor before insert or update on public.transaction_attachment_references
  for each row execute function ledger_private.derive_transaction_attachment_sync_reference();
create trigger transactions_sync_children after update on public.spike_transactions
  for each row when (row(old.scope_kind,old.project_id,old.category_id) is distinct from row(new.scope_kind,new.project_id,new.category_id))
  execute function ledger_private.propagate_transaction_sync_scope();
create trigger transaction_attachment_sets_sync_references after update on public.transaction_attachment_sets
  for each row when (row(old.revision,old.sync_scope_kind,old.sync_project_id,old.sync_category_id)
    is distinct from row(new.revision,new.sync_scope_kind,new.sync_project_id,new.sync_category_id))
  execute function ledger_private.propagate_transaction_attachment_sync_marker();

update public.transaction_receipt_items set sync_scope_kind=sync_scope_kind;
update public.transaction_attachment_sets set sync_scope_kind=sync_scope_kind;
update public.transaction_attachment_references set sync_scope_kind=sync_scope_kind;
alter table public.transaction_receipt_items alter column sync_scope_kind set not null;
alter table public.transaction_attachment_sets alter column sync_scope_kind set not null;
alter table public.transaction_attachment_references
  alter column sync_scope_kind set not null, alter column sync_is_current set not null,
  alter column sync_content_sha256 set not null, alter column sync_byte_count set not null,
  alter column sync_media_type set not null, alter column sync_storage_path set not null;
commit;
