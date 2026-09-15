-- Descriptive evidence belongs to the canonical Transaction. No backfill guesses:
-- in particular import time is not the original created time, and unknown email
-- receipt evidence is not false. No writer or accounting-lock change is granted.
alter table public.spike_transactions
  add column source text,
  add column transaction_date date,
  add column created_at_ms bigint,
  add column notes text,
  add column payment_method text,
  add column has_email_receipt boolean,
  add constraint spike_transactions_date_check check (
    transaction_date is null or transaction_date between date '0001-01-01' and date '9999-12-31');

grant select (source,transaction_date,created_at_ms,notes,payment_method,has_email_receipt)
  on public.spike_transactions to authenticated;

-- A detail read of an already-authorized Transaction, not a promise that all
-- Transaction origins or the whole browser working set are implemented. Keep
-- current financial RLS, including the imported-payment relationship boundary.
create function public.spike_read_transaction_detail(p_account_id text,p_transaction_id text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
  if (select auth.uid()) is null then
    raise exception using errcode='28000',message='authentication required';
  end if;
  if not ledger_private.has_active_membership(p_account_id) then
    raise exception using errcode='42501',message='account_not_authorized';
  end if;
  select jsonb_build_object(
    'accountId',t.account_id,'principalId',ledger_private.current_principal_id(),
    'transactionId',t.id,'scopeKind',t.scope_kind,'projectId',t.project_id,'clientId',t.client_id,
    'type',t.type,'role',t.role,'origin',t.origin,
    'amountMinorUnits',t.amount_minor_units::text,'currency',t.currency,
    'source',t.source,'transactionDate',to_char(t.transaction_date,'YYYY-MM-DD'),
    'createdAtMilliseconds',t.created_at_ms::text,'notes',t.notes,
    'paymentMethod',t.payment_method,'hasEmailReceipt',t.has_email_receipt,
    'category',case when c.id is null then null else jsonb_build_object(
      'id',c.id,'name',c.display_name,'kind',c.kind,'revision',c.revision::text) end)
  into result from public.spike_transactions t
  left join public.spike_budget_categories c on c.account_id=t.account_id and c.id=t.category_id
  where t.account_id=p_account_id and t.id=p_transaction_id;
  if result is null then
    raise exception using errcode='42501',message='transaction_not_available';
  end if;
  return result;
end;
$$;
revoke all on function public.spike_read_transaction_detail(text,text) from public,anon,authenticated,service_role;
grant execute on function public.spike_read_transaction_detail(text,text) to authenticated;
