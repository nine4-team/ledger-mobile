-- Unverified original bytes for an existing Item. No accounting mutation and no
-- canonical reference until the trusted byte verifier publishes atomically.
create table ledger_private.item_attachment_uploads (
 id text primary key check(id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id)<=128),
 account_id text not null,
 item_id text not null,
 principal_id text not null references public.spike_principals(id),
 content_sha256 text not null check(content_sha256 ~ '^[0-9a-f]{64}$'),
 byte_count bigint not null check(byte_count between 1 and 67108864),
 media_type text not null check(media_type ~ '^image/[a-z0-9][a-z0-9.+-]{0,126}$'),
 file_name text,
 local_position bigint not null check(local_position between 0 and 4294967295),
 make_primary_if_empty boolean not null,
 storage_path text generated always as ('accounts/'||account_id||'/attachments/'||id||'/'||content_sha256) stored unique,
 created_at timestamptz not null default clock_timestamp(),
 foreign key(account_id,item_id) references public.spike_items(account_id,id)
);
create index item_attachment_uploads_parent on ledger_private.item_attachment_uploads(account_id,item_id);
create index item_attachment_uploads_actor on ledger_private.item_attachment_uploads(principal_id);
alter table ledger_private.item_attachment_uploads enable row level security;
alter table ledger_private.item_attachment_uploads force row level security;
revoke all on ledger_private.item_attachment_uploads from public,anon,authenticated,service_role;

create function ledger_private.can_use_item_attachment_upload(p_path text) returns boolean
language sql stable security definer set search_path='' as $$
 select (select auth.uid()) is not null and exists (
  select 1 from ledger_private.item_attachment_uploads u
  join public.spike_principals actor on actor.id=u.principal_id and actor.auth_user_id=(select auth.uid())
  join public.spike_account_memberships m on m.account_id=u.account_id and m.principal_id=u.principal_id and m.state='active'
  join public.spike_items i on i.account_id=u.account_id and i.id=u.item_id
  where u.storage_path=p_path
 )
$$;
revoke all on function ledger_private.can_use_item_attachment_upload(text) from public,anon,authenticated,service_role;
grant execute on function ledger_private.can_use_item_attachment_upload(text) to authenticated;

create function ledger_private.begin_item_attachment_upload(
 p_id text,p_account_id text,p_item_id text,p_content_sha256 text,p_byte_count bigint,
 p_media_type text,p_file_name text,p_local_position bigint,p_make_primary_if_empty boolean
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text; u ledger_private.item_attachment_uploads; marker public.item_image_sets;
begin
 if (select auth.uid()) is null then raise sqlstate '28000' using message='authentication_required'; end if;
 actor:=ledger_private.current_principal_id();
 perform 1 from public.spike_account_memberships where account_id=p_account_id and principal_id=actor
  and state='active' for share;
 if not found then raise sqlstate '42501' using message='item_upload_unavailable'; end if;
 perform 1 from public.spike_items where account_id=p_account_id and id=p_item_id for share;
 if not found then raise sqlstate '42501' using message='item_upload_unavailable'; end if;
 perform pg_advisory_xact_lock(hashtextextended(p_id,0));
 select * into u from ledger_private.item_attachment_uploads where id=p_id;
 if not found then
  select * into marker from public.item_image_sets where account_id=p_account_id and item_id=p_item_id for share;
  if not found then raise sqlstate '42501' using message='item_images_unknown'; end if;
  if marker.expected_count>=50 then raise sqlstate 'PT409' using message='item_gallery_full'; end if;
  if exists(select 1 from public.item_image_objects where id=p_id) then
   raise sqlstate 'PT409' using message='item_upload_identity_conflict';
  end if;
  insert into ledger_private.item_attachment_uploads(id,account_id,item_id,principal_id,content_sha256,
   byte_count,media_type,file_name,local_position,make_primary_if_empty)
  values(p_id,p_account_id,p_item_id,actor,p_content_sha256,p_byte_count,p_media_type,p_file_name,
   p_local_position,p_make_primary_if_empty) returning * into u;
 end if;
 if row(u.account_id,u.item_id,u.principal_id,u.content_sha256,u.byte_count,u.media_type,u.file_name,u.local_position,u.make_primary_if_empty)
  is distinct from row(p_account_id,p_item_id,actor,p_content_sha256,p_byte_count,p_media_type,p_file_name,p_local_position,p_make_primary_if_empty) then
  raise sqlstate 'PT409' using message='item_upload_identity_conflict';
 end if;
 return jsonb_build_object('attachmentId',u.id,'accountId',u.account_id,'principalId',u.principal_id,
  'itemId',u.item_id,'bucket','ledger-attachments','storagePath',u.storage_path,'contentSHA256',u.content_sha256,
  'byteCount',u.byte_count::text,'mediaType',u.media_type,'phase','awaiting_upload');
end;
$$;
revoke all on function ledger_private.begin_item_attachment_upload(text,text,text,text,bigint,text,text,bigint,boolean) from public,anon,authenticated,service_role;
grant execute on function ledger_private.begin_item_attachment_upload(text,text,text,text,bigint,text,text,bigint,boolean) to authenticated;
create function public.spike_begin_item_attachment_upload(
 p_id text,p_account_id text,p_item_id text,p_content_sha256 text,p_byte_count bigint,
 p_media_type text,p_file_name text,p_local_position bigint,p_make_primary_if_empty boolean
) returns jsonb language sql security invoker set search_path='' as $$
 select ledger_private.begin_item_attachment_upload(p_id,p_account_id,p_item_id,p_content_sha256,
  p_byte_count,p_media_type,p_file_name,p_local_position,p_make_primary_if_empty)
$$;
revoke all on function public.spike_begin_item_attachment_upload(text,text,text,text,bigint,text,text,bigint,boolean) from public,anon,authenticated,service_role;
grant execute on function public.spike_begin_item_attachment_upload(text,text,text,text,bigint,text,text,bigint,boolean) to authenticated;

create policy item_attachment_reserved_upload on storage.objects for insert to authenticated
 with check(bucket_id='ledger-attachments' and ledger_private.can_use_item_attachment_upload(name));
create policy item_attachment_reserved_read on storage.objects for select to authenticated
 using(bucket_id='ledger-attachments' and storage.allow_any_operation(array['object.get_authenticated','object.get_authenticated_info'])
  and ledger_private.can_use_item_attachment_upload(name));
