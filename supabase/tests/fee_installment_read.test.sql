begin;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values('fee-read-project','account-primary','client-existing','Fee read',now(),now(),1,1,'principal-owner');
insert into ledger_private.fee_installments(id,account_id,project_id,category_id,label,amount_minor_units,currency,created_at,created_by_principal_id)
values('fee-read','account-primary','fee-read-project','category-design-fee','Design fee',9007199254740993,'USD',now(),'principal-owner');
select ok(has_function_privilege('authenticated','public.spike_read_project_fees(text,text)','EXECUTE')
  and not has_function_privilege('anon','public.spike_read_project_fees(text,text)','EXECUTE')
  and not has_function_privilege('service_role','public.spike_read_project_fees(text,text)','EXECUTE'),'Read endpoint is authenticated only');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select ledger_private.read_project_fees('account-primary','fee-read-project')$$,'42501','fees_not_available','Anonymous denied');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select is(public.spike_read_project_fees('account-primary','fee-read-project')->'fees'->0->>'amountMinorUnits','9007199254740993','Exact decimal amount');
select is(public.spike_read_project_fees('account-primary','fee-read-project')->'fees'->0->>'status','available','Available demand');
select is(public.spike_read_project_fees('account-primary','fee-read-project')->>'canCreate','true','Active creation eligibility');
select throws_ok($$select public.spike_read_project_fees('account-other','fee-read-project')$$,'42501','fees_not_available','Cross-account denied');
reset role;
insert into ledger_private.live_invoices(id,account_id,project_id,name,status,created_at,created_by_principal_id)
values('fee-read-invoice','account-primary','fee-read-project','Phase 1','created',now(),'principal-owner');
insert into ledger_private.live_invoice_memberships(account_id,invoice_id,source_kind,source_id,position)
values('account-primary','fee-read-invoice','fee_installment','fee-read',0);
select is(public.spike_read_project_fees('account-primary','fee-read-project')->'fees'->0->>'status','created','Created membership');
update ledger_private.live_invoices set status='sent' where id='fee-read-invoice';
select is(public.spike_read_project_fees('account-primary','fee-read-project')->'fees'->0->>'status','sent','Sent membership');
update public.spike_projects set lifecycle='archived',revision=revision+1 where id='fee-read-project';
select is(public.spike_read_project_fees('account-primary','fee-read-project')->>'canCreate','false','Archive disables creation');
select is(jsonb_array_length(public.spike_read_project_fees('account-primary','fee-read-project')->'fees'),1,'Archive retains Fee history');
update ledger_private.live_invoices set status='paid' where id='fee-read-invoice';
select throws_ok($$select public.spike_read_project_fees('account-primary','fee-read-project')$$,'55000','fee_history_incomplete','Missing frozen evidence is not fake paid history');
select ledger_private.import_client_payment('fee-read-payment','account-primary','fee-read-project','client-existing',
  9007199254740993,'USD','synthetic-fee-read','fee-read-payment','\x01'::bytea);
insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units,display_metadata)
values('fee-read-invoice','account-primary','fee-read-project','client-existing','fee-read-payment',1,'USD',9007199254740993,'{"invoiceNumber":"Original invoice"}');
insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,
  source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
values('fee-read-line','account-primary','fee-read-invoice',0,'USD','fee_installment','fee-read',1,'category-design-fee',9007199254740993,'Frozen fee label','{}');
update ledger_private.collected_invoices set sealed=true where id='fee-read-invoice';
update public.spike_budget_categories set display_name='Renamed category',revision=revision+1 where id='category-design-fee';
select is(public.spike_read_project_fees('account-primary','fee-read-project')->'fees'->0->>'status','paid','Frozen membership is paid');
select is(public.spike_read_project_fees('account-primary','fee-read-project')->'fees'->0->>'label','Frozen fee label','Frozen label wins');
select is(public.spike_read_project_fees('account-primary','fee-read-project')->'fees'->0->>'categoryName',null::text,'Current category rename is not paid history');
select is(public.spike_read_project_fees('account-primary','fee-read-project')->'fees'->0->>'invoiceName','Original invoice','Frozen Invoice name retained');
update public.spike_account_memberships set financial_access='none' where account_id='account-primary' and principal_id='principal-owner';
select throws_ok($$select public.spike_read_project_fees('account-primary','fee-read-project')$$,'42501','fees_not_available','Financial withdrawal denied');
select * from finish();
rollback;
