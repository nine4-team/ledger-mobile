-- Private atomic Inventory sale implementation. Public API wiring remains gated.
alter table public.spike_operation_results drop constraint spike_operation_results_command_type_check;
alter table public.spike_operation_results add constraint spike_operation_results_command_type_check check
 (command_type in ('create_client','create_project','archive_project','archive_client','revise_space_checklists','manage_categories','sell_inventory_items'));

create or replace function ledger_private.sell_inventory_items(p_command text)
returns public.spike_operation_results language plpgsql security definer set search_path='' as $sale$
declare
 c jsonb; entry jsonb; fingerprint text; result public.spike_operation_results;
 actor text; account text; project text; category text; operation text;
 price ledger_private.item_project_prices; placement public.spike_item_placements;
 received timestamptz; created timestamptz; failure text; client text;
 cost_count bigint; cost bigint; cost_currency text; reviewed bigint; normalized bigint; price_exists boolean;
begin
 if current_setting('transaction_isolation') <> 'read committed' then
   raise exception using errcode='25001',message='Sale requires READ COMMITTED';
 end if;
 c := p_command::jsonb;
 actor := c->>'actorPrincipalId'; account := c->>'accountId'; project := c->>'projectId'; operation := c->>'operationId';
 if (select auth.uid()) is null or actor is distinct from ledger_private.current_principal_id() then
   raise exception using errcode='42501',message='Authenticated actor required';
 end if;
 perform 1 from public.spike_account_memberships where account_id=account and principal_id=actor and state='active' for share;
 if not found then raise exception using errcode='42501',message='Active Account membership required'; end if;
 if jsonb_typeof(c) is distinct from 'object'
   or c->>'contractVersion' is distinct from 'inventory-sale-v1'
   or not(c ?& array['operationId','accountId','actorPrincipalId','projectId','contractVersion','createdAtMs','currency','items'])
   or (c-array['operationId','accountId','actorPrincipalId','projectId','contractVersion','createdAtMs','currency','items']) <> '{}'::jsonb
   or c->>'currency' !~ '^[A-Z]{3}$'
   or exists(select 1 from jsonb_each(c-'items') where jsonb_typeof(value)<>'string')
   or operation is null or operation !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
   or octet_length(operation)>128
   or jsonb_typeof(c->'items') is distinct from 'array'
   or jsonb_array_length(c->'items') not between 1 and 500
   or jsonb_typeof(c->'createdAtMs') is distinct from 'string'
   or c->>'createdAtMs' !~ '^[0-9]+$' then
   raise exception using errcode='22023',message='Invalid sale command';
 end if;
 created := to_timestamp((c->>'createdAtMs')::bigint/1000.0);
 fingerprint := encode(extensions.digest(convert_to(p_command,'UTF8'),'sha256'),'hex');
 perform pg_advisory_xact_lock(hashtextextended(operation,0));
 select * into result from public.spike_operation_results where operation_id=operation;
 if found then
   if row(result.account_id,result.actor_principal_id,result.command_type,result.command_fingerprint)
      is distinct from row(account,actor,'sell_inventory_items'::text,fingerprint) then
     raise exception using errcode='23505',message='Operation identity already used';
   end if;
   return result;
 end if;
 received := clock_timestamp();
 begin
   if (select count(distinct value->>'itemId') from jsonb_array_elements(c->'items')) <> jsonb_array_length(c->'items') then
     raise exception 'sale_duplicate_item';
   end if;
   select client_id into client from public.spike_projects
     where id=project and account_id=account and lifecycle='active' for share;
   if not found then raise exception 'sale_destination_unavailable'; end if;
   perform 1 from public.spike_clients where id=client and account_id=account and lifecycle='active' for share;
   if not found then raise exception 'sale_destination_unavailable'; end if;
   select furnishings_category_id into category from public.spike_accounts where id=account;
   if category is null then raise exception 'sale_furnishings_unresolved'; end if;
   -- Stable lock order across bulk sales. Return-only provenance is not consulted.
   for entry in select value from jsonb_array_elements(c->'items') order by value->>'itemId' collate "C" loop
     if jsonb_typeof(entry) is distinct from 'object'
       or not(entry ?& array['itemId','placementId','priceRevision','newPlacementId','occurrenceId','reviewedPriceMinorUnits'])
       or (entry-array['itemId','placementId','priceRevision','newPlacementId','occurrenceId','reviewedPriceMinorUnits']) <> '{}'::jsonb
       or exists(select 1 from jsonb_each(entry) where jsonb_typeof(value)<>'string')
       or exists(select 1 from jsonb_each_text(entry-array['priceRevision','reviewedPriceMinorUnits'])
         where value !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(value)>128)
       or jsonb_typeof(entry->'priceRevision') is distinct from 'string'
       or entry->>'priceRevision' !~ '^(0|[1-9][0-9]*)$'
       or entry->>'reviewedPriceMinorUnits' !~ '^[1-9][0-9]*$' then raise exception 'sale_item_invalid'; end if;
     perform 1 from public.spike_items where account_id=account and id=entry->>'itemId' for update;
     if not found then raise exception 'sale_item_unavailable'; end if;
     select * into placement from public.spike_item_placements where account_id=account and item_id=entry->>'itemId'
       and id=entry->>'placementId' and scope_kind='business_inventory' and ended_at is null for update;
     if not found or placement.started_at>=received then raise exception 'sale_placement_stale'; end if;
     -- Retained vendor-Purchase evidence, never caller-selected receipt IDs or
     -- a mutable Transaction total. Multiple acquisitions need reconciliation.
     perform r.id from public.transaction_receipt_items r join public.spike_transactions t
       on t.account_id=r.account_id and t.id=r.transaction_id
       where r.account_id=account and r.item_id=placement.item_id and t.type='purchase' for share of r,t;
     select count(*),min(r.amount_minor_units),min(r.currency) into cost_count,cost,cost_currency
       from public.transaction_receipt_items r join public.spike_transactions t on t.account_id=r.account_id and t.id=r.transaction_id
       where r.account_id=account and r.item_id=placement.item_id and t.type='purchase';
     if exists(select 1 from public.transaction_receipt_items r join public.spike_transactions t
       on t.account_id=r.account_id and t.id=r.transaction_id join public.spike_budget_categories cat
       on cat.account_id=t.account_id and cat.id=t.category_id where r.account_id=account and r.item_id=placement.item_id
       and t.type='purchase' and not ledger_private.can_view_budget_category(cat.account_id,cat.visibility_class)) then
       raise exception 'sale_acquisition_unavailable';
     end if;
     if cost_count>1 then raise exception 'sale_acquisition_ambiguous'; end if;
     if cost_count=1 and cost is null then raise exception 'sale_acquisition_unavailable'; end if;
     if cost_count=1 and cost_currency<>c->>'currency' then raise exception 'sale_currency_mismatch'; end if;
     select * into price from ledger_private.item_project_prices where account_id=account and item_id=entry->>'itemId' for update;
     price_exists := found;
     if (price_exists and price.revision::text is distinct from entry->>'priceRevision')
       or (not price_exists and entry->>'priceRevision'<>'0') then raise exception 'sale_price_stale'; end if;
     if price_exists and price.currency<>c->>'currency' then raise exception 'sale_currency_mismatch'; end if;
     reviewed := (entry->>'reviewedPriceMinorUnits')::bigint;
     normalized := greatest(case when price_exists then price.amount_minor_units else 0 end,coalesce(cost,0));
     if normalized>0 and reviewed<>normalized then raise exception 'sale_price_review_stale'; end if;
     if not price_exists then
       insert into ledger_private.item_project_prices(account_id,item_id,amount_minor_units,currency,updated_at,updated_by_principal_id)
         values(account,placement.item_id,reviewed,c->>'currency',received,actor) returning * into price;
     elsif price.amount_minor_units<>reviewed then
       update ledger_private.item_project_prices set amount_minor_units=reviewed,revision=revision+1,updated_at=received,updated_by_principal_id=actor
         where account_id=account and item_id=placement.item_id returning * into price;
     end if;
     -- Price facts are command-managed; no caller-supplied historical receipt or
     -- amount can substitute a cheaper acquisition or overwrite a paid basis.
     update public.spike_item_placements set ended_at=received,ended_by_principal_id=actor where id=placement.id;
     insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
       values(entry->>'newPlacementId',account,placement.item_id,'project',project,received,actor);
     insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,
       amount_minor_units,currency,created_at,created_by_principal_id)
       values(entry->>'occurrenceId',account,project,placement.item_id,entry->>'newPlacementId',category,
         price.amount_minor_units,price.currency,received,actor);
   end loop;
 exception
   when raise_exception then failure := SQLERRM;
   when integrity_constraint_violation or numeric_value_out_of_range then failure := 'sale_integrity_conflict';
 end;
 insert into public.spike_operation_results(operation_id,account_id,actor_principal_id,command_type,contract_version,
   command_fingerprint,envelope_sha256,subject_id,phase,result_code,error_code,client_created_at,server_received_at,
   completed_at,client_created_at_ms,server_received_at_ms,completed_at_ms)
 values(operation,account,actor,'sell_inventory_items','inventory-sale-v1',fingerprint,fingerprint,project,
   case when failure is null then 'applied' else 'rejected' end,
   case when failure is null then 'inventory_items_sold' end,failure,created,received,received,
   (c->>'createdAtMs')::bigint,floor(extract(epoch from received)*1000)::bigint,floor(extract(epoch from received)*1000)::bigint)
 returning * into result;
 return result;
end;
$sale$;
revoke all on function ledger_private.sell_inventory_items(text) from public,anon,authenticated,service_role;
-- Remain unexposed until command security, price admission and bulk/replay tests
-- pass. This private implementation is not yet the public app/MCP API.
