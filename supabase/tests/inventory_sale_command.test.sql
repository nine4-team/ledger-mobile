begin;
set local search_path=public,extensions;
select no_plan();
update public.spike_accounts set furnishings_category_id='category-furnishings' where id='account-primary';
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('sale-destination','account-primary','client-existing','Sale destination',now(),now(),1,1,'principal-owner');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values ('sale-item-a','account-primary','A','principal-owner'),('sale-item-b','account-primary','B','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id)
values ('sale-old-a','account-primary','sale-item-a','business_inventory','2026-01-01','principal-owner'),
 ('sale-old-b','account-primary','sale-item-b','business_inventory','2026-01-01','principal-owner');
insert into ledger_private.item_project_prices(account_id,item_id,amount_minor_units,currency,updated_at,updated_by_principal_id)
values ('account-primary','sale-item-a',100,'USD',now(),'principal-owner'),('account-primary','sale-item-b',200,'USD',now(),'principal-owner');
insert into public.spike_transactions(id,account_id,amount_minor_units,currency,type,origin,scope_kind,category_id)
values ('sale-acquisition','account-primary',150,'USD','purchase','vendor_payment','business_inventory','category-furnishings');
insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
values ('sale-acquisition-item','account-primary','sale-acquisition','sale-item-a','USD',150,'linked');
-- A previous collected project cycle must survive a new Inventory sale.
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,
 started_at,started_by_principal_id,ended_at,ended_by_principal_id)
values ('historical-placement','account-primary','sale-item-a','project','sale-destination',
 '2025-01-01','principal-owner','2025-12-01','principal-owner');
insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,
 category_id,amount_minor_units,currency,created_at,created_by_principal_id)
values ('historical-charge','account-primary','sale-destination','sale-item-a','historical-placement',
 'category-furnishings',900,'USD','2025-01-01','principal-owner');
select ledger_private.import_client_payment('historical-payment','account-primary','sale-destination','client-existing',
 900,'USD','synthetic-sale-history','historical-payment','\x01'::bytea);
insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
values ('historical-invoice','account-primary','sale-destination','client-existing','historical-payment',1,'USD',900);
insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,
 source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
values ('historical-line','account-primary','historical-invoice',0,'USD','item','historical-charge','sale-item-a',
 1,'category-furnishings',900,'Previous sale','{}');
update ledger_private.collected_invoices set sealed=true where id='historical-invoice';
set constraints all immediate;
set constraints all deferred;
create temp table sale_history_before as
 select 'charge' as kind,to_jsonb(c) as value from ledger_private.item_charge_occurrences c where id='historical-charge'
 union all select 'invoice',to_jsonb(i) from ledger_private.collected_invoices i where id='historical-invoice'
 union all select 'line',to_jsonb(l) from ledger_private.collected_invoice_lines l where id='historical-line'
 union all select 'payment',to_jsonb(t) from public.spike_transactions t where id='historical-payment';
create function pg_temp.sale_command(op text, second_revision text default '1') returns text language sql as $$
 select jsonb_build_object('operationId',op,'accountId','account-primary','actorPrincipalId','principal-owner',
  'projectId','sale-destination','contractVersion','inventory-sale-v1','createdAtMs','1788523200000','currency','USD','items',
  jsonb_build_array(jsonb_build_object('itemId','sale-item-a','placementId','sale-old-a','priceRevision','1','reviewedPriceMinorUnits','150','newPlacementId','sale-new-a','occurrenceId','sale-charge-a'),
   jsonb_build_object('itemId','sale-item-b','placementId','sale-old-b','priceRevision',second_revision,'reviewedPriceMinorUnits','200','newPlacementId','sale-new-b','occurrenceId','sale-charge-b')))::text
$$;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select is(public.spike_read_inventory_sale_review('account-primary',array['sale-item-a','sale-item-b'])#>'{items,0,purchaseCost}',
 '{"state":"known","amountMinorUnits":"150","currency":"USD"}'::jsonb,'Review reads authoritative acquisition amount as decimal text');
