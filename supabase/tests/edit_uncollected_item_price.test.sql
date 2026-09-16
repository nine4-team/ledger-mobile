begin;
set local search_path=public,extensions;
select no_plan();
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values('price-project','account-primary','client-existing','Price test',now(),now(),1,1,'principal-owner');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values('price-item','account-primary','Chair','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
values('price-placement','account-primary','price-item','project','price-project','2026-01-01','principal-owner');
insert into ledger_private.item_project_prices(account_id,item_id,amount_minor_units,currency,updated_at,updated_by_principal_id)
values('account-primary','price-item',100,'USD','2026-01-01','principal-owner');
insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,amount_minor_units,currency,created_by_principal_id)
values('price-charge','account-primary','price-project','price-item','price-placement','category-furnishings',100,'USD','principal-owner');
insert into ledger_private.live_invoices(id,account_id,project_id,name,status,created_at,created_by_principal_id)
values('price-invoice','account-primary','price-project','Invoice','sent',now(),'principal-owner');
insert into ledger_private.live_invoice_memberships(account_id,invoice_id,source_kind,source_id,position)
values('account-primary','price-invoice','item','price-charge',0);
create function pg_temp.price_command(op text) returns text language sql as $$
select jsonb_build_object('operationId',op,'accountId','account-primary','actorPrincipalId','principal-owner',
 'contractVersion','item-uncollected-price-edit-v1','createdAtMs','1788523200000',
 'projectId','price-project','itemId','price-item','placementId','price-placement','occurrenceId','price-charge',
 'expectedPriceRevision','1','expectedChargeRevision','1','requestedPriceMinorUnits','200','reviewedPriceMinorUnits','200','currency','USD')::text;
$$;
set local role authenticated;
select is(public.spike_read_item_price_edit('account-primary','price-project','price-item')->'currentPrice'->>'amountMinorUnits',
 '100','Review reads exact current price, not live Invoice total');
select is(public.spike_read_item_price_edit('account-primary','price-project','price-item')->'purchaseCost'->>'state',
 'absent','Review distinguishes no purchase evidence from zero cost');
select throws_ok($$select public.spike_read_item_price_edit('account-other','price-project','price-item')$$,
 '42501','Item price access required','Review cannot cross Account scope');
select is((public.spike_edit_uncollected_item_price(pg_temp.price_command('price-op'))).phase,'applied','Authenticated endpoint applies scoped price edit');
reset role;
select is((select amount_minor_units from ledger_private.item_project_prices where item_id='price-item'),200::bigint,'Current price changes');
select is((select revision from ledger_private.item_charge_occurrences where id='price-charge'),2::bigint,'Exact open charge advances');
select is(ledger_private.read_live_invoice('account-primary','price-project','price-invoice')->>'totalMinorUnits','200','Sent Invoice derives new total');
select is((ledger_private.edit_uncollected_item_price(pg_temp.price_command('price-op'))).phase,'applied','Exact retry is stable');
select is((select revision from ledger_private.item_charge_occurrences where id='price-charge'),2::bigint,'Retry does not reapply');
select is((ledger_private.edit_uncollected_item_price(pg_temp.price_command('price-stale'))).error_code,'price_charge_stale','Stale new operation is rejected');
select ok(not has_function_privilege('anon','public.spike_edit_uncollected_item_price(text)','EXECUTE'),'Anonymous endpoint execution denied');
select ok(not has_function_privilege('anon','public.spike_read_item_price_edit(text,text,text)','EXECUTE'),'Anonymous review execution denied');
select ok(not has_table_privilege('authenticated','ledger_private.item_project_prices','UPDATE'),'Endpoint grants no direct price writes');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select throws_ok($$select ledger_private.edit_uncollected_item_price(pg_temp.price_command('price-spoof'))$$,
 '42501','Authenticated actor required','Another identity cannot claim the owner');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select ledger_private.edit_uncollected_item_price(pg_temp.price_command('price-anon'))$$,
 '42501','Authenticated actor required','No authenticated subject is denied');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
insert into public.spike_transactions(id,account_id,amount_minor_units,currency,type,origin,scope_kind,category_id)
values('price-acquisition','account-primary',150,'USD','purchase','vendor_payment','business_inventory','category-furnishings');
insert into public.transaction_receipt_items(id,account_id,transaction_id,item_id,currency,amount_minor_units,membership_kind)
values('price-receipt','account-primary','price-acquisition','price-item','USD',150,'linked');
select is(public.spike_read_item_price_edit('account-primary','price-project','price-item')->'purchaseCost'->>'amountMinorUnits',
 '150','Review uses actual purchase receipt cost');
create function pg_temp.next_price_command(op text, requested text, reviewed text) returns text language sql as $$
 select (pg_temp.price_command(op)::jsonb || jsonb_build_object('expectedPriceRevision','2','expectedChargeRevision','2',
  'requestedPriceMinorUnits',requested,'reviewedPriceMinorUnits',reviewed))::text;
$$;
select is((ledger_private.edit_uncollected_item_price(pg_temp.next_price_command('price-below','100','100'))).error_code,
 'price_review_stale','Cannot bypass the acquisition floor');
select is((select amount_minor_units from ledger_private.item_project_prices where item_id='price-item'),200::bigint,
 'Rejected review leaves current price intact');
