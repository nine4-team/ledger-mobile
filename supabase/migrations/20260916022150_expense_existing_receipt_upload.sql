-- Reuse receipt upload reservations for pre-collection Expense edits.
-- Uploading bytes never changes Expense membership or collected accounting.
create or replace function ledger_private.begin_expense_attachment_upload(
  p_id text,p_account_id text,p_project_id text,p_expense_id text,p_content_sha256 text,
  p_byte_count bigint,p_media_type text,p_file_name text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text; client text; u ledger_private.expense_attachment_uploads;
  source ledger_private.expenses;
begin
  if (select auth.uid()) is null then raise sqlstate '28000' using message='authentication_required'; end if;
  actor:=ledger_private.current_principal_id();
  perform 1 from public.spike_account_memberships where account_id=p_account_id and principal_id=actor
    and state='active' and financial_access='full' for share;
  if not found then raise sqlstate '42501' using message='expense_upload_unavailable'; end if;
  select client_id into client from public.spike_projects where account_id=p_account_id and id=p_project_id and lifecycle='active' for share;
  if not found then raise sqlstate '42501' using message='expense_upload_unavailable'; end if;
  perform 1 from public.spike_clients where account_id=p_account_id and id=client and lifecycle='active' for share;
  if not found then raise sqlstate '42501' using message='expense_upload_unavailable'; end if;
  if current_setting('transaction_isolation') <> 'read committed' then
    raise sqlstate '25001' using message='Expense uploads require READ COMMITTED';
  end if;
  select * into source from ledger_private.expenses where id=p_expense_id for update;
  if found and row(source.account_id,source.project_id) is distinct from row(p_account_id,p_project_id) then
    raise sqlstate '42501' using message='expense_upload_unavailable';
  end if;
  perform pg_advisory_xact_lock(hashtextextended(p_id,0));
  select * into u from ledger_private.expense_attachment_uploads where id=p_id;
  if not found then
    if exists(select 1 from ledger_private.collected_invoice_lines where account_id=p_account_id
      and source_kind='expense' and source_id=p_expense_id) then
      raise sqlstate '42501' using message='expense_upload_unavailable';
    end if;
    insert into ledger_private.expense_attachment_uploads(id,account_id,project_id,expense_id,principal_id,
      content_sha256,byte_count,media_type,file_name)
    values(p_id,p_account_id,p_project_id,p_expense_id,actor,p_content_sha256,p_byte_count,p_media_type,p_file_name)
    returning * into u;
  end if;
  if row(u.account_id,u.project_id,u.expense_id,u.principal_id,u.content_sha256,u.byte_count,u.media_type,u.file_name)
    is distinct from row(p_account_id,p_project_id,p_expense_id,actor,p_content_sha256,p_byte_count,p_media_type,p_file_name) then
    raise sqlstate 'PT409' using message='expense_upload_identity_conflict';
  end if;
  return jsonb_build_object('attachmentId',u.id,'accountId',u.account_id,'principalId',u.principal_id,
    'projectId',u.project_id,'expenseId',u.expense_id,'bucket','ledger-attachments','storagePath',u.storage_path,
    'contentSHA256',u.content_sha256,'byteCount',u.byte_count::text,'mediaType',u.media_type,'phase','awaiting_upload');
end;
$$;
revoke all on function ledger_private.begin_expense_attachment_upload(text,text,text,text,text,bigint,text,text) from public,anon,service_role;
grant execute on function ledger_private.begin_expense_attachment_upload(text,text,text,text,text,bigint,text,text) to authenticated;
