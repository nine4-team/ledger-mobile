-- Immutable originals and separately scoped Item references. This is a read
-- boundary only; no upload, primary-change, detach, or purge API is authorized.
create table public.item_image_objects (
 id text primary key check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id)<=128),
 account_id text not null references public.spike_accounts(id),
 content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
 byte_count bigint not null check (byte_count>0),
 media_type text not null check (media_type ~ '^image/[a-z0-9][a-z0-9.+-]{0,126}$'),
 storage_path text not null unique,
 unique(account_id,id),
 check (storage_path='accounts/'||account_id||'/attachments/'||id||'/'||content_sha256)
);
create table public.item_image_sets (
 id text primary key,
 account_id text not null,
 item_id text not null,
 revision bigint not null check (revision>0),
 expected_count integer not null check (expected_count>=0),
 check (id=item_id),
 unique(account_id,item_id),
 foreign key(account_id,item_id) references public.spike_items(account_id,id)
);
create table public.item_image_references (
 id text primary key check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id)<=128),
 account_id text not null,
 item_id text not null,
 attachment_id text not null,
 set_revision bigint not null check (set_revision>0),
 position integer not null check (position>=0),
 is_primary boolean not null,
 foreign key(account_id,item_id) references public.item_image_sets(account_id,item_id),
 foreign key(account_id,attachment_id) references public.item_image_objects(account_id,id),
 unique(account_id,item_id,set_revision,position) deferrable initially deferred,
 unique(account_id,item_id,set_revision,attachment_id) deferrable initially deferred
);
create index item_image_references_attachment_idx on public.item_image_references(account_id,attachment_id);
-- Enforce across concurrent snapshots, not only the deferred set validator.
create unique index item_image_references_one_primary_idx
 on public.item_image_references(account_id,item_id,set_revision) where is_primary;
create function ledger_private.guard_image_reference_parent() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 if row(new.id,new.account_id,new.item_id) is distinct from row(old.id,old.account_id,old.item_id) then
   raise exception using errcode='55000',message='Item image parent identity is immutable';
 end if;
 return new;
end;
$$;
create trigger item_image_sets_parent_immutable before update on public.item_image_sets
 for each row execute function ledger_private.guard_image_reference_parent();
create trigger item_image_references_parent_immutable before update on public.item_image_references
 for each row execute function ledger_private.guard_image_reference_parent();

create function ledger_private.guard_immutable_image_object() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
 raise exception using errcode='55000',message='Original image object evidence is immutable';
end;
$$;
create trigger item_image_objects_immutable before update or delete on public.item_image_objects
 for each row execute function ledger_private.guard_immutable_image_object();
create trigger item_image_objects_no_truncate before truncate on public.item_image_objects
 for each statement execute function ledger_private.guard_immutable_image_object();

-- Retain prior set revisions as evidence. Only the marker's exact revision is
-- the current gallery; an absent marker is unknown, not known empty.
create function ledger_private.check_current_item_image_set() returns trigger
language plpgsql security invoker set search_path='' as $$
declare marker public.item_image_sets; actual_count bigint; primary_count bigint;
 first_position integer; last_position integer;
begin
 select * into marker from public.item_image_sets
 where account_id=coalesce(new.account_id,old.account_id)
 and item_id=coalesce(new.item_id,old.item_id) for update;
 if not found then return null; end if;
 select count(*),count(*) filter(where is_primary),min(position),max(position)
 into actual_count,primary_count,first_position,last_position
 from public.item_image_references
 where account_id=marker.account_id and item_id=marker.item_id and set_revision=marker.revision;
 if actual_count<>marker.expected_count or primary_count>1
   or (actual_count>0 and (first_position<>0 or last_position<>actual_count-1)) then
   raise exception using errcode='23514',message='Current Item image set is inconsistent';
 end if;
 return null;
end;
$$;
create constraint trigger item_image_set_consistency after insert or update on public.item_image_sets
 deferrable initially deferred for each row execute function ledger_private.check_current_item_image_set();
create constraint trigger item_image_reference_consistency after insert or update or delete on public.item_image_references
 deferrable initially deferred for each row execute function ledger_private.check_current_item_image_set();
revoke all on function ledger_private.guard_immutable_image_object(),ledger_private.check_current_item_image_set(),
 ledger_private.guard_image_reference_parent()
 from public,anon,authenticated,service_role;

alter table public.item_image_objects enable row level security;
alter table public.item_image_objects force row level security;
alter table public.item_image_sets enable row level security;
alter table public.item_image_sets force row level security;
alter table public.item_image_references enable row level security;
alter table public.item_image_references force row level security;
revoke all on public.item_image_objects,public.item_image_sets,public.item_image_references
 from public,anon,authenticated,service_role;
grant select on public.item_image_objects,public.item_image_sets,public.item_image_references to authenticated;
create policy item_image_sets_member_read on public.item_image_sets for select to authenticated
 using ((select ledger_private.has_active_membership(account_id)));
create policy item_image_references_member_read on public.item_image_references for select to authenticated
 using ((select ledger_private.has_active_membership(account_id)) and exists (
   select 1 from public.item_image_sets s where s.account_id=item_image_references.account_id
   and s.item_id=item_image_references.item_id and s.revision=item_image_references.set_revision));
create policy item_image_objects_reference_read on public.item_image_objects for select to authenticated
 using ((select ledger_private.has_active_membership(account_id)) and exists (
   select 1 from public.item_image_references r where r.account_id=item_image_objects.account_id
   and r.attachment_id=item_image_objects.id));
create policy ledger_item_image_download on storage.objects for select to authenticated
 using (bucket_id='ledger-attachments'
   and storage.operation() in ('object.get_authenticated','storage.object.get_authenticated')
   and exists (select 1 from public.item_image_objects image where image.storage_path=storage.objects.name
     and ledger_private.has_active_membership(image.account_id)));
