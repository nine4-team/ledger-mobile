begin;
select no_plan();
insert into public.spike_transactions(id,account_id,amount_minor_units,currency,type,origin,scope_kind,category_id,
  source,transaction_date,created_at_ms,notes,payment_method,has_email_receipt,legacy_subtotal_minor_units,legacy_tax_rate_pct)
values ('detail-inventory','account-primary',9007199254740993,'USD','return','vendor_payment','business_inventory','category-system',
  'Café vendor','2024-02-29',1709251200123,E'First line\nSecond line','Company card',false,
  9007199254740993,8.12345678901234567890);
insert into public.spike_transactions(id,account_id,amount_minor_units,currency,origin,scope_kind,category_id)
values ('detail-unknown','account-primary',100,'USD','vendor_payment','business_inventory','category-system');
insert into public.spike_budget_categories(id,account_id,display_name,kind,visibility_class,presentation_order,lifecycle,is_system,excludes_from_overall_budget,created_at_ms,updated_at_ms)
values ('detail-fee','account-primary','Fee','fee','company_financial',50,'active',false,false,1,1);
insert into public.spike_transactions(id,account_id,amount_minor_units,currency,origin,scope_kind,category_id,notes)
values ('detail-private','account-primary',1234,'USD','vendor_payment','business_inventory','detail-fee','Private financial notes');

select ok(not has_function_privilege('anon','public.spike_read_transaction_detail(text,text)','EXECUTE'),'no anonymous RPC grant');
select ok(not has_function_privilege('service_role','public.spike_read_transaction_detail(text,text)','EXECUTE'),'no service-role RPC grant');
select ok(not has_any_column_privilege('authenticated','public.spike_transactions','UPDATE'),'metadata introduces no update permission');
select ok(not has_column_privilege('anon','public.spike_transactions','notes','SELECT'),'no anonymous metadata grant');
select ok(not has_column_privilege('service_role','public.spike_transactions','notes','SELECT'),'no service-role metadata bypass');
select throws_ok($$update public.spike_transactions set transaction_date='infinity' where id='detail-inventory'$$,
  '23514',null,'non-calendar dates cannot enter the display contract');
select throws_ok($$update public.spike_transactions set legacy_tax_rate_pct='NaN' where id='detail-inventory'$$,
  '23514',null,'legacy numeric metadata must be finite');
select throws_ok($$update public.spike_transactions set legacy_tax_rate_pct='Infinity' where id='detail-inventory'$$,
  '23514',null,'legacy tax cannot be infinite');
select ok(not has_column_privilege('anon','public.spike_transactions','legacy_tax_rate_pct','SELECT'),'no anonymous tax read');
select ok(not has_column_privilege('service_role','public.spike_transactions','legacy_subtotal_minor_units','SELECT'),'no service-role subtotal bypass');

set local role authenticated;
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select public.spike_read_transaction_detail('account-primary','detail-inventory')$$,
  '28000','authentication required','identity required');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',true);
select throws_ok($$select public.spike_read_transaction_detail('account-primary','detail-inventory')$$,
  '42501','account_not_authorized','foreign Account denied');
select is((select count(*) from public.spike_transactions where id='detail-inventory'),0::bigint,'direct read cannot cross Account');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
select throws_ok($$select public.spike_read_transaction_detail('account-primary','detail-private')$$,
  '42501','transaction_not_available','restricted financial detail denied');
select throws_ok($$select public.spike_read_transaction_detail('account-primary','not-present')$$,
  '42501','transaction_not_available','missing and hidden identities have the same response');
select is((select count(notes) from public.spike_transactions where id='detail-private'),0::bigint,'private notes cannot bypass RLS');
select is(public.spike_read_transaction_detail('account-primary','detail-inventory')->>'principalId','principal-restricted','snapshot identifies caller');
select is(public.spike_read_transaction_detail('account-primary','detail-inventory')->>'amountMinorUnits','9007199254740993','exact amount exceeds JavaScript safe integer without rounding');
select is(public.spike_read_transaction_detail('account-primary','detail-inventory')->>'type','return','canonical Return retained');
select is(public.spike_read_transaction_detail('account-primary','detail-inventory')->>'scopeKind','business_inventory','Inventory has its own scope');
select is(public.spike_read_transaction_detail('account-primary','detail-inventory')->'projectId','null'::jsonb,'no synthetic Project');
select is(public.spike_read_transaction_detail('account-primary','detail-inventory')->>'source','Café vendor','source wording retained');
select is(public.spike_read_transaction_detail('account-primary','detail-inventory')->>'transactionDate','2024-02-29','calendar date retained');
select is(public.spike_read_transaction_detail('account-primary','detail-inventory')->>'createdAtMilliseconds','1709251200123','creation time exact and separate from Transaction date');
select is(public.spike_read_transaction_detail('account-primary','detail-inventory')->>'notes',E'First line\nSecond line','notes retain newlines');
select is(public.spike_read_transaction_detail('account-primary','detail-inventory')->>'paymentMethod','Company card','payment method retained');
select is(public.spike_read_transaction_detail('account-primary','detail-inventory')->'hasEmailReceipt','false'::jsonb,'known false is not unknown');
select is(public.spike_read_transaction_detail('account-primary','detail-inventory')->>'legacySubtotalMinorUnits','9007199254740993','source subtotal retains exact cents');
select is(public.spike_read_transaction_detail('account-primary','detail-inventory')->>'legacyTaxRatePct','8.12345678901234567890','source rate retains decimal precision');
select is(public.spike_read_transaction_detail('account-primary','detail-unknown')->'legacySubtotalMinorUnits','null'::jsonb,'missing subtotal is not inferred');
select is(public.spike_read_transaction_detail('account-primary','detail-unknown')->'legacyTaxRatePct','null'::jsonb,'missing tax rate is not inferred');
select is((select count(legacy_subtotal_minor_units) from public.spike_transactions where id='detail-private'),0::bigint,'restricted metadata remains hidden');
select throws_ok($$update public.spike_transactions set legacy_subtotal_minor_units=0 where id='detail-inventory'$$,
  '42501',null,'metadata does not grant writes');
select is(public.spike_read_transaction_detail('account-primary','detail-unknown')->'hasEmailReceipt','null'::jsonb,'unknown receipt evidence remains unknown');
select is(public.spike_read_transaction_detail('account-primary','detail-unknown')->'transactionDate','null'::jsonb,'no invented Transaction date');
select is(public.spike_read_transaction_detail('account-primary','detail-unknown')->'createdAtMilliseconds','null'::jsonb,'no invented creation date');
select throws_ok($$update public.spike_transactions set notes='Unauthorized edit' where id='detail-inventory'$$,
  '42501',null,'read access does not imply edit permission');
reset role;
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-restricted';
set local role authenticated;
select throws_ok($$select public.spike_read_transaction_detail('account-primary','detail-inventory')$$,
  '42501','account_not_authorized','membership removal revokes detail');
reset role;
select * from finish();
rollback;
