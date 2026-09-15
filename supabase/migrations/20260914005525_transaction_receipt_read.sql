-- Extend the canonical Transaction, not a separate Receipt entity. Existing
-- imported client payments stay immutable and are not vendor receipt evidence.
alter table public.spike_transactions
  drop constraint spike_transactions_type_check,
  drop constraint spike_transactions_origin_check,
  alter column project_id drop not null,
  alter column client_id drop not null,
  add column scope_kind text not null default 'project',
  add column category_id text,
  add column non_item_receipt_lines jsonb not null default '[]'::jsonb,
  add constraint spike_transactions_type_check check (type in ('purchase','return')),
  add constraint spike_transactions_origin_check check (origin in ('firebase_client_payment','vendor_payment')),
  add constraint spike_transactions_scope_check check (
    (scope_kind='project' and project_id is not null and client_id is not null)
    or (scope_kind='business_inventory' and project_id is null and client_id is null)),
  add constraint spike_transactions_receipt_owner_check check (
    (origin='firebase_client_payment' and scope_kind='project' and type='purchase'
      and category_id is null and non_item_receipt_lines='[]'::jsonb)
    or (origin='vendor_payment' and category_id is not null)),
  add constraint spike_transactions_account_fk foreign key (account_id) references public.spike_accounts(id),
  add constraint spike_transactions_category_fk foreign key (account_id,category_id)
    references public.spike_budget_categories(account_id,id),
  add constraint spike_transactions_receipt_scope unique (account_id,id,origin,currency);
create index spike_transactions_category_idx on public.spike_transactions(account_id,category_id);

-- Embedded nonphysical lines retain source wording/order. Amounts are exact
-- decimal strings in the read contract; quantity is evidence, not a multiplier.
create function ledger_private.valid_non_item_receipt_lines(lines jsonb)
returns boolean language plpgsql immutable security invoker set search_path='' as $$
declare line jsonb; ids text[] := '{}'; amount bigint;
begin
  if jsonb_typeof(lines) is distinct from 'array' or octet_length(lines::text)>262144 then return false; end if;
  for line in select value from jsonb_array_elements(lines) loop
    if jsonb_typeof(line) is distinct from 'object'
      or not (line ?& array['id','description','amountMinorUnits','effect'])
      or (line-array['id','description','amountMinorUnits','effect','quantity'])<>'{}'::jsonb
      or jsonb_typeof(line->'id') is distinct from 'string'
      or (line->>'id') !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
      or octet_length(line->>'id')>128 or line->>'id'=any(ids)
      or jsonb_typeof(line->'description') is distinct from 'string'
      or (line->>'description') !~ '[^[:space:]]'
      or jsonb_typeof(line->'amountMinorUnits') is distinct from 'string'
      or (line->>'amountMinorUnits') !~ '^[1-9][0-9]*$'
      or (line->>'effect') not in ('increase','decrease')
      or jsonb_typeof(line->'effect') is distinct from 'string' then return false; end if;
    amount := (line->>'amountMinorUnits')::bigint;
    if line ? 'quantity' and jsonb_typeof(line->'quantity') <> 'null' then
      if jsonb_typeof(line->'quantity') is distinct from 'string'
        or (line->>'quantity') !~ '^-?(0|[1-9][0-9]*)$' then return false; end if;
      perform (line->>'quantity')::bigint;
    end if;
    ids := array_append(ids,line->>'id');
  end loop;
  return true;
exception when numeric_value_out_of_range or invalid_text_representation then return false;
end;
$$;
revoke all on function ledger_private.valid_non_item_receipt_lines(jsonb) from public,anon,authenticated,service_role;
alter table public.spike_transactions add constraint spike_transactions_receipt_lines_check
  check (ledger_private.valid_non_item_receipt_lines(non_item_receipt_lines));

-- A permanent Transaction/physical-Item relationship carries the price evidence
-- on that vendor receipt's purchase-cost basis. Ending current membership keeps
-- its historical contribution; placement/lineage remains in its existing model.
-- A missing recorded Item amount is allowed evidence-in-progress, never zero.
create table public.transaction_receipt_items (
  id text primary key check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id)<=128),
  account_id text not null,
  transaction_id text not null,
  item_id text not null,
  transaction_origin text generated always as ('vendor_payment'::text) stored,
  currency text not null,
  amount_minor_units bigint check (amount_minor_units>=0),
  membership_kind text not null check (membership_kind in ('linked','returned','sold')),
  unique (account_id,transaction_id,item_id),
  foreign key (account_id,transaction_id,transaction_origin,currency)
    references public.spike_transactions(account_id,id,origin,currency),
  foreign key (account_id,item_id) references public.spike_items(account_id,id)
);
create index transaction_receipt_items_item_idx on public.transaction_receipt_items(account_id,item_id);
alter table public.transaction_receipt_items enable row level security;
alter table public.transaction_receipt_items force row level security;
revoke all on public.transaction_receipt_items from public,anon,authenticated,service_role;

