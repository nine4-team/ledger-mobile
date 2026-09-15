-- Derived download state only. Receipts remain the acquisition authority.
create table ledger_private.item_acquisition_reviews (
  id text primary key,
  account_id text not null,
  state text not null check(state in ('absent','known','unavailable')),
  amount_minor_units bigint,
  currency text,
  requires_full_access boolean not null,
  foreign key(account_id,id) references public.spike_items(account_id,id) on delete cascade,
  check ((state='known' and amount_minor_units is not null and currency is not null)
    or (state<>'known' and amount_minor_units is null and currency is null))
);
create index item_acquisition_reviews_account on ledger_private.item_acquisition_reviews(account_id,id);
alter table ledger_private.item_acquisition_reviews enable row level security;
alter table ledger_private.item_acquisition_reviews force row level security;
revoke all on ledger_private.item_acquisition_reviews from public,anon,authenticated,service_role;

create function ledger_private.refresh_item_acquisition_review(account text,item text)
returns void language plpgsql security definer set search_path='' as $$
declare n bigint; amount bigint; money_currency text; restricted boolean; resolution text;
begin
  -- Serialize refreshes for one physical identity before reading current receipts.
  perform 1 from public.spike_items where account_id=account and id=item for update;
  if not found then return; end if;
  select count(*),min(r.amount_minor_units),min(r.currency),
    coalesce(bool_or(cat.visibility_class is distinct from 'ordinary'),false)
    into n,amount,money_currency,restricted
  from public.transaction_receipt_items r
  join public.spike_transactions t on t.account_id=r.account_id and t.id=r.transaction_id
  left join public.spike_budget_categories cat on cat.account_id=t.account_id and cat.id=t.category_id
  where r.account_id=account and r.item_id=item and t.type='purchase';
  resolution := case when n=0 then 'absent' when n=1 and amount is not null then 'known' else 'unavailable' end;
  insert into ledger_private.item_acquisition_reviews(id,account_id,state,amount_minor_units,currency,requires_full_access)
    values(item,account,resolution,case when resolution='known' then amount end,
      case when resolution='known' then money_currency end,restricted)
  on conflict(id) do update set state=excluded.state,amount_minor_units=excluded.amount_minor_units,
    currency=excluded.currency,requires_full_access=excluded.requires_full_access;
end;
$$;
create function ledger_private.item_acquisition_review_changed() returns trigger
language plpgsql security definer set search_path='' as $$
begin
  if tg_table_name='spike_items' then
    perform ledger_private.refresh_item_acquisition_review(new.account_id,new.id);
  else
    if tg_op<>'INSERT' then perform ledger_private.refresh_item_acquisition_review(old.account_id,old.item_id); end if;
    if tg_op='INSERT' or (tg_op='UPDATE' and (new.account_id,new.item_id) is distinct from (old.account_id,old.item_id)) then
      perform ledger_private.refresh_item_acquisition_review(new.account_id,new.item_id);
    end if;
  end if;
  return null;
end;
$$;
create function ledger_private.item_acquisition_visibility_changed() returns trigger
language plpgsql security definer set search_path='' as $$
declare item text;
begin
  for item in select distinct r.item_id from public.transaction_receipt_items r
    join public.spike_transactions t on t.account_id=r.account_id and t.id=r.transaction_id
    where t.account_id=new.account_id and t.category_id=new.id order by r.item_id loop
    perform ledger_private.refresh_item_acquisition_review(new.account_id,item);
  end loop;
  return null;
end;
$$;
revoke all on function ledger_private.refresh_item_acquisition_review(text,text),
  ledger_private.item_acquisition_review_changed(),ledger_private.item_acquisition_visibility_changed()
  from public,anon,authenticated,service_role;
create trigger item_acquisition_initial after insert on public.spike_items
  for each row execute function ledger_private.item_acquisition_review_changed();
create trigger item_acquisition_receipt_changed after insert or update or delete on public.transaction_receipt_items
  for each row execute function ledger_private.item_acquisition_review_changed();
-- Existing transactions_sync_children already updates receipt rows on all
-- Transaction changes, so no second Transaction propagation trigger is needed.
create trigger item_acquisition_category_visibility after update on public.spike_budget_categories
  for each row when(old.visibility_class is distinct from new.visibility_class)
  execute function ledger_private.item_acquisition_visibility_changed();
do $$ declare row record; begin
  for row in select account_id,id from public.spike_items order by id loop
    perform ledger_private.refresh_item_acquisition_review(row.account_id,row.id);
  end loop;
end $$;