select is(public.spike_read_inventory_sale_review('account-primary',array['sale-item-b'])#>'{items,0,purchaseCost}',
 '{"state":"absent"}'::jsonb,'Complete source read distinguishes absent acquisition');
select throws_ok($$select public.spike_read_inventory_sale_review('account-other',array['sale-item-a'])$$,
 '42501','Active Account membership required','Review denies foreign Account');
select throws_ok($$select public.spike_read_inventory_sale_review('account-primary',array['sale-item-a','sale-item-a'])$$,
 '22023','Invalid Item selection','Review rejects duplicate selections');
reset role;
select is((ledger_private.sell_inventory_items(jsonb_set(pg_temp.sale_command('sale-below-cost')::jsonb,'{items,0,reviewedPriceMinorUnits}','"100"'::jsonb)::text)).error_code,
 'sale_price_review_stale','Caller cannot sell below recorded purchase cost');
update public.spike_projects set lifecycle='archived',revision=revision+1 where id='sale-destination';
select is((ledger_private.sell_inventory_items(pg_temp.sale_command('sale-archived'))).error_code,'sale_destination_unavailable','Archived Project denied');
update public.spike_projects set lifecycle='active',revision=revision+1 where id='sale-destination';
update public.spike_clients set lifecycle='archived',revision=revision+1 where id='client-existing';
select is((ledger_private.sell_inventory_items(pg_temp.sale_command('sale-client-archived'))).error_code,'sale_destination_unavailable','Archived Client denied');
update public.spike_clients set lifecycle='active',revision=revision+1 where id='client-existing';
select is((ledger_private.sell_inventory_items(jsonb_set(pg_temp.sale_command('sale-numeric-id')::jsonb,'{items,1,newPlacementId}','123'::jsonb)::text)).error_code,
 'sale_item_invalid','Numeric identity does not silently become text');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select throws_ok($$select ledger_private.sell_inventory_items(pg_temp.sale_command('sale-spoof'))$$,'42501',null,'Foreign actor cannot impersonate owner');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((ledger_private.sell_inventory_items(pg_temp.sale_command('sale-stale','2'))).error_code,'sale_price_stale','Stale second Item rejects whole batch');
select is((select count(*) from public.spike_item_placements where id in ('sale-old-a','sale-old-b') and ended_at is null),2::bigint,'First Item remains in Inventory after later failure');
select is((select count(*) from ledger_private.item_charge_occurrences where account_id='account-primary' and id in ('sale-charge-a','sale-charge-b')),0::bigint,'No partial demand');
select is((select amount_minor_units from ledger_private.item_project_prices where item_id='sale-item-a'),100::bigint,'Failed batch rolls back price normalization too');
select is((ledger_private.sell_inventory_items(pg_temp.sale_command('sale-stale','2'))).error_code,'sale_price_stale','Rejected replay is stable');
create temp table sale_transaction_before as select count(*) as n from public.spike_transactions;
set local role authenticated;
select is((public.spike_sell_inventory_items(pg_temp.sale_command('sale-success'))).phase,'applied','Authenticated endpoint sells selection atomically');
reset role;
select is((ledger_private.sell_inventory_items(pg_temp.sale_command('sale-success'))).phase,'applied','Applied replay succeeds without repeating effects');
select is((select count(*) from public.spike_item_placements where id in ('sale-old-a','sale-old-b') and ended_at is not null),2::bigint,'Inventory placement history is retained and closed');
select is((select count(*) from public.spike_item_placements where id in ('sale-new-a','sale-new-b') and project_id='sale-destination' and ended_at is null),2::bigint,'Exactly two destination placements');
select is((select sum(amount_minor_units)::bigint from ledger_private.item_charge_occurrences where account_id='account-primary' and id in ('sale-charge-a','sale-charge-b')),350::bigint,'Fresh charges retain exact reviewed amounts');
select is((select amount_minor_units from ledger_private.item_project_prices where item_id='sale-item-a'),150::bigint,'Approved floor persisted atomically');
select is((select amount_minor_units from public.transaction_receipt_items where id='sale-acquisition-item'),150::bigint,'Acquisition amount remains unchanged');
select is((select count(*) from public.spike_transactions),(select n from sale_transaction_before),'No synthetic payment Transaction');
select is((select to_jsonb(c) from ledger_private.item_charge_occurrences c where id='historical-charge'),
 (select value from sale_history_before where kind='charge'),'Prior collected charge remains byte-for-byte equivalent');
