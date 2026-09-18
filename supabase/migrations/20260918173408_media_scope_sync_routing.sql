-- Derived sync routing only: original media and historical references remain
-- authoritative. One object per scope preserves shared-reference retention.
begin;
lock table public.item_image_sets,public.item_image_references,public.item_card_thumbnails,
  public.space_media_sets,public.space_media_references in share row exclusive mode;
alter table public.item_image_references add column sync_project_id text,
  add column sync_is_current boolean not null default false;
alter table public.space_media_references add column sync_is_current boolean not null default false;

create table ledger_private.media_sync_objects (
  id text primary key,
  account_id text not null,
  scope_kind text not null check(scope_kind in ('item','project','space')),
  scope_id text not null,
  attachment_id text not null,
  content_sha256 text not null,
  byte_count bigint not null,
  media_type text not null,
  storage_path text not null,
  unique(account_id,scope_kind,scope_id,attachment_id)
);
-- This private derived projection deliberately has no object FK. Canonical
-- objects cannot be deleted (immutable guard), and canonical references retain
-- their Account/object FKs. An extra FK here would take KEY SHARE locks on every
-- Project original during a rebuild and invert with an unrelated thumbnail
-- publisher's original lock. Only refresh_media_sync_scope populates these rows.
create table ledger_private.media_sync_thumbnails (
  id text primary key,
  account_id text not null,
  scope_kind text not null check(scope_kind in ('item','project')),
  scope_id text not null,
  thumbnail_link_id text not null,
  original_attachment_id text not null,
  thumbnail_attachment_id text not null,
  recipe text not null,
  pixel_width integer not null,
  pixel_height integer not null,
  unique(account_id,scope_kind,scope_id,thumbnail_link_id)
);
alter table ledger_private.media_sync_objects enable row level security;
alter table ledger_private.media_sync_objects force row level security;
alter table ledger_private.media_sync_thumbnails enable row level security;
alter table ledger_private.media_sync_thumbnails force row level security;
revoke all on ledger_private.media_sync_objects,ledger_private.media_sync_thumbnails from public,anon,authenticated,service_role;

create function ledger_private.refresh_media_sync_scope(a text,k text,s text) returns void
language plpgsql security invoker set search_path='' as $$
begin
  if s is null then return; end if;
  -- All publishers affecting a shared scope serialize before reading its
  -- references. Fresh statements after this lock see a preceding commit.
  perform pg_advisory_xact_lock(hashtextextended(jsonb_build_array('media_sync',a,k,s)::text,0));
  delete from ledger_private.media_sync_thumbnails where account_id=a and scope_kind=k and scope_id=s;
  insert into ledger_private.media_sync_thumbnails
  select jsonb_build_array(a,k,s,t.id)::text,a,k,s,t.id,t.original_attachment_id,
    t.thumbnail_attachment_id,t.recipe,t.pixel_width,t.pixel_height
  from public.item_card_thumbnails t
  where t.account_id=a and exists (
    select 1 from public.item_image_references r
    where r.account_id=a and r.attachment_id=t.original_attachment_id and r.sync_is_current
      and ((k='item' and r.item_id=s) or (k='project' and r.sync_project_id=s))
  );
  delete from ledger_private.media_sync_objects where account_id=a and scope_kind=k and scope_id=s;
  insert into ledger_private.media_sync_objects
  select jsonb_build_array(a,k,s,o.id)::text,a,k,s,o.id,o.content_sha256,o.byte_count,o.media_type,o.storage_path
  from public.item_image_objects o where o.account_id=a and (
    exists(select 1 from public.item_image_references r where r.account_id=a
      and r.attachment_id=o.id and r.sync_is_current
      and ((k='item' and r.item_id=s) or (k='project' and r.sync_project_id=s)))
    or (k='space' and exists(select 1 from public.space_media_references r
      where r.account_id=a and r.space_id=s and r.attachment_id=o.id and r.sync_is_current))
    or exists(select 1 from ledger_private.media_sync_thumbnails t
      where t.account_id=a and t.scope_kind=k and t.scope_id=s and t.thumbnail_attachment_id=o.id)
  );
