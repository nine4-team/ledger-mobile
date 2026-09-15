-- Reuse canonical Transactions and immutable source evidence. This operator-only
-- primitive does not infer payer, allocation, placement, collection or tax.
-- The caller must reconcile those facts before supplying an import plan.
create function ledger_private.import_vendor_purchase(
  p_id text, p_account_id text, p_scope_kind text, p_project_id text, p_client_id text,
  p_category_id text, p_amount bigint, p_currency text, p_lines jsonb, p_items jsonb,
  p_source_account text, p_source_document text, p_source_bytes bytea
) returns text language plpgsql security invoker set search_path='' as $$
declare
  stored public.spike_transactions;
  evidence ledger_private.imported_transaction_sources;
  link public.transaction_receipt_items;
  entry jsonb;
  item_ids text[] := '{}';
  link_ids text[] := '{}';
  amount bigint;
  newly_created boolean;
begin
  if jsonb_typeof(p_items) is distinct from 'array' or octet_length(p_items::text)>1048576 then
    raise exception using errcode='22023',message='Invalid imported Item relationships';
  end if;
  insert into public.spike_transactions(id,account_id,scope_kind,project_id,client_id,
    category_id,amount_minor_units,currency,origin,type,non_item_receipt_lines)
  values(p_id,p_account_id,p_scope_kind,p_project_id,p_client_id,p_category_id,p_amount,
    p_currency,'vendor_payment','purchase',p_lines) on conflict(id) do nothing returning true into newly_created;
  select * into strict stored from public.spike_transactions where id=p_id for update;
  if row(stored.account_id,stored.scope_kind,stored.project_id,stored.client_id,stored.category_id,
    stored.amount_minor_units,stored.currency,stored.origin,stored.type,stored.role,stored.non_item_receipt_lines)
    is distinct from row(p_account_id,p_scope_kind,p_project_id,p_client_id,p_category_id,
      p_amount,p_currency,'vendor_payment'::text,'purchase'::text,'standalone'::text,p_lines) then
    raise exception using errcode='22000',message='Imported vendor purchase conflicts with target facts';
  end if;
  if newly_created is not true and (
    not exists(select 1 from ledger_private.imported_transaction_sources where transaction_id=p_id)
    or (select count(*) from public.transaction_receipt_items where account_id=p_account_id and transaction_id=p_id)
       <>jsonb_array_length(p_items)) then
    raise exception using errcode='22000',message='Imported purchase replay requires unchanged source and Item set';
  end if;
  insert into ledger_private.imported_transaction_sources(transaction_id,account_id,
    source_account_id,source_document_id,source_bytes)
  values(p_id,p_account_id,p_source_account,p_source_document,p_source_bytes) on conflict do nothing;
  select * into evidence from ledger_private.imported_transaction_sources where transaction_id=p_id;
  if not found or row(evidence.account_id,evidence.source_account_id,evidence.source_document_id,evidence.source_bytes)
    is distinct from row(p_account_id,p_source_account,p_source_document,p_source_bytes) then
    raise exception using errcode='22000',message='Imported vendor source identity or bytes conflict';
  end if;
  for entry in select value from jsonb_array_elements(p_items) loop
    if jsonb_typeof(entry) is distinct from 'object'
      or not (entry ?& array['id','itemId','amountMinorUnits','membershipKind'])
      or (entry-array['id','itemId','amountMinorUnits','membershipKind'])<>'{}'::jsonb
      or jsonb_typeof(entry->'id') is distinct from 'string'
      or jsonb_typeof(entry->'itemId') is distinct from 'string'
      or jsonb_typeof(entry->'membershipKind') is distinct from 'string'
      or entry->>'membershipKind' not in ('linked','returned','sold')
      or entry->>'itemId'=any(item_ids) or entry->>'id'=any(link_ids) then
      raise exception using errcode='22023',message='Invalid imported Item relationships';
    end if;
    if entry->'amountMinorUnits'='null'::jsonb then amount:=null;
    elsif jsonb_typeof(entry->'amountMinorUnits')='string'
      and entry->>'amountMinorUnits' ~ '^(0|[1-9][0-9]*)$' then
      amount:=(entry->>'amountMinorUnits')::bigint;
    else raise exception using errcode='22023',message='Imported Item amount must be exact text or null';
    end if;
    item_ids:=array_append(item_ids,entry->>'itemId');
    link_ids:=array_append(link_ids,entry->>'id');
    insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,
      amount_minor_units,membership_kind)
    values(entry->>'id',p_account_id,p_id,entry->>'itemId',p_currency,amount,entry->>'membershipKind')
    on conflict do nothing;
    select * into link from public.transaction_receipt_items where id=entry->>'id' for update;
    if not found or row(link.account_id,link.transaction_id,link.item_id,link.currency,link.amount_minor_units,link.membership_kind)
      is distinct from row(p_account_id,p_id,entry->>'itemId',p_currency,amount,entry->>'membershipKind') then
      raise exception using errcode='22000',message='Imported Item relationship conflicts';
    end if;
  end loop;
  if exists(select 1 from public.transaction_receipt_items
    where account_id=p_account_id and transaction_id=p_id and not(id=any(link_ids))) then
    raise exception using errcode='22000',message='Imported Item relationship set conflicts';
  end if;
  return p_id;
end;
$$;
revoke all on function ledger_private.import_vendor_purchase(text,text,text,text,text,text,bigint,text,jsonb,jsonb,text,text,bytea)
  from public,anon,authenticated,service_role;