-- Adding vendor Purchases must not let a vendor payment masquerade as the
-- payment generated by collecting an Invoice. No new collection writer here.
create function ledger_private.require_collected_payment_origin()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if not exists (select 1 from public.spike_transactions t where t.account_id=new.account_id
    and t.id=new.purchase_id and t.origin='firebase_client_payment') then
    raise exception using errcode='23514',message='Collected Invoice requires collection payment evidence';
  end if;
  return new;
end;
$$;
revoke all on function ledger_private.require_collected_payment_origin() from public,anon,authenticated,service_role;
create trigger require_collected_payment_origin before insert or update on ledger_private.collected_invoices
  for each row execute function ledger_private.require_collected_payment_origin();

-- Use current category authorization, including archived definitions. A category
-- transition changes visibility normally, with no sticky Fee-to-General rule.
drop policy item_linked_purchase_full_read on public.spike_transactions;
drop policy if exists vendor_transaction_receipt_read on public.spike_transactions;
create policy transaction_authorized_read on public.spike_transactions
for select to authenticated using (
  (origin='firebase_client_payment' and exists (
    select 1 from public.spike_principals principal
    join public.spike_account_memberships membership on membership.principal_id=principal.id
    where principal.auth_user_id=(select auth.uid()) and membership.account_id=spike_transactions.account_id
      and membership.state='active' and membership.financial_access='full'
  ) and exists (
    select 1 from ledger_private.item_client_payment_connections link
    join public.spike_item_placements placement on placement.id=link.placement_id
      and placement.account_id=link.account_id and placement.project_id=link.project_id and placement.item_id=link.item_id
    where link.transaction_id=spike_transactions.id and link.account_id=spike_transactions.account_id
      and link.project_id=spike_transactions.project_id and link.client_id=spike_transactions.client_id
      and link.transaction_type=spike_transactions.type and link.transaction_role=spike_transactions.role
      and link.ended_at is null and placement.ended_at is null and placement.scope_kind='project'
  )) or (origin='vendor_payment' and exists (
    select 1 from public.spike_budget_categories c
    where c.account_id=spike_transactions.account_id and c.id=spike_transactions.category_id
      and ledger_private.can_view_budget_category(c.account_id,c.visibility_class))
  )
);
create policy transaction_receipt_items_read on public.transaction_receipt_items
for select to authenticated using (exists (
  select 1 from public.spike_transactions t where t.account_id=transaction_receipt_items.account_id
    and t.id=transaction_receipt_items.transaction_id and t.origin='vendor_payment'
));
grant select (scope_kind,category_id,non_item_receipt_lines) on public.spike_transactions to authenticated;
grant select (id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
  on public.transaction_receipt_items to authenticated;

-- One statement snapshot returns complete authorized receipt evidence. This is
-- a read port, not a writer or a persisted audit/completion flag. PowerSync's
-- local reader must establish its own complete-working-set evidence.
create or replace function public.spike_read_transaction_receipt(p_account_id text,p_transaction_id text)
returns jsonb language plpgsql stable security invoker set search_path='' as $$
declare result jsonb;
begin
  if (select auth.uid()) is null then raise exception using errcode='28000',message='authentication required'; end if;
  if not ledger_private.has_active_membership(p_account_id) then
    raise exception using errcode='42501',message='account_not_authorized';
  end if;
  select jsonb_build_object('accountId',t.account_id,'transactionId',t.id,
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
      where i.account_id=t.account_id and i.transaction_id=t.id),'[]'::jsonb))
    into result from public.spike_transactions t join public.spike_budget_categories c
      on c.account_id=t.account_id and c.id=t.category_id
    where t.account_id=p_account_id and t.id=p_transaction_id and t.origin='vendor_payment';
  if result is null then raise exception using errcode='42501',message='transaction_not_available'; end if;
  return result;
end;
$$;
revoke all on function public.spike_read_transaction_receipt(text,text) from public,anon,authenticated,service_role;
grant execute on function public.spike_read_transaction_receipt(text,text) to authenticated;