end;
$$;

create function ledger_private.derive_media_reference_sync_scope() returns trigger
language plpgsql security invoker set search_path='' as $$
declare current_revision bigint;
begin
  if tg_table_name='item_image_references' then
    if tg_op='DELETE' then
      perform 1 from public.item_image_sets where account_id=old.account_id and item_id=old.item_id for update;
    else
      select revision,sync_project_id into current_revision,new.sync_project_id
        from public.item_image_sets where account_id=new.account_id and item_id=new.item_id for update;
    end if;
  else
    perform 1 from public.space_media_sets where account_id=coalesce(new.account_id,old.account_id)
      and space_id=coalesce(new.space_id,old.space_id) for update;
    select revision into current_revision from public.space_media_sets
      where account_id=coalesce(new.account_id,old.account_id) and space_id=coalesce(new.space_id,old.space_id);
  end if;
  -- The verified publisher already owns the marker before changing references.
  -- Keep that same marker -> original order for trusted inserts and deletes.
  -- NO KEY UPDATE serializes original publishers without blocking the KEY SHARE
  -- foreign-key checks when another scope retains this immutable object.
  perform 1 from public.item_image_objects
    where account_id=coalesce(new.account_id,old.account_id)
      and id in (new.attachment_id,old.attachment_id) order by id for no key update;
  if tg_op='DELETE' then return old; end if;
  new.sync_is_current := coalesce(new.set_revision=current_revision,false);
  return new;
end;
$$;
create function ledger_private.propagate_media_set_sync_scope() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if tg_table_name='item_image_sets' then
    -- The publisher advances all existing references and then inserts its new
    -- private upload object (admission rejects an already existing object ID).
    -- Acquire every existing original before any scope
    -- lock, so a thumbnail publisher cannot hold the next original while
    -- waiting on a scope acquired for an earlier reference in this gallery.
    perform 1 from public.item_image_objects where account_id=new.account_id
      and id in (select attachment_id from public.item_image_references
        where account_id=new.account_id and item_id=new.item_id) order by id for no key update;
    update public.item_image_references set sync_is_current=(set_revision=new.revision),sync_project_id=new.sync_project_id
      where account_id=new.account_id and item_id=new.item_id;
  else
    perform 1 from public.item_image_objects where account_id=new.account_id
      and id in (select attachment_id from public.space_media_references
        where account_id=new.account_id and space_id=new.space_id) order by id for no key update;
    update public.space_media_references set sync_is_current=(set_revision=new.revision)
      where account_id=new.account_id and space_id=new.space_id;
  end if;
  return null;
end;
$$;
create function ledger_private.refresh_media_reference_sync_scope() returns trigger
language plpgsql security invoker set search_path='' as $$
declare a text; parent_id text; p text;
begin
  a := coalesce(new.account_id,old.account_id);
  if tg_table_name='item_image_references' then
    parent_id := coalesce(new.item_id,old.item_id);
    -- Project before Item in every refresh path, including shared thumbnails.
    -- Sort both placement scopes. A removed reference cannot withdraw another
    -- Item's media. Trusted multi-row writers must prelock their parent marker;
    -- a row trigger cannot reorder a tuple lock already taken by arbitrary SQL.
    for p in select distinct value from unnest(array[new.sync_project_id,old.sync_project_id]) value
      where value is not null order by value loop
      perform ledger_private.refresh_media_sync_scope(a,'project',p);
    end loop;
    perform ledger_private.refresh_media_sync_scope(a,'item',parent_id);
  else
    parent_id := coalesce(new.space_id,old.space_id);
    perform ledger_private.refresh_media_sync_scope(a,'space',parent_id);
  end if;
  return null;
