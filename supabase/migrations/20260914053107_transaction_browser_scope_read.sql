-- Full financial visibility is Account authority, not current Item placement.
-- Keep unknown collected-payment classification full-only (O-060), current
-- vendor category policy, immutable source/payment facts, and all writer grants.
drop policy transaction_authorized_read on public.spike_transactions;
create policy transaction_authorized_read on public.spike_transactions
for select to authenticated using (
  (origin='firebase_client_payment' and exists (
    select 1 from public.spike_principals principal
    join public.spike_account_memberships membership on membership.principal_id=principal.id
    where principal.auth_user_id=(select auth.uid()) and membership.account_id=spike_transactions.account_id
      and membership.state='active' and membership.financial_access='full'
  )) or (origin='vendor_payment' and exists (
    select 1 from public.spike_budget_categories category
    where category.account_id=spike_transactions.account_id and category.id=spike_transactions.category_id
      and ledger_private.can_view_budget_category(category.account_id,category.visibility_class)
  ))
);
create index spike_transactions_browser_scope_idx
  on public.spike_transactions(account_id,scope_kind,project_id,id);

-- One explicit display projection shared by list/detail RPCs. Invoker security
-- retains underlying column grants and RLS; future private columns do not leak.
create view ledger_private.transaction_display with (security_invoker=true) as
select t.id,t.account_id,t.scope_kind,t.project_id,t.client_id,
  jsonb_build_object(
    'accountId',t.account_id,'principalId',ledger_private.current_principal_id(),
    'transactionId',t.id,'scopeKind',t.scope_kind,'projectId',t.project_id,'clientId',t.client_id,
    'type',t.type,'role',t.role,'origin',t.origin,
    'amountMinorUnits',t.amount_minor_units::text,'currency',t.currency,
    'source',t.source,'transactionDate',to_char(t.transaction_date,'YYYY-MM-DD'),
    'createdAtMilliseconds',t.created_at_ms::text,'notes',t.notes,
    'paymentMethod',t.payment_method,'hasEmailReceipt',t.has_email_receipt,
    'category',case when c.id is null then null else jsonb_build_object(
      'id',c.id,'name',c.display_name,'kind',c.kind,'revision',c.revision::text) end) as payload
from public.spike_transactions t
left join public.spike_budget_categories c on c.account_id=t.account_id and c.id=t.category_id;
revoke all on ledger_private.transaction_display from public,anon,authenticated,service_role;
grant select on ledger_private.transaction_display to authenticated;

create or replace function public.spike_read_transaction_detail(p_account_id text,p_transaction_id text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
  if (select auth.uid()) is null then raise exception using errcode='28000',message='authentication required'; end if;
  if not ledger_private.has_active_membership(p_account_id) then
    raise exception using errcode='42501',message='account_not_authorized';
  end if;
  select payload into result from ledger_private.transaction_display
    where account_id=p_account_id and id=p_transaction_id;
  if result is null then raise exception using errcode='42501',message='transaction_not_available'; end if;
  return result;
end;
$$;
revoke all on function public.spike_read_transaction_detail(text,text) from public,anon,authenticated,service_role;
grant execute on function public.spike_read_transaction_detail(text,text) to authenticated;

create function public.spike_read_transaction_list(p_account_id text,p_scope_kind text,p_project_id text default null)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare scope_client text; result jsonb;
begin
  if (select auth.uid()) is null then raise exception using errcode='28000',message='authentication required'; end if;
  if not ledger_private.has_active_membership(p_account_id) then
    raise exception using errcode='42501',message='account_not_authorized';
  end if;
  if p_scope_kind is null or p_scope_kind not in ('project','business_inventory')
    or (p_scope_kind='project' and p_project_id is null)
    or (p_scope_kind='business_inventory' and p_project_id is not null) then
    raise exception using errcode='22023',message='transaction_scope_invalid';
  end if;
  if p_scope_kind='project' then
    select client_id into scope_client from public.spike_projects where account_id=p_account_id and id=p_project_id;
    if scope_client is null then raise exception using errcode='42501',message='transaction_scope_not_available'; end if;
  end if;
  select coalesce(jsonb_agg(payload order by id),'[]'::jsonb) into result from ledger_private.transaction_display
    where account_id=p_account_id and scope_kind=p_scope_kind and project_id is not distinct from p_project_id;
  return jsonb_build_object('accountId',p_account_id,'principalId',ledger_private.current_principal_id(),
    'scopeKind',p_scope_kind,'projectId',p_project_id,'clientId',scope_client,
    'coverage','partial','transactions',result);
  -- All currently implemented canonical origins, not proof of Transfer or new
  -- collection-writer completion. Callers must not present a complete empty list.
end;
$$;
revoke all on function public.spike_read_transaction_list(text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.spike_read_transaction_list(text,text,text) to authenticated;
