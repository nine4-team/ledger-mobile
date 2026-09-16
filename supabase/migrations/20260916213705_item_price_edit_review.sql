-- One statement snapshot for the same edit context used by native downloads.
create function ledger_private.read_item_price_edit(p_account_id text,p_project_id text,p_item_id text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  actor text:=ledger_private.current_principal_id(); n bigint; occurrence text;
  charge ledger_private.item_charge_occurrences; price ledger_private.item_project_prices;
  price_found boolean; cost_count bigint; cost bigint; cost_currency text;
begin
  if (select auth.uid()) is null or actor is null or not exists(
    select 1 from public.spike_account_memberships where account_id=p_account_id
      and principal_id=actor and state='active' and financial_access='full') then
    raise sqlstate '42501' using message='Item price access required';
  end if;
  select count(*),min(c.id) into n,occurrence
  from ledger_private.item_charge_occurrences c
  join public.spike_item_placements placement on placement.account_id=c.account_id
    and placement.id=c.placement_id and placement.item_id=c.item_id and placement.project_id=c.project_id
  join public.spike_projects project on project.account_id=c.account_id and project.id=c.project_id
  join public.spike_clients client on client.account_id=project.account_id and client.id=project.client_id
  where c.account_id=p_account_id and c.project_id=p_project_id and c.item_id=p_item_id
    and c.withdrawn_at is null and placement.scope_kind='project' and placement.ended_at is null
    and project.lifecycle='active' and client.lifecycle='active'
    and not exists(select 1 from ledger_private.collected_invoice_lines paid
      where paid.account_id=c.account_id and paid.source_kind='item' and paid.source_id=c.id);
  if n<>1 then raise sqlstate '22023' using message='Item price review unavailable'; end if;
  select * into charge from ledger_private.item_charge_occurrences where account_id=p_account_id and id=occurrence;
  select * into price from ledger_private.item_project_prices where account_id=p_account_id and item_id=p_item_id;
  price_found:=found;
  select count(*),min(r.amount_minor_units),min(r.currency) into cost_count,cost,cost_currency
  from public.transaction_receipt_items r join public.spike_transactions t
    on t.account_id=r.account_id and t.id=r.transaction_id
  where r.account_id=p_account_id and r.item_id=p_item_id and t.type='purchase';
  if cost_count>1 or (cost_count=1 and (cost is null or cost<0 or cost_currency<>charge.currency))
    or (price_found and (price.currency<>charge.currency or price.amount_minor_units<0
      or price.revision>=9223372036854775807)) or charge.revision>=9223372036854775807 then
    raise sqlstate '22023' using message='Item price review unavailable';
  end if;
  return jsonb_build_object('accountId',p_account_id,'principalId',actor,'projectId',p_project_id,
    'itemId',p_item_id,'placementId',charge.placement_id,'occurrenceId',charge.id,'currency',charge.currency,
    'priceRevision',case when price_found then price.revision::text else '0' end,
    'chargeRevision',charge.revision::text,
    'currentPrice',case when price_found then jsonb_build_object(
      'amountMinorUnits',price.amount_minor_units::text,'currency',price.currency) else null end,
    'purchaseCost',case when cost_count=0 then jsonb_build_object('state','absent')
      else jsonb_build_object('state','known','amountMinorUnits',cost::text,'currency',cost_currency) end);
end;
$$;
revoke all on function ledger_private.read_item_price_edit(text,text,text) from public,anon,service_role;
grant execute on function ledger_private.read_item_price_edit(text,text,text) to authenticated;
create function public.spike_read_item_price_edit(p_account_id text,p_project_id text,p_item_id text)
returns jsonb language sql stable security invoker set search_path='' as $$
  select ledger_private.read_item_price_edit(p_account_id,p_project_id,p_item_id)
$$;
revoke all on function public.spike_read_item_price_edit(text,text,text) from public,anon,service_role;
grant execute on function public.spike_read_item_price_edit(text,text,text) to authenticated;
