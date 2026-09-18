begin;
set local search_path=public,extensions;
select no_plan();
select throws_ok($$insert into public.spike_transactions(id,account_id,amount_minor_units,currency,type,origin,scope_kind,category_id)
 values('invalid-zero-return','account-primary',0,'USD','return','vendor_payment','business_inventory','category-furnishings')$$,
 '23514',null,'zero exception is Purchase-only, not Return');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values('adjustment-project','account-primary','client-existing','Adjustments',now(),now(),1,1,'principal-owner');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values('adjustment-item','account-primary','Chair','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
values('adjustment-placement','account-primary','adjustment-item','project','adjustment-project','2026-01-01','principal-owner');
insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,amount_minor_units,currency,created_by_principal_id)
values('adjustment-charge','account-primary','adjustment-project','adjustment-item','adjustment-placement','category-furnishings',100,'USD','principal-owner');
insert into ledger_private.live_invoices(id,account_id,project_id,name,status,created_at,created_by_principal_id)
values('adjustment-invoice','account-primary','adjustment-project','Invoice','sent',now(),'principal-owner');
insert into ledger_private.live_invoice_memberships(account_id,invoice_id,source_kind,source_id,position)
values('account-primary','adjustment-invoice','item','adjustment-charge',0);
insert into public.spike_transactions(id,account_id,amount_minor_units,currency,type,origin,scope_kind,category_id,non_item_receipt_lines)
values('adjustment-order','account-primary',120,'USD','purchase','vendor_payment','business_inventory','category-furnishings',
 '[{"id":"shipping","description":"Shipping","amountMinorUnits":"20","effect":"increase"}]');
insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
values('adjustment-receipt','account-primary','adjustment-order','adjustment-item','USD',100,'linked');
create function pg_temp.adjustment_command(op text,price text) returns text language sql as $$
select jsonb_build_object('operationId',op,'accountId','account-primary','actorPrincipalId','principal-owner',
 'contractVersion','item-live-adjustment-price-edit-v3','createdAtMs','1788523200000',
 'projectId','adjustment-project','itemId','adjustment-item','placementId','adjustment-placement','occurrenceId','adjustment-charge',
 'transactionId','adjustment-order',
 'expectedAdjustmentRevision',(select revision::text from ledger_private.item_adjustment_orders where id='adjustment-order'),
 'expectedPriceRevision',coalesce((select revision::text from ledger_private.item_project_prices where item_id='adjustment-item'),'0'),
 'expectedChargeRevision',(select revision::text from ledger_private.item_charge_occurrences where id='adjustment-charge'),
 'requestedPriceMinorUnits',price,'reviewedPriceMinorUnits',price,'currency','USD')::text;
$$;
create temporary table saved_command as select pg_temp.adjustment_command('adjustment-op','120') as command;
select is((select count(*) from ledger_private.item_adjustment_inputs where item_id='adjustment-item'),0::bigint,'legacy acquisition amount is not guessed into a live input');
select is((select snapshot->'items'->0->>'issue' from ledger_private.item_adjustment_orders where id='adjustment-order'),'unknownInput','migration-compatible receipt projection retains unknown inclusion');
grant select on saved_command to authenticated;
set local role authenticated;
select is((public.spike_edit_uncollected_item_price((select command from saved_command))).phase,'applied','inclusive price edit saves original input through authenticated endpoint');
reset role;
select is((select input->>'numerator' from ledger_private.item_adjustment_inputs where item_id='adjustment-item'),'100','exact unadjusted input persisted');
select is((select amount_minor_units from ledger_private.item_project_prices where item_id='adjustment-item'),120::bigint,'current price includes adjustment once');
select is(ledger_private.read_live_invoice('account-primary','adjustment-project','adjustment-invoice')->>'totalMinorUnits','120','live Invoice receives current calculated price');
select is((ledger_private.edit_live_item_price((select command from saved_command))).phase,'applied','identical replay accepted');
select is((select revision from ledger_private.item_project_prices where item_id='adjustment-item'),1::bigint,'replay does not recalculate twice');
select is((ledger_private.edit_live_item_price(((select command::jsonb from saved_command)||'{"operationId":"adjustment-stale"}')::text)).error_code,'price_revision_stale','stale order revision rejected');
select is((ledger_private.edit_live_item_price(pg_temp.adjustment_command('adjustment-zero','0'))).phase,'applied','valid zero current price remains savable');
select is(ledger_private.read_live_invoice('account-primary','adjustment-project','adjustment-invoice')->>'totalMinorUnits','0','zero remains current amount with source identity retained');
select is((select count(*) from ledger_private.live_invoice_memberships where invoice_id='adjustment-invoice' and released_at is null),1::bigint,'zero does not withdraw Invoice membership');
select is((ledger_private.edit_live_item_price(pg_temp.adjustment_command('adjustment-restore','120'))).phase,'applied','current zero remains editable');
update public.spike_transactions set non_item_receipt_lines='[{"id":"shipping","description":"Shipping","amountMinorUnits":"120","effect":"increase"}]'
 where id='adjustment-order';
select is((select amount_minor_units from ledger_private.item_project_prices where item_id='adjustment-item'),null::bigint,'invalid base never presents old current price');
select throws_ok($$select ledger_private.read_live_invoice('account-primary','adjustment-project','adjustment-invoice')$$,'55000','invoice_sources_incomplete','uncalculable source uses existing incomplete readiness');
select is((ledger_private.edit_live_item_price(pg_temp.adjustment_command('adjustment-invalid-save','240'))).phase,'applied','calculation issue does not lock input saves');
select is((select input->>'requestedProjectPriceMinorUnits' from ledger_private.item_adjustment_inputs where item_id='adjustment-item'),'240','invalid-base inclusive intent retained');
update public.spike_transactions set non_item_receipt_lines='[{"id":"shipping","description":"Shipping","amountMinorUnits":"20","effect":"increase"}]'
 where id='adjustment-order';
