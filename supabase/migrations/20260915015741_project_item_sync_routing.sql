-- Reviewed local pull: include only tested routing changes and backfill.
-- Omit local-role grants and false drops of existing private/attachment objects.
begin;
lock table public.spike_items,public.spike_item_placements,public.item_image_sets in share row exclusive mode;
alter table public.spike_items add column sync_project_id text;
alter table public.item_image_sets add column sync_project_id text;

-- Routing is derived from the one current placement, never supplied by a client.
create function ledger_private.derive_item_sync_project() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  select p.project_id into new.sync_project_id from public.spike_item_placements p
    where p.account_id=new.account_id and p.item_id=new.id and p.ended_at is null;
  return new;
end;
$$;
create function ledger_private.derive_image_set_sync_project() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  select i.sync_project_id into new.sync_project_id from public.spike_items i
    where i.account_id=new.account_id and i.id=new.item_id for share;
  if not found then raise exception using errcode='23503',message='Missing exact Item sync parent'; end if;
  return new;
end;
$$;
create or replace function ledger_private.guard_item_identity() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if new.id is distinct from old.id or new.account_id is distinct from old.account_id
    or new.created_at is distinct from old.created_at
    or new.created_by_principal_id is distinct from old.created_by_principal_id then
    raise exception using errcode='55000',message='Item identity and creation evidence are immutable';
  end if;
  -- Database-derived routing must not invalidate an offline editable revision.
  -- The earlier derive trigger ignores any caller-supplied routing value.
  if (to_jsonb(new)-'sync_project_id') = (to_jsonb(old)-'sync_project_id') then return new; end if;
  if new.revision <> old.revision + 1 then
    raise exception using errcode='40001',message='Item update must advance revision exactly once';
  end if;
  return new;
end;
$$;
create function ledger_private.propagate_item_sync_project() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  update public.item_image_sets set sync_project_id=new.sync_project_id
    where account_id=new.account_id and item_id=new.id;
  return null;
end;
$$;
create function ledger_private.refresh_placement_item_sync_project() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  update public.spike_items set sync_project_id=sync_project_id
    where account_id=new.account_id and id=new.item_id;
  if not found then raise exception using errcode='23503',message='Missing exact placement Item'; end if;
  return null;
end;
$$;
create trigger spike_items_derive_sync_project before insert or update on public.spike_items
  for each row execute function ledger_private.derive_item_sync_project();
create trigger item_image_sets_derive_sync_project before insert or update on public.item_image_sets
  for each row execute function ledger_private.derive_image_set_sync_project();
create trigger spike_items_propagate_sync_project after update on public.spike_items
  for each row when (old.sync_project_id is distinct from new.sync_project_id)
  execute function ledger_private.propagate_item_sync_project();
create trigger spike_item_placements_sync_project after insert or update on public.spike_item_placements
  for each row execute function ledger_private.refresh_placement_item_sync_project();
revoke all on function ledger_private.derive_item_sync_project(),ledger_private.derive_image_set_sync_project(),
  ledger_private.propagate_item_sync_project(),ledger_private.refresh_placement_item_sync_project()
  from public,anon,authenticated,service_role;
update public.spike_items set sync_project_id=sync_project_id;
update public.item_image_sets set sync_project_id=sync_project_id;
commit;
