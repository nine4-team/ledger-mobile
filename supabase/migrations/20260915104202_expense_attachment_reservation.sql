-- A pending Expense may own receipt bytes before its creation command uploads.
-- These are unverified claims, not an Expense or a payment Transaction.
create table ledger_private.expense_attachment_uploads (
  id text primary key check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id)<=128),
  account_id text not null,
  project_id text not null,
  expense_id text not null check (expense_id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(expense_id)<=128),
  principal_id text not null references public.spike_principals(id),
  content_sha256 text not null check (content_sha256 ~ '^[0-9a-f]{64}$'),
  byte_count bigint not null check (byte_count between 1 and 67108864),
  media_type text not null check (media_type ~ '^image/[a-z0-9][a-z0-9.+-]{0,126}$' or media_type='application/pdf'),
  file_name text,
  storage_path text generated always as ('accounts/'||account_id||'/attachments/'||id||'/'||content_sha256) stored unique,
  created_at timestamptz not null default clock_timestamp(),
  foreign key (account_id,project_id) references public.spike_projects(account_id,id)
);
create index expense_attachment_uploads_parent on ledger_private.expense_attachment_uploads(account_id,project_id,expense_id);
create index expense_attachment_uploads_actor on ledger_private.expense_attachment_uploads(principal_id);
alter table ledger_private.expense_attachment_uploads enable row level security;
alter table ledger_private.expense_attachment_uploads force row level security;
revoke all on ledger_private.expense_attachment_uploads from public,anon,authenticated,service_role;

create function ledger_private.can_use_expense_attachment_upload(p_path text) returns boolean
language sql stable security definer set search_path='' as $$
  select (select auth.uid()) is not null and exists (
    select 1 from ledger_private.expense_attachment_uploads u
    join public.spike_principals actor on actor.id=u.principal_id and actor.auth_user_id=(select auth.uid())
    join public.spike_account_memberships m on m.account_id=u.account_id and m.principal_id=u.principal_id
      and m.state='active' and m.financial_access='full'
    join public.spike_projects p on p.account_id=u.account_id and p.id=u.project_id and p.lifecycle='active'
    join public.spike_clients c on c.account_id=p.account_id and c.id=p.client_id and c.lifecycle='active'
    where u.storage_path=p_path
  )
$$;
revoke all on function ledger_private.can_use_expense_attachment_upload(text) from public,anon,authenticated,service_role;
grant execute on function ledger_private.can_use_expense_attachment_upload(text) to authenticated;

create function ledger_private.begin_expense_attachment_upload(
  p_id text,p_account_id text,p_project_id text,p_expense_id text,p_content_sha256 text,
  p_byte_count bigint,p_media_type text,p_file_name text
) returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text; client text; u ledger_private.expense_attachment_uploads;
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
  perform pg_advisory_xact_lock(hashtextextended(p_id,0));
  select * into u from ledger_private.expense_attachment_uploads where id=p_id;
  if not found then
    -- This endpoint supports creation, not the unresolved edit/paid-append policy.
    if exists(select 1 from ledger_private.expenses where id=p_expense_id) then
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
revoke all on function ledger_private.begin_expense_attachment_upload(text,text,text,text,text,bigint,text,text) from public,anon,authenticated,service_role;
grant execute on function ledger_private.begin_expense_attachment_upload(text,text,text,text,text,bigint,text,text) to authenticated;
create function public.spike_begin_expense_attachment_upload(
  p_id text,p_account_id text,p_project_id text,p_expense_id text,p_content_sha256 text,
  p_byte_count bigint,p_media_type text,p_file_name text
) returns jsonb language sql security invoker set search_path='' as $$
  select ledger_private.begin_expense_attachment_upload(p_id,p_account_id,p_project_id,p_expense_id,p_content_sha256,p_byte_count,p_media_type,p_file_name)
$$;
revoke all on function public.spike_begin_expense_attachment_upload(text,text,text,text,text,bigint,text,text) from public,anon,authenticated,service_role;
grant execute on function public.spike_begin_expense_attachment_upload(text,text,text,text,text,bigint,text,text) to authenticated;

create policy expense_attachment_reserved_upload on storage.objects for insert to authenticated with check (
  bucket_id='ledger-attachments' and ledger_private.can_use_expense_attachment_upload(name)
);
create policy expense_attachment_reserved_read on storage.objects for select to authenticated using (
  bucket_id='ledger-attachments' and storage.allow_any_operation(array['object.get_authenticated','object.get_authenticated_info'])
  and ledger_private.can_use_expense_attachment_upload(name)
);
