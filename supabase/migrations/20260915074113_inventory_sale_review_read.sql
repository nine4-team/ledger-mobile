-- Complete cross-scope review of existing facts. This creates no acquisition,
-- payment, price or placement and does not authorize a sale by itself.
create or replace function ledger_private.read_inventory_sale_review(p_account_id text, p_item_ids text[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text; result jsonb;
begin
  actor := ledger_private.current_principal_id();
  if (select auth.uid()) is null or actor is null then
    raise exception using errcode='42501',message='Authenticated member required';
  end if;
  perform 1 from public.spike_account_memberships
    where account_id=p_account_id and principal_id=actor and state='active' for share;
  if not found then raise exception using errcode='42501',message='Active Account membership required'; end if;
  if p_item_ids is null or cardinality(p_item_ids) not between 1 and 500
    or exists(select 1 from unnest(p_item_ids) id where id is null or id='')
    or (select count(distinct id) from unnest(p_item_ids) id)<>cardinality(p_item_ids) then
    raise exception using errcode='22023',message='Invalid Item selection';
  end if;
  select jsonb_agg(jsonb_build_object(
    'itemId',i.id,'placementId',p.id,
    'priceRevision',coalesce(price.revision::text,'0'),
    'projectPrice',case when price.item_id is null then jsonb_build_object('state','absent')
      else jsonb_build_object('state','known','amountMinorUnits',price.amount_minor_units::text,'currency',price.currency) end,
    'purchaseCost',case when cost.n=0 then jsonb_build_object('state','absent')
      when cost.n=1 and cost.visible and cost.amount is not null then jsonb_build_object('state','known','amountMinorUnits',cost.amount::text,'currency',cost.currency)
      else jsonb_build_object('state','unavailable') end
    ) order by i.id collate "C") into result
  from public.spike_items i
  join public.spike_item_placements p on p.account_id=i.account_id and p.item_id=i.id
    and p.scope_kind='business_inventory' and p.ended_at is null
  left join ledger_private.item_project_prices price on price.account_id=i.account_id and price.item_id=i.id
  cross join lateral (
    select count(*) n,min(r.amount_minor_units) amount,min(r.currency) currency,
      bool_and(coalesce(ledger_private.can_view_budget_category(cat.account_id,cat.visibility_class),false)) visible
    from public.transaction_receipt_items r
    join public.spike_transactions t on t.account_id=r.account_id and t.id=r.transaction_id
    left join public.spike_budget_categories cat on cat.account_id=t.account_id and cat.id=t.category_id
    where r.account_id=i.account_id and r.item_id=i.id and t.type='purchase'
  ) cost
  where i.account_id=p_account_id and i.id=any(p_item_ids);
  if coalesce(jsonb_array_length(result),0)<>cardinality(p_item_ids) then
    raise exception using errcode='42501',message='Inventory Item selection unavailable';
  end if;
  return jsonb_build_object('accountId',p_account_id,'principalId',actor,'items',result);
end;
$$;
revoke all on function ledger_private.read_inventory_sale_review(text,text[]) from public,anon,authenticated,service_role;
grant execute on function ledger_private.read_inventory_sale_review(text,text[]) to authenticated;
create function public.spike_read_inventory_sale_review(p_account_id text,p_item_ids text[])
returns jsonb language sql security invoker set search_path='' as $$
  select ledger_private.read_inventory_sale_review(p_account_id,p_item_ids);
$$;
revoke all on function public.spike_read_inventory_sale_review(text,text[]) from public,anon,authenticated,service_role;
grant execute on function public.spike_read_inventory_sale_review(text,text[]) to authenticated;