select is((select to_jsonb(i) from ledger_private.collected_invoices i where id='historical-invoice'),
 (select value from sale_history_before where kind='invoice'),'Prior collected Invoice remains unchanged');
select is((select to_jsonb(l) from ledger_private.collected_invoice_lines l where id='historical-line'),
 (select value from sale_history_before where kind='line'),'Frozen membership and price remain unchanged');
select is((select to_jsonb(t) from public.spike_transactions t where id='historical-payment'),
 (select value from sale_history_before where kind='payment'),'Client payment is neither a sale cost nor rewritten');
select throws_ok($$select ledger_private.sell_inventory_items(pg_temp.sale_command('sale-success','2'))$$,'23505',null,'Operation identity cannot bind a different selection');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values ('sale-prompt','account-primary','Prompt','principal-owner'),('sale-ambiguous-item','account-primary','Ambiguous','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id)
values ('sale-prompt-old','account-primary','sale-prompt','business_inventory','2026-01-01','principal-owner'),
 ('sale-ambiguous-old','account-primary','sale-ambiguous-item','business_inventory','2026-01-01','principal-owner');
create function pg_temp.single_sale(op text,item text,old_placement text,amount text,actor text default 'principal-owner') returns text language sql as $$
 select (pg_temp.sale_command(op)::jsonb || jsonb_build_object('actorPrincipalId',actor,'items',jsonb_build_array(jsonb_build_object(
  'itemId',item,'placementId',old_placement,'priceRevision','0','reviewedPriceMinorUnits',amount,'newPlacementId',op||'-new','occurrenceId',op||'-charge'))))::text
$$;
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values ('sale-unknown-cost','account-primary','Unknown cost','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id)
values ('sale-unknown-old','account-primary','sale-unknown-cost','business_inventory','2026-01-01','principal-owner');
insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
values ('sale-unknown-receipt','account-primary','sale-acquisition','sale-unknown-cost','USD',null,'linked');
select is(public.spike_read_inventory_sale_review('account-primary',array['sale-unknown-cost'])#>'{items,0,purchaseCost}',
 '{"state":"unavailable"}'::jsonb,'Existing receipt with unknown cost is not absent or zero');
select is((ledger_private.sell_inventory_items(pg_temp.single_sale('unknown-cost-denied','sale-unknown-cost','sale-unknown-old','100'))).error_code,
 'sale_acquisition_unavailable','Unknown recorded acquisition amount blocks sale despite positive entered price');
select is((select count(*) from ledger_private.item_project_prices where item_id='sale-unknown-cost'),0::bigint,
 'Unknown cost rejection does not persist an invented price');
select is((select count(*) from public.spike_item_placements where item_id='sale-unknown-cost' and scope_kind='business_inventory' and ended_at is null),1::bigint,
 'Unknown cost rejection preserves Inventory placement');
select is((select state from ledger_private.item_acquisition_reviews where id='sale-unknown-cost'),'unavailable','Unknown receipt amount propagates to download review');
update public.transaction_receipt_items set amount_minor_units=100 where id='sale-unknown-receipt';
select is((select amount_minor_units from ledger_private.item_acquisition_reviews where id='sale-unknown-cost'),100::bigint,'Completing receipt amount refreshes derived cost');
update public.spike_transactions set category_id='category-design-fee' where id='sale-acquisition';
select ok((select requires_full_access from ledger_private.item_acquisition_reviews where id='sale-unknown-cost'),'Existing Transaction propagation withdraws ordinary cost visibility');
update public.spike_budget_categories set kind='general',revision=revision+1,updated_at_ms=updated_at_ms+1 where id='category-design-fee';
select ok(not (select requires_full_access from ledger_private.item_acquisition_reviews where id='sale-unknown-cost'),'Category kind change refreshes visibility even though visibility_class is derived');
update public.spike_budget_categories set kind='fee',revision=revision+1,updated_at_ms=updated_at_ms+1 where id='category-design-fee';
select ok((select requires_full_access from ledger_private.item_acquisition_reviews where id='sale-unknown-cost'),'Fee reclassification restores protected cost visibility');
update public.spike_transactions set category_id='category-furnishings' where id='sale-acquisition';
select is((ledger_private.sell_inventory_items(pg_temp.single_sale('prompt-zero','sale-prompt','sale-prompt-old','0'))).error_code,
 'sale_item_invalid','A missing price does not become a free sale');
select is((ledger_private.sell_inventory_items(pg_temp.single_sale('prompt-success','sale-prompt','sale-prompt-old','75'))).phase,
 'applied','Explicit positive review initializes missing price');
select is((select amount_minor_units from ledger_private.item_project_prices where item_id='sale-prompt'),75::bigint,'Entered price persists with sale');
insert into public.spike_transactions(id,account_id,amount_minor_units,currency,type,origin,scope_kind,category_id)
values ('sale-hidden-acquisition','account-primary',100,'EUR','purchase','vendor_payment','business_inventory','category-design-fee');
insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
values ('sale-ambiguous-one','account-primary','sale-acquisition','sale-ambiguous-item','USD',10,'linked'),
 ('sale-ambiguous-two','account-primary','sale-hidden-acquisition','sale-ambiguous-item','EUR',100,'sold');
select is((ledger_private.sell_inventory_items(pg_temp.single_sale('ambiguous-owner','sale-ambiguous-item','sale-ambiguous-old','100'))).error_code,
 'sale_acquisition_ambiguous','Full-access actor must reconcile multiple acquisitions, not choose a cheap receipt');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select is(public.spike_read_inventory_sale_review('account-primary',array['sale-ambiguous-item'])#>'{items,0,purchaseCost}',
 '{"state":"unavailable"}'::jsonb,'Protected acquisition exposes no amount, currency or count in review');
select is((ledger_private.sell_inventory_items(pg_temp.single_sale('ambiguous-restricted','sale-ambiguous-item','sale-ambiguous-old','100','principal-restricted'))).error_code,
 'sale_acquisition_unavailable','Restricted actor does not learn ambiguity or currency of hidden acquisition');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-owner';
select throws_ok($$select ledger_private.sell_inventory_items(pg_temp.sale_command('sale-success'))$$,'42501',null,'Removed member cannot replay/read a former result');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select ledger_private.sell_inventory_items(pg_temp.sale_command('sale-anon'))$$,'42501',null,'Unauthenticated invocation denied');
select ok(has_function_privilege('authenticated','public.spike_sell_inventory_items(text)','EXECUTE'),'Authenticated users may invoke the narrow command');
select ok(not has_function_privilege('anon','public.spike_sell_inventory_items(text)','EXECUTE'),'Anonymous role cannot invoke sale endpoint');
select ok(not has_function_privilege('service_role','public.spike_sell_inventory_items(text)','EXECUTE'),'No service-role app bypass');
select ok(not (select prosecdef from pg_proc where oid='public.spike_sell_inventory_items(text)'::regprocedure),'Public wrapper is security invoker');
set local role authenticated;
select throws_ok($$select public.spike_sell_inventory_items(pg_temp.sale_command('endpoint-no-auth'))$$,'42501',null,'Public endpoint still requires authenticated identity');
select throws_ok($$insert into ledger_private.item_project_prices(account_id,item_id,amount_minor_units,currency,updated_by_principal_id)
 values ('account-primary','sale-item-a',1,'USD','principal-owner')$$,'42501',null,'Command grant does not enable direct price writes');
reset role;
select * from finish();
rollback;
