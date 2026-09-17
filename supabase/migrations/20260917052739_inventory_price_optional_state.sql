-- Clear current price without deleting its revision identity. Currency remains
-- fixed; this does not alter acquisition, charge or paid-history amounts.
alter table ledger_private.item_project_prices
  alter column amount_minor_units drop not null,
  drop constraint item_project_prices_amount_minor_units_check,
  add constraint item_project_prices_amount_minor_units_check
    check (amount_minor_units is null or amount_minor_units >= 0);

-- Preserve the already-reviewed handler bodies and grants. These are exact,
-- migration-local substitutions, not runtime rewriting. Fail closed if any
-- expected source has drifted or occurs more than once.
do $migration$
declare change record; definition text; updated text;
begin
  for change in select * from (values
    ('ledger_private.sell_inventory_items(text)',
     'elsif price.amount_minor_units<>reviewed then',
     'elsif price.amount_minor_units is distinct from reviewed then'),
    ('ledger_private.edit_uncollected_item_price(text)',
     'elsif price.amount_minor_units<>reviewed then',
     'elsif price.amount_minor_units is distinct from reviewed then'),
    ('ledger_private.read_inventory_sale_review(text,text[])',
     'case when price.item_id is null then jsonb_build_object(''state'',''absent'')',
     'case when price.item_id is null or price.amount_minor_units is null then jsonb_build_object(''state'',''absent'')'),
    ('ledger_private.read_item_price_edit(text,text,text)',
     '''currentPrice'',case when price_found then jsonb_build_object(',
     '''currentPrice'',case when price_found and price.amount_minor_units is not null then jsonb_build_object(')
  ) as changes(signature,old_text,new_text) loop
    definition := pg_get_functiondef(change.signature::regprocedure);
    if (length(definition)-length(replace(definition,change.old_text,''))) / length(change.old_text) <> 1 then
      raise exception 'Unexpected function definition for %',change.signature;
    end if;
    updated := replace(definition,change.old_text,change.new_text);
    execute updated;
  end loop;
end;
$migration$;

-- Both placements use the same authorized review and cost evidence. A missing
-- Inventory currency is genuinely unknown, not a default inferred from zero.
create or replace function ledger_private.read_item_price_edit(p_account_id text,p_project_id text,p_item_id text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare
  actor text:=ledger_private.current_principal_id(); n bigint; occurrence text; placement_id text;
  charge ledger_private.item_charge_occurrences; price ledger_private.item_project_prices;
  price_found boolean; cost_count bigint; cost bigint; cost_currency text; review_currency text;
begin
  if (select auth.uid()) is null or actor is null or not exists(
    select 1 from public.spike_account_memberships where account_id=p_account_id
      and principal_id=actor and state='active' and financial_access='full') then
    raise sqlstate '42501' using message='Item price access required';
  end if;
  if p_project_id is null then
    select count(*),min(p.id) into n,placement_id
    from public.spike_item_placements p join public.spike_items i
      on i.account_id=p.account_id and i.id=p.item_id
    where p.account_id=p_account_id and p.item_id=p_item_id
      and p.scope_kind='business_inventory' and p.ended_at is null;
  else
    select count(*),min(c.id) into n,occurrence
    from ledger_private.item_charge_occurrences c
    join public.spike_item_placements p on p.account_id=c.account_id
      and p.id=c.placement_id and p.item_id=c.item_id and p.project_id=c.project_id
    join public.spike_projects project on project.account_id=c.account_id and project.id=c.project_id
    join public.spike_clients client on client.account_id=project.account_id and client.id=project.client_id
    where c.account_id=p_account_id and c.project_id=p_project_id and c.item_id=p_item_id
      and c.withdrawn_at is null and p.scope_kind='project' and p.ended_at is null
      and project.lifecycle='active' and client.lifecycle='active'
      and not exists(select 1 from ledger_private.collected_invoice_lines paid
        where paid.account_id=c.account_id and paid.source_kind='item' and paid.source_id=c.id);
    select * into charge from ledger_private.item_charge_occurrences where account_id=p_account_id and id=occurrence;
    placement_id:=charge.placement_id;
  end if;
  if n<>1 then raise sqlstate '22023' using message='Item price review unavailable'; end if;
  select * into price from ledger_private.item_project_prices where account_id=p_account_id and item_id=p_item_id;
  price_found:=found;
  select count(*),min(r.amount_minor_units),min(r.currency) into cost_count,cost,cost_currency
  from public.transaction_receipt_items r join public.spike_transactions t
    on t.account_id=r.account_id and t.id=r.transaction_id
  where r.account_id=p_account_id and r.item_id=p_item_id and t.type='purchase';
  review_currency:=coalesce(charge.currency,price.currency,cost_currency);
  if cost_count>1 or (cost_count=1 and (cost is null or cost<0 or cost_currency is distinct from review_currency))
    or (price_found and (price.currency is distinct from review_currency or price.amount_minor_units<0
      or price.revision>=9223372036854775807)) or charge.revision>=9223372036854775807 then
    raise sqlstate '22023' using message='Item price review unavailable';
  end if;
  return jsonb_build_object('accountId',p_account_id,'principalId',actor,'projectId',p_project_id,
    'itemId',p_item_id,'placementId',placement_id,'occurrenceId',charge.id,'currency',review_currency,
    'priceRevision',case when price_found then price.revision::text else '0' end,
    'chargeRevision',charge.revision::text,
    'currentPrice',case when price_found and price.amount_minor_units is not null then jsonb_build_object(
      'amountMinorUnits',price.amount_minor_units::text,'currency',price.currency) else null end,
    'purchaseCost',case when cost_count=0 then jsonb_build_object('state','absent')
      else jsonb_build_object('state','known','amountMinorUnits',cost::text,'currency',cost_currency) end);
end;
$$;

-- Inventory branch of the existing price operation. API routing is enabled
-- separately after the complete command/admission path is verified.
create function ledger_private.edit_inventory_item_price(p_command text)
returns public.spike_operation_results language plpgsql security definer set search_path='' as $$
declare
 c jsonb:=p_command::jsonb; actor text:=c->>'actorPrincipalId'; account text:=c->>'accountId';
 operation text:=c->>'operationId'; fingerprint text; result public.spike_operation_results;
 price ledger_private.item_project_prices; price_exists boolean; failure text;
 cost_count bigint; cost bigint; cost_currency text; requested bigint; reviewed bigint; stored bigint;
 received timestamptz:=clock_timestamp();
 required text[]:=array['operationId','accountId','actorPrincipalId','contractVersion','createdAtMs',
   'itemId','placementId','expectedPriceRevision','requestedPriceMinorUnits','reviewedPriceMinorUnits','currency','clearPrice'];
begin
 if current_setting('transaction_isolation')<>'read committed' then
   raise sqlstate '25001' using message='Item price edits require READ COMMITTED';
 end if;
 if (select auth.uid()) is null or actor is distinct from ledger_private.current_principal_id() then
   raise sqlstate '42501' using message='Authenticated actor required';
 end if;
 perform 1 from public.spike_account_memberships where account_id=account and principal_id=actor
   and state='active' and financial_access='full' for share;
 if not found then raise sqlstate '42501' using message='Item price access required'; end if;
 if jsonb_typeof(c) is distinct from 'object' or not(c ?& required) or c-required<>'{}'
   or exists(select 1 from jsonb_each(c) where jsonb_typeof(value)<>'string')
   or c->>'contractVersion' is distinct from 'item-inventory-price-edit-v2'
   or exists(select 1 from jsonb_each_text(c-array['contractVersion','createdAtMs','expectedPriceRevision',
     'requestedPriceMinorUnits','reviewedPriceMinorUnits','currency','clearPrice'])
     where value !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(value)>128)
   or c->>'currency' !~ '^[A-Z]{3}$' or c->>'clearPrice' not in ('true','false')
   or c->>'createdAtMs' !~ '^(0|[1-9][0-9]*)$' or (c->>'createdAtMs')::numeric>=1000000000000000
   or c->>'expectedPriceRevision' !~ '^(0|[1-9][0-9]*)$'
   or (c->>'expectedPriceRevision')::numeric>=9223372036854775807
   or c->>'requestedPriceMinorUnits' !~ '^(0|[1-9][0-9]*)$'
   or c->>'reviewedPriceMinorUnits' !~ '^(0|[1-9][0-9]*)$'
   or (c->>'requestedPriceMinorUnits')::numeric>9223372036854775807
   or (c->>'reviewedPriceMinorUnits')::numeric>9223372036854775807 then
   raise sqlstate '22023' using message='Invalid Inventory price command';
 end if;
 requested:=(c->>'requestedPriceMinorUnits')::bigint; reviewed:=(c->>'reviewedPriceMinorUnits')::bigint;
 if reviewed<requested or (c->>'clearPrice'='true' and requested<>0) then
   raise sqlstate '22023' using message='Invalid reviewed Inventory price';
 end if;
 fingerprint:=encode(extensions.digest(convert_to(p_command,'UTF8'),'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended(operation,0));
 select * into result from public.spike_operation_results where operation_id=operation;
 if found then
   if row(result.account_id,result.actor_principal_id,result.command_type,result.command_fingerprint)
     is distinct from row(account,actor,'edit_uncollected_item_price',fingerprint) then
     raise sqlstate '23505' using message='Operation identity conflict';
   end if;
   return result;
 end if;
 begin
   -- Same Item-before-placement/price lock order as Inventory sale.
   perform 1 from public.spike_items where account_id=account and id=c->>'itemId' for update;
   if not found then raise exception 'price_item_unavailable'; end if;
   perform 1 from public.spike_item_placements where account_id=account and item_id=c->>'itemId'
     and id=c->>'placementId' and scope_kind='business_inventory' and ended_at is null for update;
   if not found then raise exception 'price_placement_stale'; end if;
   perform r.id from public.transaction_receipt_items r join public.spike_transactions t
     on t.account_id=r.account_id and t.id=r.transaction_id
     where r.account_id=account and r.item_id=c->>'itemId' and t.type='purchase' for share of r,t;
   select count(*),min(r.amount_minor_units),min(r.currency) into cost_count,cost,cost_currency
     from public.transaction_receipt_items r join public.spike_transactions t
       on t.account_id=r.account_id and t.id=r.transaction_id
     where r.account_id=account and r.item_id=c->>'itemId' and t.type='purchase';
   if cost_count>1 or (cost_count=1 and (cost is null or cost<0)) then
     raise exception 'price_acquisition_ambiguous';
   end if;
   if cost_count=1 and cost_currency is distinct from c->>'currency' then raise exception 'price_currency_mismatch'; end if;
   if reviewed<>greatest(requested,coalesce(cost,0)) then raise exception 'price_review_stale'; end if;
   select * into price from ledger_private.item_project_prices where account_id=account and item_id=c->>'itemId' for update;
   price_exists:=found;
   if (price_exists and price.revision::text<>c->>'expectedPriceRevision')
     or (not price_exists and c->>'expectedPriceRevision'<>'0') then raise exception 'price_revision_stale'; end if;
   if price_exists and price.currency<>c->>'currency' then raise exception 'price_currency_mismatch'; end if;
   stored:=case when c->>'clearPrice'='true' and reviewed=0 then null else reviewed end;
   if not price_exists then
     insert into ledger_private.item_project_prices(account_id,item_id,amount_minor_units,currency,updated_at,updated_by_principal_id)
       values(account,c->>'itemId',stored,c->>'currency',received,actor);
   elsif price.amount_minor_units is distinct from stored then
     update ledger_private.item_project_prices set amount_minor_units=stored,revision=revision+1,
       updated_at=received,updated_by_principal_id=actor where account_id=account and item_id=c->>'itemId';
   end if;
 exception when raise_exception then failure:=SQLERRM;
   when integrity_constraint_violation or numeric_value_out_of_range or object_not_in_prerequisite_state then
     failure:='price_integrity_conflict';
 end;
 insert into public.spike_operation_results(operation_id,account_id,actor_principal_id,command_type,contract_version,
   command_fingerprint,envelope_sha256,subject_id,phase,result_code,error_code,client_created_at,server_received_at,
   completed_at,client_created_at_ms,server_received_at_ms,completed_at_ms)
 values(operation,account,actor,'edit_uncollected_item_price','item-inventory-price-edit-v2',fingerprint,fingerprint,c->>'itemId',
   case when failure is null then 'applied' else 'rejected' end,
   case when failure is null then 'item_price_updated' end,failure,
   to_timestamp((c->>'createdAtMs')::numeric/1000),received,received,(c->>'createdAtMs')::bigint,
   floor(extract(epoch from received)*1000)::bigint,floor(extract(epoch from received)*1000)::bigint)
 returning * into result;
 return result;
end;
$$;
revoke all on function ledger_private.edit_inventory_item_price(text) from public,anon,authenticated,service_role;

-- Route through the existing invoker endpoint; both private branches enforce
-- authenticated actor, current membership and full financial access themselves.
grant execute on function ledger_private.edit_inventory_item_price(text) to authenticated;
create or replace function public.spike_edit_uncollected_item_price(p_command text)
returns public.spike_operation_results language sql security invoker set search_path='' as $$
 select case when p_command::jsonb->>'contractVersion'='item-inventory-price-edit-v2'
   then ledger_private.edit_inventory_item_price(p_command)
   else ledger_private.edit_uncollected_item_price(p_command) end;
$$;
revoke all on function public.spike_edit_uncollected_item_price(text) from public,anon,service_role;
grant execute on function public.spike_edit_uncollected_item_price(text) to authenticated;
