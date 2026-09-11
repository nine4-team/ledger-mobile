-- One explicit small derivative per original/recipe. Bytes remain in the
-- existing immutable image-object store, not a second media namespace.
create table public.item_card_thumbnails (
 id text primary key check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id)<=128),
 account_id text not null,
 original_attachment_id text not null,
 thumbnail_attachment_id text not null,
 recipe text not null check (recipe='item-card-300-jpeg-v1'),
 pixel_width integer not null check (pixel_width between 1 and 300),
 pixel_height integer not null check (pixel_height between 1 and 300),
 check (original_attachment_id<>thumbnail_attachment_id),
 foreign key(account_id,original_attachment_id) references public.item_image_objects(account_id,id),
 foreign key(account_id,thumbnail_attachment_id) references public.item_image_objects(account_id,id),
 unique(account_id,original_attachment_id,recipe)
);
create index item_card_thumbnails_object_idx
 on public.item_card_thumbnails(account_id,thumbnail_attachment_id);
-- Object metadata is immutable, so checking it once at publication preserves
-- this recipe invariant. Encoded dimensions/hash require byte verification by
-- the trusted publisher; database metadata alone cannot establish derivation.
create function ledger_private.check_item_card_thumbnail_recipe() returns trigger
 language plpgsql security invoker set search_path='' as $$
begin
 if exists (select 1 from public.item_image_objects o
   where o.account_id=new.account_id and o.id=new.thumbnail_attachment_id
     and o.media_type<>'image/jpeg') then
   raise exception 'Item card thumbnail recipe requires JPEG' using errcode='23514';
 end if;
 return new;
end;
$$;
revoke all on function ledger_private.check_item_card_thumbnail_recipe()
 from public,anon,authenticated,service_role;
create trigger item_card_thumbnails_recipe before insert on public.item_card_thumbnails
 for each row execute function ledger_private.check_item_card_thumbnail_recipe();
create trigger item_card_thumbnails_immutable before update or delete on public.item_card_thumbnails
 for each row execute function ledger_private.guard_immutable_image_object();
create trigger item_card_thumbnails_no_truncate before truncate on public.item_card_thumbnails
 for each statement execute function ledger_private.guard_immutable_image_object();

alter table public.item_card_thumbnails enable row level security;
alter table public.item_card_thumbnails force row level security;
revoke all on public.item_card_thumbnails from public,anon,authenticated,service_role;
grant select on public.item_card_thumbnails to authenticated;
-- References already restrict reads to the current Item-set revision. Do not
-- join image_objects here: its policy consults this link and would recurse.
create policy item_card_thumbnails_reference_read on public.item_card_thumbnails
 for select to authenticated using (
   (select ledger_private.has_active_membership(account_id)) and exists (
     select 1 from public.item_image_references r
     where r.account_id=item_card_thumbnails.account_id
       and r.attachment_id=item_card_thumbnails.original_attachment_id
   )
 );
alter policy item_image_objects_reference_read on public.item_image_objects using (
 (select ledger_private.has_active_membership(account_id)) and (
   exists (select 1 from public.item_image_references r
     where r.account_id=item_image_objects.account_id and r.attachment_id=item_image_objects.id)
   or exists (select 1 from public.item_card_thumbnails t
     where t.account_id=item_image_objects.account_id and t.thumbnail_attachment_id=item_image_objects.id)
 )
);
-- Existing authenticated Storage GET policy consults visible image_objects,
-- so it now accepts a derivative only through an authorized live original.
-- No authenticated upload/publication/delete API is added by this migration.

-- Trusted publication of metadata only. The caller must separately verify and
-- upload the derivative bytes; this function cannot establish their existence,
-- encoded dimensions, digest, or derivation from the original.
create function ledger_private.publish_item_card_thumbnail(
 p_account_id text, p_original_attachment_id text, p_original_sha256 text,
 p_original_byte_count bigint, p_original_media_type text, p_original_storage_path text,
 p_thumbnail_attachment_id text, p_thumbnail_sha256 text, p_thumbnail_byte_count bigint,
 p_thumbnail_media_type text, p_thumbnail_storage_path text,
 p_link_id text, p_recipe text, p_pixel_width integer, p_pixel_height integer
) returns text language plpgsql security invoker set search_path='' as $$
declare
 original public.item_image_objects;
 proposed_object public.item_image_objects;
 stored_object public.item_image_objects;
 proposed_link public.item_card_thumbnails;
 stored_link public.item_card_thumbnails;
begin
 -- Serialize competing recipe publications before checking or inserting either
 -- record. No API role can acquire this publication authority via EXECUTE.
 select * into original from public.item_image_objects
 where account_id=p_account_id and id=p_original_attachment_id for update;
 if not found then
   raise exception 'Thumbnail publication requires the exact existing Account original' using errcode='23503';
 end if;
 if row(original.content_sha256,original.byte_count,original.media_type,original.storage_path)
   is distinct from row(p_original_sha256,p_original_byte_count,p_original_media_type,p_original_storage_path) then
   raise exception 'Thumbnail publication conflicts with original metadata' using errcode='22000';
 end if;
 proposed_object.id:=p_thumbnail_attachment_id;
 proposed_object.account_id:=p_account_id;
 proposed_object.content_sha256:=p_thumbnail_sha256;
 proposed_object.byte_count:=p_thumbnail_byte_count;
 proposed_object.media_type:=p_thumbnail_media_type;
 proposed_object.storage_path:=p_thumbnail_storage_path;
 proposed_link.id:=p_link_id;
 proposed_link.account_id:=p_account_id;
 proposed_link.original_attachment_id:=p_original_attachment_id;
 proposed_link.thumbnail_attachment_id:=p_thumbnail_attachment_id;
 proposed_link.recipe:=p_recipe;
 proposed_link.pixel_width:=p_pixel_width;
 proposed_link.pixel_height:=p_pixel_height;

 select * into stored_link from public.item_card_thumbnails
 where account_id=p_account_id and original_attachment_id=p_original_attachment_id and recipe=p_recipe;
 if found then
   select * into stored_object from public.item_image_objects where id=p_thumbnail_attachment_id;
   if not found or stored_link is distinct from proposed_link or stored_object is distinct from proposed_object then
     raise exception 'Thumbnail publication conflicts with existing recipe evidence' using errcode='22000';
   end if;
   return stored_link.id;
 end if;

 -- Reuse only an exactly matching immutable object. ON CONFLICT also handles
 -- another original concurrently proposing the same derivative ID/path.
 insert into public.item_image_objects select proposed_object.* on conflict do nothing;
 select * into stored_object from public.item_image_objects where id=p_thumbnail_attachment_id;
 if not found or stored_object is distinct from proposed_object then
   raise exception 'Thumbnail publication conflicts with existing object evidence' using errcode='22000';
 end if;
 insert into public.item_card_thumbnails select proposed_link.* on conflict do nothing;
 if not found then
   -- Raising aborts this publication, including any object inserted above.
   raise exception 'Thumbnail publication conflicts with existing link identity' using errcode='22000';
 end if;
 return p_link_id;
end;
$$;
revoke all on function ledger_private.publish_item_card_thumbnail(
 text,text,text,bigint,text,text,text,text,bigint,text,text,text,text,integer,integer)
 from public,anon,authenticated,service_role;