end;
$$;
create function ledger_private.refresh_thumbnail_sync_scopes() returns trigger
language plpgsql security invoker set search_path='' as $$
declare r record; a text; original_id text;
begin
  a := coalesce(new.account_id,old.account_id);
  original_id := coalesce(new.original_attachment_id,old.original_attachment_id);
  for r in select distinct 'item'::text as kind,item_id as scope from public.item_image_references
      where account_id=a and attachment_id=original_id and sync_is_current
    union select distinct 'project',sync_project_id from public.item_image_references
      where account_id=a and attachment_id=original_id and sync_is_current and sync_project_id is not null
    order by kind desc,scope loop
    perform ledger_private.refresh_media_sync_scope(a,r.kind,r.scope);
  end loop;
  return null;
end;
$$;
create function ledger_private.lock_thumbnail_sync_original() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  perform 1 from public.item_image_objects where account_id=new.account_id and id=new.original_attachment_id for no key update;
  return new;
end;
$$;
create trigger a_thumbnail_sync_original before insert on public.item_card_thumbnails
  for each row execute function ledger_private.lock_thumbnail_sync_original();
create trigger a_media_reference_sync_scope before insert or update or delete on public.item_image_references
  for each row execute function ledger_private.derive_media_reference_sync_scope();
create trigger a_media_reference_sync_scope before insert or update or delete on public.space_media_references
  for each row execute function ledger_private.derive_media_reference_sync_scope();
create trigger media_reference_sync_scope after insert or update or delete on public.item_image_references
  for each row execute function ledger_private.refresh_media_reference_sync_scope();
create trigger media_reference_sync_scope after insert or update or delete on public.space_media_references
  for each row execute function ledger_private.refresh_media_reference_sync_scope();
create trigger media_set_sync_scope after update on public.item_image_sets
  for each row when (row(old.revision,old.sync_project_id) is distinct from row(new.revision,new.sync_project_id))
  execute function ledger_private.propagate_media_set_sync_scope();
create trigger media_set_sync_scope after update on public.space_media_sets
  for each row when (old.revision is distinct from new.revision)
  execute function ledger_private.propagate_media_set_sync_scope();
create trigger thumbnail_sync_scopes after insert or update or delete on public.item_card_thumbnails
  for each row execute function ledger_private.refresh_thumbnail_sync_scopes();
revoke all on function ledger_private.refresh_media_sync_scope(text,text,text),
  ledger_private.derive_media_reference_sync_scope(),ledger_private.propagate_media_set_sync_scope(),
  ledger_private.refresh_media_reference_sync_scope(),ledger_private.refresh_thumbnail_sync_scopes(),ledger_private.lock_thumbnail_sync_original()
  from public,anon,authenticated,service_role;

-- Backfill flags once, then each scope once; avoid repeatedly rebuilding a
-- large Project for every historical reference during migration.
alter table public.item_image_references disable trigger media_reference_sync_scope;
alter table public.space_media_references disable trigger media_reference_sync_scope;
update public.item_image_references set sync_is_current=sync_is_current;
update public.space_media_references set sync_is_current=sync_is_current;
set constraints all immediate;
alter table public.item_image_references enable trigger media_reference_sync_scope;
alter table public.space_media_references enable trigger media_reference_sync_scope;
do $$ declare r record; begin
  for r in select account_id,'item'::text as kind,item_id as scope from public.item_image_sets
    union select account_id,'project',sync_project_id from public.item_image_sets where sync_project_id is not null
    union select account_id,'space',space_id from public.space_media_sets
    order by account_id,kind,scope loop
    perform ledger_private.refresh_media_sync_scope(r.account_id,r.kind,r.scope);
  end loop;
end $$;
create index item_image_reference_sync_project on public.item_image_references(account_id,sync_project_id) where sync_is_current;
do $$ begin
  if exists(select 1 from pg_publication where pubname='powersync') then
    alter publication powersync add table ledger_private.media_sync_objects,ledger_private.media_sync_thumbnails;
  end if;
end $$;
commit;
