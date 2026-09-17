begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values('budget-project','account-primary','client-existing','Budget QA',now(),now(),1,1,'principal-owner');
insert into public.spike_project_category_allocations(id,account_id,project_id,category_id,allocation_minor_units,allocation_currency,created_by_principal_id,created_at,updated_at,created_at_ms,updated_at_ms)
values('budget-allocation','account-primary','budget-project','category-furnishings',1000,'USD','principal-owner',now(),now(),1,1);
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values('budget-item','account-primary','Chair','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id,ended_at,ended_by_principal_id)
values('budget-original','account-primary','budget-item','business_inventory','2024-01-01','principal-owner','2025-01-01','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
values('budget-placement','account-primary','budget-item','project','budget-project','2025-01-01','principal-owner');
insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,amount_minor_units,currency,created_at,created_by_principal_id)
values('budget-charge','account-primary','budget-project','budget-item','budget-placement','category-furnishings',100,'USD','2025-01-01','principal-owner');
insert into ledger_private.expenses(id,account_id,project_id,category_id,vendor,expense_date,final_amount_minor_units,currency,created_at,created_by_principal_id)
values('budget-expense','account-primary','budget-project','category-furnishings','Vendor','2026-09-17',50,'USD',now(),'principal-owner');
insert into ledger_private.fee_installments(id,account_id,project_id,category_id,label,amount_minor_units,currency,created_at,created_by_principal_id)
values('budget-fee','account-primary','budget-project','category-furnishings','Fee',25,'USD',now(),'principal-owner');
insert into public.spike_transactions(id,account_id,project_id,client_id,amount_minor_units,currency,origin,scope_kind,category_id)
values('budget-direct','account-primary','budget-project','client-existing',20,'USD','vendor_payment','project','category-furnishings');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select is(public.spike_read_project_budget('account-primary','budget-project','USD')->>'overallRecognizedMinorUnits','195','Mixed source total matches native fixture');
select is(public.spike_read_project_budget('account-primary','budget-project','USD')->>'overallPaidMinorUnits','20','Only direct amount paid initially');
select is(public.spike_read_project_budget('account-primary','budget-project','USD')->>'overallUnpaidMinorUnits','175','Item Expense Fee count once before invoicing');
select is(public.spike_read_project_budget('account-primary','budget-project','USD')->>'overallBudgetMinorUnits','1000','Enabled allocation preserved');
select is(public.spike_read_project_budget('account-primary','budget-project','USD')->>'isCompleteForProjectBudget','false','No full coverage claim');
select throws_ok($$select public.spike_read_project_budget('account-foreign','budget-project','USD')$$,'42501',null,'Foreign Account denied');
select throws_ok($$select public.spike_read_project_budget('account-primary','missing','USD')$$,'42501',null,'Unknown Project denied');
select throws_ok($$select public.spike_read_project_budget('account-primary','budget-project','EUR')$$,'22023',null,'Currency mismatch cannot become zero');
reset role;
insert into ledger_private.live_invoices(id,account_id,project_id,name,status,created_at,created_by_principal_id)
values('budget-invoice','account-primary','budget-project','Invoice','sent',now(),'principal-owner');
insert into ledger_private.live_invoice_memberships(account_id,invoice_id,source_kind,source_id,position)
values('account-primary','budget-invoice','item','budget-charge',0),
 ('account-primary','budget-invoice','expense','budget-expense',1),
 ('account-primary','budget-invoice','fee_installment','budget-fee',2);
select is(public.spike_read_project_budget('account-primary','budget-project','USD')->>'overallUnpaidMinorUnits','175','Sent membership does not remove demand');
select ledger_private.import_client_payment('budget-payment','account-primary','budget-project','client-existing',175,'USD','synthetic-budget','budget-invoice','\x01'::bytea);
insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
values('budget-invoice','account-primary','budget-project','client-existing','budget-payment',1,'USD',175);
insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
values('budget-line-item','account-primary','budget-invoice',0,'USD','item','budget-charge','budget-item',1,'category-furnishings',100,'Chair','{}'),
 ('budget-line-expense','account-primary','budget-invoice',1,'USD','expense','budget-expense',null,1,'category-furnishings',50,'Expense','{}'),
 ('budget-line-fee','account-primary','budget-invoice',2,'USD','fee_installment','budget-fee',null,1,'category-furnishings',25,'Fee','{}');
update ledger_private.collected_invoices set sealed=true where id='budget-invoice';
set local role authenticated;
select is(public.spike_read_project_budget('account-primary','budget-project','USD')->>'overallPaidMinorUnits','195','Collection moves sources to paid without counting payment twice');
select is(public.spike_read_project_budget('account-primary','budget-project','USD')->>'overallUnpaidMinorUnits','0','Collected sources no longer unpaid');
select is((public.spike_return_paid_items(jsonb_build_object('operationId','budget-return','accountId','account-primary',
 'actorPrincipalId','principal-owner','projectId','budget-project','contractVersion','return-paid-items-v1','createdAtMs','1788523200000',
 'items',jsonb_build_array(jsonb_build_object('itemId','budget-item','placementId','budget-placement','chargeId','budget-charge',
 'paidInvoiceLineId','budget-line-item','inventoryPlacementId','budget-return-placement','returnOccurrenceId','budget-return-occurrence',
 'creditId','budget-credit')))::text)).phase,'applied','Return creates exact credit');
select is(public.spike_read_project_budget('account-primary','budget-project','USD')->>'overallPaidMinorUnits','195','Return retains original paid history');
select is(public.spike_read_project_budget('account-primary','budget-project','USD')->>'overallUnpaidMinorUnits','-100','Return credit is signed unpaid');
select is(public.spike_read_project_budget('account-primary','budget-project','USD')->>'overallRecognizedMinorUnits','95','Return reduces total once');
reset role;
savepoint restricted;
update public.spike_project_category_allocations set allocation_minor_units=null,allocation_currency=null where id='budget-allocation';
select is(public.spike_read_project_budget('account-primary','budget-project','USD')->>'overallBudgetMinorUnits','0','Enabled without allocation does not invent budget');
select is((select value->>'enabled' from jsonb_array_elements(public.spike_read_project_budget('account-primary','budget-project','USD')->'categories')
 where value->>'id'='category-furnishings'),'true','Null allocation remains enabled');
rollback to restricted;
delete from public.spike_project_category_allocations where id='budget-allocation';
select is((select value->>'enabled' from jsonb_array_elements(public.spike_read_project_budget('account-primary','budget-project','USD')->'categories')
 where value->>'id'='category-furnishings'),'false','Absent allocation differs from enabled-null');
select is(public.spike_read_project_budget('account-primary','budget-project','USD')->>'overallRecognizedMinorUnits','95','Disabled display category does not erase recognized value');
rollback to restricted;
update public.spike_budget_categories set excludes_from_overall_budget=true where id='category-furnishings';
select is(public.spike_read_project_budget('account-primary','budget-project','USD')->>'overallRecognizedMinorUnits','0','Explicit category exclusion affects overall only');
select is((select value->>'recognizedMinorUnits' from jsonb_array_elements(public.spike_read_project_budget('account-primary','budget-project','USD')->'categories')
 where value->>'id'='category-furnishings'),'95','Excluded category retains its own accounting');
rollback to restricted;
insert into public.spike_transactions(id,account_id,project_id,client_id,amount_minor_units,currency,origin,scope_kind,category_id,type)
values('budget-direct-return','account-primary','budget-project','client-existing',5,'USD','vendor_payment','project','category-furnishings','return');
select is(public.spike_read_project_budget('account-primary','budget-project','USD')->>'overallRecognizedMinorUnits','90','Direct refund has negative contribution');
rollback to restricted;
insert into public.spike_transactions(id,account_id,project_id,client_id,amount_minor_units,currency,origin,scope_kind,category_id)
values('budget-overflow','account-primary','budget-project','client-existing',9223372036854775807,'USD','vendor_payment','project','category-furnishings');
select throws_ok($$select public.spike_read_project_budget('account-primary','budget-project','USD')$$,'22003',null,'Int64 overflow rejects instead of rounding');
rollback to restricted;
update public.spike_account_memberships set financial_access='limited' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select throws_ok($$select public.spike_read_project_budget('account-primary','budget-project','USD')$$,'42501',null,'Limited financial access denied');
reset role;
rollback to restricted;
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select throws_ok($$select public.spike_read_project_budget('account-primary','budget-project','USD')$$,'42501',null,'Removed membership denied');
reset role;
rollback to restricted;
set local role anon;
select throws_ok($$select public.spike_read_project_budget('account-primary','budget-project','USD')$$,'42501',null,'Anonymous role cannot call endpoint');
reset role;
select is((select provolatile::text from pg_proc where oid='ledger_private.read_project_budget(text,text,text)'::regprocedure),'s','Read has stable snapshot semantics');
select * from finish();
rollback;
