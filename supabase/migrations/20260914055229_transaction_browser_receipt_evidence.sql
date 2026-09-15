-- Share receipt evidence, not a persisted or independently calculated audit flag.
-- Invoker views retain current category/tenant RLS and explicit column grants.
create view ledger_private.transaction_receipt_display with (security_invoker=true) as
select t.id,t.account_id,
  jsonb_build_object('accountId',t.account_id,'transactionId',t.id,
    'principalId',ledger_private.current_principal_id(),
    'scopeKind',t.scope_kind,'projectId',t.project_id,'clientId',t.client_id,'type',t.type,
    'amountMinorUnits',t.amount_minor_units::text,'currency',t.currency,
    'category',jsonb_build_object('id',c.id,'name',c.display_name,'kind',c.kind,'revision',c.revision::text),
    'nonItemReceiptLines',t.non_item_receipt_lines,
    'items',coalesce((select jsonb_agg(jsonb_build_object('itemId',i.item_id,
      'amountMinorUnits',i.amount_minor_units::text,'membershipKind',i.membership_kind,
      'name',coalesce(item.name,item.description),'sku',item.sku) order by i.item_id)
      from public.transaction_receipt_items i
      left join public.spike_items item on item.account_id=i.account_id and item.id=i.item_id
      where i.account_id=t.account_id and i.transaction_id=t.id),'[]'::jsonb)) as payload
from public.spike_transactions t join public.spike_budget_categories c on c.account_id=t.account_id and c.id=t.category_id
where t.origin='vendor_payment';
revoke all on ledger_private.transaction_receipt_display from public,anon,authenticated,service_role;
grant select on ledger_private.transaction_receipt_display to authenticated;

create or replace function public.spike_read_transaction_receipt(p_account_id text,p_transaction_id text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
  if (select auth.uid()) is null then raise exception using errcode='28000',message='authentication required'; end if;
  if not ledger_private.has_active_membership(p_account_id) then
    raise exception using errcode='42501',message='account_not_authorized';
  end if;
  select payload into result from ledger_private.transaction_receipt_display where account_id=p_account_id and id=p_transaction_id;
  if result is null then raise exception using errcode='42501',message='transaction_not_available'; end if;
  return result;
end;
$$;
revoke all on function public.spike_read_transaction_receipt(text,text) from public,anon,authenticated,service_role;
grant execute on function public.spike_read_transaction_receipt(text,text) to authenticated;

create or replace view ledger_private.transaction_display with (security_invoker=true) as
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
      'id',c.id,'name',c.display_name,'kind',c.kind,'revision',c.revision::text) end,
    'receipt',r.payload) as payload
from public.spike_transactions t
left join public.spike_budget_categories c on c.account_id=t.account_id and c.id=t.category_id
left join ledger_private.transaction_receipt_display r on r.account_id=t.account_id and r.id=t.id;
revoke all on ledger_private.transaction_display from public,anon,authenticated,service_role;
grant select on ledger_private.transaction_display to authenticated;
