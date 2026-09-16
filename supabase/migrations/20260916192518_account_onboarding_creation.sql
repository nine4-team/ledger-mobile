-- Online onboarding only. No caller-provided owner, role or Account identity.
create function ledger_private.prepare_authenticated_principal()
returns text language plpgsql security definer set search_path='' as $$
declare actor uuid := (select auth.uid()); principal text;
begin
  if actor is null or coalesce((select auth.jwt())->>'is_anonymous','false') <> 'false' then
    raise exception using errcode='42501',message='authentication_required';
  end if;
  -- The FK proves this subject exists in Auth. The unique subject binding
  -- serializes concurrent first entry; never match or merge by email/metadata.
  insert into public.spike_principals(id,auth_user_id) values(gen_random_uuid()::text,actor)
    on conflict(auth_user_id) do nothing;
  select id into principal from public.spike_principals where auth_user_id=actor;
  if principal is null then
    raise exception using errcode='42501',message='identity_not_linked';
  end if;
  return principal;
end;
$$;
revoke all on function ledger_private.prepare_authenticated_principal() from public,anon,authenticated,service_role;
grant usage on schema ledger_private to authenticated;
grant execute on function ledger_private.prepare_authenticated_principal() to authenticated;
create function public.spike_prepare_authenticated_principal()
returns text language sql security invoker set search_path='' as $$
  select ledger_private.prepare_authenticated_principal();
$$;
revoke all on function public.spike_prepare_authenticated_principal() from public,anon,authenticated,service_role;
grant execute on function public.spike_prepare_authenticated_principal() to authenticated;

create table ledger_private.account_creation_receipts (
  auth_user_id uuid not null references auth.users(id),
  request_id uuid not null,
  account_id text not null references public.spike_accounts(id),
  display_name text not null,
  primary key (auth_user_id, request_id)
);
create index account_creation_receipts_account_idx on ledger_private.account_creation_receipts(account_id);
alter table ledger_private.account_creation_receipts enable row level security;
revoke all on ledger_private.account_creation_receipts from public, anon, authenticated, service_role;

create function ledger_private.create_initial_account(p_request_id uuid, p_display_name text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare
  actor uuid := (select auth.uid());
  principal text;
  result_account text;
  saved_name text;
  created_time timestamptz := statement_timestamp();
  created_ms bigint := floor(extract(epoch from statement_timestamp()) * 1000)::bigint;
begin
  -- A waiter must read fresh membership/receipt state after the Principal lock.
  -- Snapshot isolation could otherwise retain the pre-lock empty directory.
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode='25001', message='Account creation requires READ COMMITTED';
  end if;
  if actor is null or coalesce((select auth.jwt())->>'is_anonymous', 'false') <> 'false' then
    raise exception using errcode='42501', message='authentication_required';
  end if;
  if p_request_id is null or p_display_name is null or btrim(p_display_name) = ''
    or p_display_name <> btrim(p_display_name) or char_length(p_display_name) > 80
    or octet_length(p_display_name) > 200 or p_display_name ~ '[[:cntrl:]]' then
    raise exception using errcode='22023', message='invalid_account_creation';
  end if;
  -- Serialize this identity's concurrent submissions, including different keys.
  select id into principal from public.spike_principals where auth_user_id=actor for update;
  if principal is null then
    raise exception using errcode='42501', message='identity_not_linked';
  end if;
  select account_id, display_name into result_account, saved_name
    from ledger_private.account_creation_receipts where auth_user_id=actor and request_id=p_request_id;
  if found then
    if saved_name <> p_display_name then
      raise exception using errcode='22023', message='account_creation_retry_mismatch';
    end if;
    if not exists(select 1 from public.spike_account_memberships
      where account_id=result_account and principal_id=principal and state='active') then
      raise exception using errcode='42501', message='account_access_unavailable';
    end if;
    return jsonb_build_object('accountId',result_account,'displayName',saved_name);
  end if;
  if exists(select 1 from public.spike_account_memberships where principal_id=principal and state='active') then
    raise exception using errcode='42501', message='account_already_available';
  end if;
  result_account := gen_random_uuid()::text;
  insert into public.spike_accounts(id,display_name) values(result_account,p_display_name);
  insert into public.spike_account_memberships(account_id,principal_id,role,state,
    can_manage_clients,can_manage_projects,can_manage_project_budgets,financial_access)
    values(result_account,principal,'owner','active',true,true,true,'full');
  insert into public.spike_budget_categories(id,account_id,display_name,kind,
    excludes_from_overall_budget,presentation_order,created_at,updated_at,created_at_ms,updated_at_ms)
    select result_account || ':' || seed.suffix,result_account,seed.name,seed.kind,
      seed.excluded,seed.position,created_time,created_time,created_ms,created_ms
    from (values ('furnishings','Furnishings','itemized',false,0),
      ('install','Install','general',false,1),
      ('design-fee','Design Fee','fee',true,2),
      ('storage-receiving','Storage & Receiving','general',false,3))
      as seed(suffix,name,kind,excluded,position);
  update public.spike_accounts set furnishings_category_id=result_account || ':furnishings'
    where id=result_account;
  insert into ledger_private.account_creation_receipts values(actor,p_request_id,result_account,p_display_name);
  return jsonb_build_object('accountId',result_account,'displayName',p_display_name);
end;
$$;
revoke all on function ledger_private.create_initial_account(uuid,text) from public,anon,authenticated,service_role;
grant usage on schema ledger_private to authenticated;
grant execute on function ledger_private.create_initial_account(uuid,text) to authenticated;
create function public.spike_create_initial_account(p_request_id uuid,p_display_name text)
returns jsonb language sql security invoker set search_path='' as $$
  select ledger_private.create_initial_account(p_request_id,p_display_name);
$$;
revoke all on function public.spike_create_initial_account(uuid,text) from public,anon,authenticated,service_role;
grant execute on function public.spike_create_initial_account(uuid,text) to authenticated;