insert into ledger_private.fee_installments(id,account_id,project_id,category_id,label,amount_minor_units,currency,created_by_principal_id,created_at)
select 'price-fee','account-primary','price-project','category-furnishings','Overflow companion',100,'USD','principal-owner',now();
insert into ledger_private.live_invoice_memberships(account_id,invoice_id,source_kind,source_id,position)
values('account-primary','price-invoice','fee_installment','price-fee',1);
select is((ledger_private.edit_uncollected_item_price(pg_temp.next_price_command('price-overflow','9223372036854775807','9223372036854775807'))).error_code,
 'price_integrity_conflict','Overflow rolls back the whole price edit');
select is((select amount_minor_units from ledger_private.item_charge_occurrences where id='price-charge'),200::bigint,
 'Overflow does not change charge');
select is((select revision from ledger_private.item_project_prices where item_id='price-item'),2::bigint,
 'Overflow does not consume price revision');
select is((ledger_private.edit_uncollected_item_price(pg_temp.next_price_command('price-floor','100','150'))).phase,
 'applied','Confirmed normalized price applies');
select is((select amount_minor_units from public.transaction_receipt_items where id='price-receipt'),150::bigint,
 'Price editing never rewrites acquisition');
select ledger_private.import_client_payment('price-payment','account-primary','price-project','client-existing',
 150,'USD','price-test','price-payment',decode('01','hex'));
insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
values('price-paid','account-primary','price-project','client-existing','price-payment',1,'USD',150);
insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,
 source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
values('price-paid-line','account-primary','price-paid',0,'USD','item','price-charge','price-item',3,
 'category-furnishings',150,'Frozen chair','{}');
select throws_ok($$select public.spike_read_item_price_edit('account-primary','price-project','price-item')$$,
 '22023','Item price review unavailable','Collected charge is not offered for editing');
update ledger_private.collected_invoices set sealed=true where id='price-paid';
select is((ledger_private.edit_uncollected_item_price((pg_temp.next_price_command('price-collected','300','300')::jsonb
 || jsonb_build_object('expectedPriceRevision','3','expectedChargeRevision','3'))::text)).error_code,
 'price_charge_collected','Collected occurrence cannot be repriced');
select is((select amount_minor_units from ledger_private.item_project_prices where item_id='price-item'),150::bigint,
 'Collected denial leaves current price intact');
select is((select signed_amount_minor_units from ledger_private.collected_invoice_lines where id='price-paid-line'),150::bigint,
 'Frozen price remains intact');
select is((select amount_minor_units from public.spike_transactions where id='price-payment'),150::bigint,
 'Client payment remains intact');
-- A different source writer must not bypass the same live-total boundary.
insert into ledger_private.expenses(id,account_id,project_id,category_id,vendor,expense_date,
 final_amount_minor_units,currency,notes,created_at,created_by_principal_id)
values('price-other-expense','account-primary','price-project','category-system','Vendor','2026-01-01',100,'USD','',now(),'principal-owner');
insert into ledger_private.fee_installments(id,account_id,project_id,category_id,label,amount_minor_units,currency,created_by_principal_id,created_at)
values('price-limit-fee','account-primary','price-project','category-furnishings','Limit',9223372036854775707,'USD','principal-owner',now());
insert into ledger_private.live_invoices(id,account_id,project_id,name,status,created_at,created_by_principal_id)
values('price-limit-invoice','account-primary','price-project','Limit invoice','created',now(),'principal-owner');
insert into ledger_private.live_invoice_memberships(account_id,invoice_id,source_kind,source_id,position)
values('account-primary','price-limit-invoice','expense','price-other-expense',0),
 ('account-primary','price-limit-invoice','fee_installment','price-limit-fee',1);
select is((ledger_private.edit_expense(jsonb_build_object('operationId','price-expense-overflow','accountId','account-primary',
 'actorPrincipalId','principal-owner','projectId','price-project','expenseId','price-other-expense',
 'contractVersion','expense-edit-v1','createdAtMs','1000','vendor','Vendor','date','2026-01-01',
 'amountMinorUnits','101','currency','USD','categoryId','category-system','notes','',
 'receiptLines','[]'::jsonb,'receiptAttachmentIds','[]'::jsonb,'expectedRevision','1')::text)).phase,
 'rejected','Expense writer cannot overflow a live Invoice either');
select throws_ok($$select ledger_private.edit_uncollected_item_price(
 (pg_temp.price_command('price-foreign-account')::jsonb||jsonb_build_object('accountId','account-other'))::text)$$,
 '42501','Item price access required','Foreign Account denied before mutation');
update public.spike_account_memberships set financial_access='none'
 where account_id='account-primary' and principal_id='principal-owner';
select throws_ok($$select public.spike_read_item_price_edit('account-primary','price-project','price-item')$$,
 '42501','Item price access required','Financial withdrawal denies review');
select throws_ok($$select ledger_private.edit_uncollected_item_price(pg_temp.price_command('price-op'))$$,
 '42501','Item price access required','Replay cannot disclose old result after financial access withdrawal');
update public.spike_account_memberships set financial_access='full',state='removed'
 where account_id='account-primary' and principal_id='principal-owner';
select throws_ok($$select public.spike_read_item_price_edit('account-primary','price-project','price-item')$$,
 '42501','Item price access required','Removed membership cannot review current prices');
select throws_ok($$select ledger_private.edit_uncollected_item_price(pg_temp.price_command('price-op'))$$,
 '42501','Item price access required','Removed membership cannot replay an accepted operation');
select is((select count(*) from public.spike_operation_results where operation_id='price-foreign-account'),0::bigint,
 'Unauthorized request creates no result in foreign Account');
select * from finish();
rollback;
