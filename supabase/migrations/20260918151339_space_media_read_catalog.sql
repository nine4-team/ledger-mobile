-- Read-only Space catalog. Reuse protected media objects and Storage download
-- policy; this does not grant upload, removal, primary selection or marker edits.
create table public.space_media_sets (
  id text primary key check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id)<=128),
  account_id text not null,
  space_id text not null,
  revision bigint not null check (revision>0),
  expected_count integer not null check (expected_count>=0),
  unique(account_id,space_id),
  foreign key(account_id,space_id) references public.spike_spaces(account_id,id)
);
create table public.space_media_references (
  id text primary key check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id)<=128),
  account_id text not null,
  space_id text not null,
  attachment_id text not null,
  set_revision bigint not null check (set_revision>0),
  position integer not null check (position>=0),
  is_primary boolean not null,
  file_name text,
  foreign key(account_id,space_id) references public.space_media_sets(account_id,space_id),
  foreign key(account_id,attachment_id) references public.item_image_objects(account_id,id),
  unique(account_id,space_id,set_revision,position) deferrable initially deferred,
  unique(account_id,space_id,set_revision,attachment_id) deferrable initially deferred
);
create unique index space_media_one_primary on public.space_media_references(account_id,space_id,set_revision) where is_primary;
create index space_media_object_reference on public.space_media_references(account_id,attachment_id);
do $$ begin
  if exists(select 1 from pg_publication where pubname='powersync') then
    alter publication powersync add table public.space_media_sets, public.space_media_references;
  end if;
end $$;
alter table public.space_media_sets enable row level security;
alter table public.space_media_sets force row level security;
alter table public.space_media_references enable row level security;
alter table public.space_media_references force row level security;
revoke all on public.space_media_sets,public.space_media_references from public,anon,authenticated,service_role;
grant select on public.space_media_sets,public.space_media_references to authenticated;

create policy space_media_sets_read on public.space_media_sets for select to authenticated
using (exists(select 1 from public.spike_spaces s
  where s.account_id=space_media_sets.account_id and s.id=space_media_sets.space_id));
create policy space_media_references_read on public.space_media_references for select to authenticated
using (exists(select 1 from public.space_media_sets s
  where s.account_id=space_media_references.account_id and s.space_id=space_media_references.space_id
    and s.revision=space_media_references.set_revision));
-- Preserve every existing consumer in the single shared object policy.
alter policy item_image_objects_reference_read on public.item_image_objects
using ((select ledger_private.has_active_membership(item_image_objects.account_id)) and (
  exists(select 1 from public.item_image_references r
    where r.account_id=item_image_objects.account_id and r.attachment_id=item_image_objects.id)
  or exists(select 1 from public.item_card_thumbnails t
    where t.account_id=item_image_objects.account_id and t.thumbnail_attachment_id=item_image_objects.id)
  or exists(select 1 from public.transaction_attachment_references r
    where r.account_id=item_image_objects.account_id and r.attachment_id=item_image_objects.id)
  or ledger_private.can_read_expense_receipt(account_id,id)
  or exists(select 1 from public.space_media_references r
    where r.account_id=item_image_objects.account_id and r.attachment_id=item_image_objects.id)
));

create function ledger_private.guard_space_media_parent() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if row(new.id,new.account_id,new.space_id) is distinct from row(old.id,old.account_id,old.space_id) then
    raise exception using errcode='55000',message='Space media parent identity is immutable';
  end if;
  return new;
end;
$$;
create function ledger_private.check_space_media_set() returns trigger
language plpgsql security invoker set search_path='' as $$
declare marker public.space_media_sets; actual_count bigint; first_position integer; last_position integer;
begin
  select * into marker from public.space_media_sets
    where account_id=coalesce(new.account_id,old.account_id)
      and space_id=coalesce(new.space_id,old.space_id) for update;
  if not found then return null; end if;
  select count(*),min(position),max(position) into actual_count,first_position,last_position
    from public.space_media_references where account_id=marker.account_id
      and space_id=marker.space_id and set_revision=marker.revision;
  if actual_count<>marker.expected_count or
      (actual_count>0 and (first_position<>0 or last_position<>actual_count-1)) then
    raise exception using errcode='23514',message='Current Space media set is inconsistent';
  end if;
  return null;
end;
$$;
revoke all on function ledger_private.guard_space_media_parent(),ledger_private.check_space_media_set()
  from public,anon,authenticated,service_role;
create trigger space_media_sets_parent before update on public.space_media_sets
  for each row execute function ledger_private.guard_space_media_parent();
create trigger space_media_references_parent before update on public.space_media_references
  for each row execute function ledger_private.guard_space_media_parent();
create constraint trigger space_media_set_consistency after insert or update on public.space_media_sets
  deferrable initially deferred for each row execute function ledger_private.check_space_media_set();
create constraint trigger space_media_reference_consistency after insert or update or delete on public.space_media_references
  deferrable initially deferred for each row execute function ledger_private.check_space_media_set();
