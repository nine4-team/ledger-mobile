-- Authenticated verifier admission without exposing the private reservations table.
create function ledger_private.read_expense_attachment_upload(p_upload_id text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare u ledger_private.expense_attachment_uploads;
begin
  select * into u from ledger_private.expense_attachment_uploads where id=p_upload_id;
  if not found or not ledger_private.can_use_expense_attachment_upload(u.storage_path) then
    raise sqlstate '42501' using message='expense_upload_unavailable';
  end if;
  return to_jsonb(u)||jsonb_build_object('byte_count',u.byte_count::text);
end;
$$;
revoke all on function ledger_private.read_expense_attachment_upload(text) from public,anon,authenticated,service_role;
grant execute on function ledger_private.read_expense_attachment_upload(text) to authenticated;
create function public.spike_read_expense_attachment_upload(p_upload_id text)
returns jsonb language sql security invoker set search_path='' as $$
  select ledger_private.read_expense_attachment_upload(p_upload_id)
$$;
revoke all on function public.spike_read_expense_attachment_upload(text) from public,anon,authenticated,service_role;
grant execute on function public.spike_read_expense_attachment_upload(text) to authenticated;

-- Only the trusted byte verifier supplies observed values and authenticated user.
-- This publishes media, not an Expense reference: create_expense owns that atomic write.
create function ledger_private.publish_verified_expense_attachment(
  p_auth_user_id uuid,p_upload_id text,p_observed_sha256 text,
  p_observed_byte_count bigint,p_observed_media_type text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare u ledger_private.expense_attachment_uploads; stored public.item_image_objects; client text;
begin
  select upload.* into u from ledger_private.expense_attachment_uploads upload
    join public.spike_principals actor on actor.id=upload.principal_id and actor.auth_user_id=p_auth_user_id
    where upload.id=p_upload_id;
  if not found then raise sqlstate '42501' using message='expense_upload_unavailable'; end if;
  -- Same lock order as admission; authorization must hold even on a verified retry.
  perform 1 from public.spike_account_memberships where account_id=u.account_id and principal_id=u.principal_id
    and state='active' and financial_access='full' for share;
  if not found then raise sqlstate '42501' using message='expense_upload_unavailable'; end if;
  select client_id into client from public.spike_projects where account_id=u.account_id and id=u.project_id
    and lifecycle='active' for share;
  if not found then raise sqlstate '42501' using message='expense_upload_unavailable'; end if;
  perform 1 from public.spike_clients where account_id=u.account_id and id=client and lifecycle='active' for share;
  if not found then raise sqlstate '42501' using message='expense_upload_unavailable'; end if;
  perform pg_advisory_xact_lock(hashtextextended(p_upload_id,0));
  if row(p_observed_sha256,p_observed_byte_count,p_observed_media_type)
    is distinct from row(u.content_sha256,u.byte_count,u.media_type) then
    raise sqlstate 'PT409' using message='stored_bytes_mismatch';
  end if;
  if not exists(select 1 from storage.objects where bucket_id='ledger-attachments' and name=u.storage_path) then
    raise sqlstate 'PT409' using message='attachment_upload_incomplete';
  end if;
  insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
    values(u.id,u.account_id,u.content_sha256,u.byte_count,u.media_type,u.storage_path)
    on conflict (id) do nothing;
  select * into stored from public.item_image_objects where id=u.id;
  if row(stored.account_id,stored.content_sha256,stored.byte_count,stored.media_type,stored.storage_path)
    is distinct from row(u.account_id,u.content_sha256,u.byte_count,u.media_type,u.storage_path) then
    raise sqlstate 'PT409' using message='attachment_identity_conflict';
  end if;
  return jsonb_build_object('attachmentId',u.id,'accountId',u.account_id,'principalId',u.principal_id,
    'projectId',u.project_id,'expenseId',u.expense_id,'contentSHA256',u.content_sha256,
    'byteCount',u.byte_count::text,'mediaType',u.media_type,'phase','verified');
end;
$$;
revoke all on function ledger_private.publish_verified_expense_attachment(uuid,text,text,bigint,text) from public,anon,authenticated,service_role;
-- Keep service_role outside ledger_private; the narrowly granted wrapper is its only entry.
create function public.spike_publish_verified_expense_attachment(
  p_auth_user_id uuid,p_upload_id text,p_observed_sha256 text,p_observed_byte_count bigint,p_observed_media_type text
) returns jsonb language sql security definer set search_path='' as $$
  select ledger_private.publish_verified_expense_attachment(p_auth_user_id,p_upload_id,p_observed_sha256,p_observed_byte_count,p_observed_media_type)
$$;
revoke all on function public.spike_publish_verified_expense_attachment(uuid,text,text,bigint,text) from public,anon,authenticated,service_role;
grant execute on function public.spike_publish_verified_expense_attachment(uuid,text,text,bigint,text) to service_role;
