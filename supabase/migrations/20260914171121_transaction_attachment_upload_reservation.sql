-- Upload-only change from the locally tested schema. The generated pg-delta
-- diff included unrelated removals; those were discarded, never executed.
begin;
create table public.transaction_attachment_uploads (
 id text primary key check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id)<=128),
 account_id text not null,
 principal_id text not null references public.spike_principals(id),
 transaction_id text not null,
 section text not null check (section in ('receipts','other')),
 content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
 byte_count bigint not null check (byte_count between 1 and 67108864),
 media_type text not null check (media_type ~ '^image/[a-z0-9][a-z0-9.+-]{0,126}$'
   or (section='receipts' and media_type='application/pdf')),
 file_name text,
 local_position bigint not null check (local_position between 0 and 4294967295),
 make_primary_if_empty boolean not null,
 storage_path text generated always as ('accounts/'||account_id||'/attachments/'||id||'/'||content_sha256) stored unique,
 created_at timestamptz not null default clock_timestamp(),
 foreign key(account_id,transaction_id,section)
   references public.transaction_attachment_sets(account_id,transaction_id,section)
);
create index transaction_attachment_uploads_parent
 on public.transaction_attachment_uploads(account_id,transaction_id,section,principal_id);
alter table public.transaction_attachment_uploads enable row level security;
alter table public.transaction_attachment_uploads force row level security;
revoke all on public.transaction_attachment_uploads from public,anon,authenticated,service_role;
grant select on public.transaction_attachment_uploads to authenticated;
grant insert(id,account_id,principal_id,transaction_id,section,content_sha256,byte_count,
 media_type,file_name,local_position,make_primary_if_empty) on public.transaction_attachment_uploads to authenticated;
create policy transaction_attachment_uploads_read on public.transaction_attachment_uploads
 for select to authenticated using (
 principal_id=(select ledger_private.current_principal_id())
 and (select ledger_private.has_active_membership(account_id))
 and exists(select 1 from public.spike_transactions t where t.account_id=transaction_attachment_uploads.account_id
   and t.id=transaction_attachment_uploads.transaction_id)
);
create policy transaction_attachment_uploads_insert on public.transaction_attachment_uploads
 for insert to authenticated with check (
 principal_id=(select ledger_private.current_principal_id())
 and (select ledger_private.has_active_membership(account_id))
 and exists(select 1 from public.transaction_attachment_sets s where s.account_id=transaction_attachment_uploads.account_id
   and s.transaction_id=transaction_attachment_uploads.transaction_id and s.section=transaction_attachment_uploads.section
   and s.expected_count<50)
);

-- Invoker RLS preserves current parent/financial visibility. Exact retry does
-- not consume a slot even if the section has filled since initial reservation.
create function public.spike_begin_transaction_attachment_upload(
 p_id text,p_account_id text,p_transaction_id text,p_section text,p_content_sha256 text,
 p_byte_count bigint,p_media_type text,p_file_name text,p_local_position bigint,p_make_primary_if_empty boolean
) returns jsonb language plpgsql security invoker set search_path='' as $$
declare actor text; reservation public.transaction_attachment_uploads;
begin
 if (select auth.uid()) is null then raise sqlstate '28000' using message='authentication_required'; end if;
 actor := ledger_private.current_principal_id();
 select * into reservation from public.transaction_attachment_uploads where id=p_id;
 if not found then
   insert into public.transaction_attachment_uploads(id,account_id,principal_id,transaction_id,section,
     content_sha256,byte_count,media_type,file_name,local_position,make_primary_if_empty)
   values(p_id,p_account_id,actor,p_transaction_id,p_section,p_content_sha256,p_byte_count,
     p_media_type,p_file_name,p_local_position,p_make_primary_if_empty)
   on conflict(id) do nothing;
   select * into reservation from public.transaction_attachment_uploads where id=p_id;
 end if;
 if not found then raise sqlstate '42501' using message='attachment_upload_unavailable'; end if;
 if row(reservation.account_id,reservation.principal_id,reservation.transaction_id,reservation.section,
   reservation.content_sha256,reservation.byte_count,reservation.media_type,reservation.file_name,
   reservation.local_position,reservation.make_primary_if_empty)
   is distinct from row(p_account_id,actor,p_transaction_id,p_section,p_content_sha256,p_byte_count,
   p_media_type,p_file_name,p_local_position,p_make_primary_if_empty) then
   raise sqlstate 'PT409' using message='attachment_upload_identity_conflict';
 end if;
 return jsonb_build_object('attachmentId',reservation.id,'accountId',reservation.account_id,
   'principalId',reservation.principal_id,'transactionId',reservation.transaction_id,'section',reservation.section,
   'bucket','ledger-attachments','storagePath',reservation.storage_path,'contentSHA256',reservation.content_sha256,
   'byteCount',reservation.byte_count::text,'mediaType',reservation.media_type,'phase','awaiting_upload');
end;
$$;
revoke all on function public.spike_begin_transaction_attachment_upload(text,text,text,text,text,bigint,text,text,bigint,boolean)
 from public,anon,authenticated,service_role;
grant execute on function public.spike_begin_transaction_attachment_upload(text,text,text,text,text,bigint,text,text,bigint,boolean)
 to authenticated;

-- Unverified bytes stay uploader-only. No overwrite, delete, list or signed URL.
-- The later verifier/publication step must not trust these declared claims.
create policy transaction_attachment_reserved_upload on storage.objects
 for insert to authenticated with check (
 bucket_id='ledger-attachments' and exists(select 1 from public.transaction_attachment_uploads u
   where u.storage_path=storage.objects.name)
);
create policy transaction_attachment_reserved_read on storage.objects
 for select to authenticated using (
 bucket_id='ledger-attachments'
 and storage.operation() in ('object.get_authenticated','storage.object.get_authenticated')
 and exists(select 1 from public.transaction_attachment_uploads u where u.storage_path=storage.objects.name)
);
commit;
