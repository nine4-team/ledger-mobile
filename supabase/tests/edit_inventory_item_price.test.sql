begin;
set local search_path=public,extensions;
select no_plan();
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values('inventory-price-item','account-primary','Inventory price','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id)
values('inventory-price-placement','account-primary','inventory-price-item','business_inventory','2026-01-01','principal-owner');
create function pg_temp.inventory_price(op text, revision text, requested text, reviewed text, clear text default 'false')
returns text language sql as $$
 select jsonb_build_object('operationId',op,'accountId','account-primary','actorPrincipalId','principal-owner',
  'contractVersion','item-inventory-price-edit-v2','createdAtMs','1000',
  'itemId','inventory-price-item','placementId','inventory-price-placement','expectedPriceRevision',revision,
  'requestedPriceMinorUnits',requested,'reviewedPriceMinorUnits',reviewed,'currency','USD','clearPrice',clear)::text;
$$;
select is(public.spike_read_item_price_edit('account-primary',null,'inventory-price-item'),
 jsonb_build_object('accountId','account-primary','principalId','principal-owner','projectId',null,
 'itemId','inventory-price-item','placementId','inventory-price-placement','occurrenceId',null,'currency',null,
 'priceRevision','0','chargeRevision',null,'currentPrice',null,'purchaseCost',jsonb_build_object('state','absent')),
 'New Inventory review has no invented currency or charge');
select throws_ok($$select public.spike_read_item_price_edit('account-primary',null,'foreign-item')$$,
 '22023','Item price review unavailable','Review denies out-of-scope Item');
select throws_ok($$select public.spike_read_item_price_edit('account-primary','project-primary','inventory-price-item')$$,
 '22023','Item price review unavailable','Inventory cannot be reviewed as Project Item');
select is((ledger_private.edit_inventory_item_price(pg_temp.inventory_price('inventory-zero','0','0','0'))).phase,'applied','Explicit zero saved');
select is((select amount_minor_units from ledger_private.item_project_prices where item_id='inventory-price-item'),0::bigint,'Zero is not null');
select is((ledger_private.edit_inventory_item_price(pg_temp.inventory_price('inventory-clear','1','0','0','true'))).phase,'applied','Explicit clear saved');
select is((select amount_minor_units from ledger_private.item_project_prices where item_id='inventory-price-item'),null::bigint,'Cleared price is absent');
select is((select revision from ledger_private.item_project_prices where item_id='inventory-price-item'),2::bigint,'Clear advances revision');
select is(public.spike_read_item_price_edit('account-primary',null,'inventory-price-item')->>'currency','USD','Cleared review retains currency');
select is(public.spike_read_item_price_edit('account-primary',null,'inventory-price-item')->>'priceRevision','2','Cleared review retains revision');
select is(public.spike_read_item_price_edit('account-primary',null,'inventory-price-item')->'currentPrice','null'::jsonb,'Cleared review preserves absence');
select is((ledger_private.edit_inventory_item_price(pg_temp.inventory_price('inventory-clear','1','0','0','true'))).phase,'applied','Identical clear replay');
select is((select revision from ledger_private.item_project_prices where item_id='inventory-price-item'),2::bigint,'Replay preserves revision');
select is((ledger_private.edit_inventory_item_price(pg_temp.inventory_price('inventory-stale','0','100','100'))).error_code,'price_revision_stale','Clear never resets revision to zero');
select throws_ok($$select ledger_private.edit_inventory_item_price(pg_temp.inventory_price('inventory-clear','2','100','100'))$$,
 '23505','Operation identity conflict','Same operation cannot change intent');
insert into public.spike_transactions(id,account_id,amount_minor_units,currency,type,origin,scope_kind,category_id)
values('inventory-cost','account-primary',150,'USD','purchase','vendor_payment','business_inventory','category-furnishings');
insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
values('inventory-cost-line','account-primary','inventory-cost','inventory-price-item','USD',150,'sold');
select is((ledger_private.edit_inventory_item_price(pg_temp.inventory_price('inventory-below-cost','2','0','0','true'))).error_code,
 'price_review_stale','Clear cannot bypass known positive cost');
select is((ledger_private.edit_inventory_item_price(pg_temp.inventory_price('inventory-floor','2','0','150','true'))).phase,
 'applied','Reviewed clear normalizes to cost');
select is((select amount_minor_units from ledger_private.item_project_prices where item_id='inventory-price-item'),150::bigint,'Cost floor applied');
select is((select amount_minor_units from public.transaction_receipt_items where id='inventory-cost-line'),150::bigint,'Acquisition remains unchanged');
select is((select count(*) from ledger_private.item_charge_occurrences where item_id='inventory-price-item'),0::bigint,'Inventory edit creates no Project charge');
select is((select count(*) from public.spike_transactions where id='inventory-cost'),1::bigint,'Original Purchase retained');
select is((ledger_private.edit_inventory_item_price(pg_temp.inventory_price('inventory-exact','3','9223372036854775807','9223372036854775807'))).phase,
 'applied','Exact Int64 maximum accepted without floating point');
select is((select amount_minor_units from ledger_private.item_project_prices where item_id='inventory-price-item'),9223372036854775807::bigint,'Exact maximum stored');
select throws_ok($$select ledger_private.edit_inventory_item_price(pg_temp.inventory_price('inventory-negative','4','-1','150'))$$,
 '22023','Invalid Inventory price command','Negative amount denied');
select throws_ok($$select ledger_private.edit_inventory_item_price(pg_temp.inventory_price('inventory-overflow','4','9223372036854775808','9223372036854775808'))$$,
 '22023','Invalid Inventory price command','Overflow denied');
select is((ledger_private.edit_inventory_item_price((pg_temp.inventory_price('inventory-placement','4','200','200')::jsonb ||
 '{"placementId":"other"}')::text)).error_code,'price_placement_stale','Exact Inventory placement required');
select is((ledger_private.edit_inventory_item_price((pg_temp.inventory_price('inventory-other-item','4','200','200')::jsonb ||
 '{"itemId":"foreign-item"}')::text)).error_code,'price_item_unavailable','Out-of-scope Item denied');
update public.spike_account_memberships set financial_access='none' where account_id='account-primary' and principal_id='principal-owner';
select throws_ok($$select public.spike_read_item_price_edit('account-primary',null,'inventory-price-item')$$,
 '42501','Item price access required','Financial withdrawal prevents Inventory review');
select throws_ok($$select ledger_private.edit_inventory_item_price(pg_temp.inventory_price('inventory-exact','3','9223372036854775807','9223372036854775807'))$$,
 '42501','Item price access required','Financial withdrawal prevents replay disclosure');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select ledger_private.edit_inventory_item_price(pg_temp.inventory_price('inventory-anon','4','200','200'))$$,
 '42501','Authenticated actor required','Anonymous denied');
select ok(has_function_privilege('authenticated','ledger_private.edit_inventory_item_price(text)','execute'),'Authenticated branch callable through invoker endpoint');
select ok(not has_function_privilege('anon','ledger_private.edit_inventory_item_price(text)','execute'),'No anonymous API');
select ok(not has_function_privilege('service_role','ledger_private.edit_inventory_item_price(text)','execute'),'No service-role app bypass');
select ok(not (select prosecdef from pg_proc where oid='public.spike_edit_uncollected_item_price(text)'::regprocedure),'Shared public endpoint remains security invoker');
update public.spike_account_memberships set financial_access='full' where account_id='account-primary' and principal_id='principal-owner';
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select is(public.spike_read_item_price_edit('account-primary',null,'inventory-price-item')->'purchaseCost'->>'amountMinorUnits',
 '150','Authenticated invoker review reads exact acquisition cost');
select is((public.spike_edit_uncollected_item_price(pg_temp.inventory_price('inventory-endpoint','4','200','200'))).phase,
 'applied','Existing authenticated endpoint routes Inventory v2');
reset role;
select * from finish();
rollback;