select is((select amount_minor_units from ledger_private.item_project_prices where item_id='adjustment-item'),240::bigint,'fixing inputs recalculates saved intent');
select is((select amount_minor_units from public.transaction_receipt_items where id='adjustment-receipt'),100::bigint,'original acquisition evidence unchanged');
select ledger_private.import_client_payment('adjustment-payment','account-primary','adjustment-project','client-existing',
 240,'USD','adjustment-test','adjustment-payment',decode('01','hex'));
insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
values('adjustment-paid','account-primary','adjustment-project','client-existing','adjustment-payment',1,'USD',240);
insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,
 source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
select 'adjustment-paid-line','account-primary','adjustment-paid',0,'USD','item','adjustment-charge','adjustment-item',revision,
 'category-furnishings',240,'Frozen chair','{}' from ledger_private.item_charge_occurrences where id='adjustment-charge';
update ledger_private.collected_invoices set sealed=true where id='adjustment-paid';
select is((ledger_private.edit_live_item_price(pg_temp.adjustment_command('adjustment-after-collection','60'))).phase,'applied','current Item remains editable after collection without purchase floor');
select is((select amount_minor_units from ledger_private.item_project_prices where item_id='adjustment-item'),60::bigint,'inclusive discounted price is not raised to acquisition cost');
select is((select amount_minor_units from ledger_private.item_charge_occurrences where id='adjustment-charge'),240::bigint,'collected source unchanged');
select is((select signed_amount_minor_units from ledger_private.collected_invoice_lines where id='adjustment-paid-line'),240::bigint,'frozen Invoice line unchanged');
select is((select amount_minor_units from public.spike_transactions where id='adjustment-payment'),240::bigint,'historical payment unchanged');
select is(public.spike_read_item_price_edit('account-primary','adjustment-project','adjustment-item')->'currentPrice'->>'amountMinorUnits','60','collected current Item is available for editing');
update saved_command set command=pg_temp.adjustment_command('adjustment-reassociated','90');
update public.transaction_receipt_items set membership_kind='sold' where id='adjustment-receipt';
select is((select live_pricing from ledger_private.item_acquisition_reviews where id='adjustment-item'),null::jsonb,'reassociation removes obsolete current pricing context');
select is((ledger_private.edit_live_item_price((select command from saved_command))).error_code,'price_acquisition_ambiguous','reassociated offline intent cannot rewrite the old order');
-- Positive collection with a zero Item is distinct from whole-Invoice zero.
insert into public.spike_items(id,account_id,description,created_by_principal_id)
 select id,'account-primary',id,'principal-owner' from unnest(array['zero-source','positive-source']) id;
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
 select id,'account-primary',id,'project','adjustment-project','2026-01-01','principal-owner'
 from unnest(array['zero-source','positive-source']) id;
insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,amount_minor_units,currency,created_by_principal_id,adjustment_transaction_id,adjustment_revision)
 values('zero-source','account-primary','adjustment-project','zero-source','zero-source','category-furnishings',0,'USD','principal-owner','adjustment-order',1),
 ('positive-source','account-primary','adjustment-project','positive-source','positive-source','category-furnishings',100,'USD','principal-owner',null,null);
select ledger_private.import_client_payment('positive-with-zero-payment','account-primary','adjustment-project','client-existing',100,'USD','adjustment-test','positive-with-zero-payment',decode('02','hex'));
insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
 values('positive-with-zero','account-primary','adjustment-project','client-existing','positive-with-zero-payment',1,'USD',100);
insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
 select id,'account-primary','positive-with-zero',case when id='zero-source' then 0 else 1 end,'USD','item',id,id,revision,'category-furnishings',amount_minor_units,id,'{}'
 from ledger_private.item_charge_occurrences where id in ('zero-source','positive-source');
update ledger_private.collected_invoices set sealed=true where id='positive-with-zero';
set constraints all immediate;
select ok((select sealed and total_minor_units=100 from ledger_private.collected_invoices where id='positive-with-zero'),'positive Invoice containing zero Item collects and seals');
select is((select signed_amount_minor_units from ledger_private.collected_invoice_lines where id='zero-source'),0::bigint,'collection retains zero source identity and amount');
set constraints all deferred;
update public.spike_account_memberships set financial_access='none' where account_id='account-primary' and principal_id='principal-owner';
select throws_ok($$select ledger_private.edit_live_item_price(pg_temp.adjustment_command('adjustment-revoked','120'))$$,'42501','Item price access required','revoked financial authority is checked before replay or mutation');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select throws_ok($$select ledger_private.edit_live_item_price(pg_temp.adjustment_command('adjustment-spoof','120'))$$,'42501','Authenticated actor required','spoofed actor denied');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select ledger_private.edit_live_item_price(pg_temp.adjustment_command('adjustment-anon','120'))$$,'42501','Authenticated actor required','anonymous write denied');
select ok(not has_function_privilege('anon','ledger_private.edit_live_item_price(text)','EXECUTE'),'anonymous execution is not granted');
select ok(not has_table_privilege('authenticated','ledger_private.item_adjustment_inputs','UPDATE'),'direct input writes are denied');
select * from finish();
rollback;
