begin;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values('invoice-membership-project','account-primary','client-existing','Membership test',now(),now(),1,1,'principal-owner');
insert into ledger_private.live_invoices(id,account_id,project_id,created_at,created_by_principal_id)
values('live-one','account-primary','invoice-membership-project',now(),'principal-owner'),
      ('live-two','account-primary','invoice-membership-project',now(),'principal-owner');
select is((select status from ledger_private.live_invoices where id='live-one'),'created','Creation is not sending or collection');
select ok(not has_table_privilege('authenticated','ledger_private.live_invoices','SELECT,INSERT,UPDATE,DELETE'),
  'No direct member access to Invoice storage');
select ok(not has_table_privilege('anon','ledger_private.live_invoice_memberships','SELECT,INSERT,UPDATE,DELETE'),
  'No anonymous membership access');
select ok(not has_table_privilege('service_role','ledger_private.live_invoice_memberships','INSERT,UPDATE,DELETE'),
  'No implicit service membership writer');
insert into ledger_private.live_invoice_memberships(account_id,invoice_id,source_kind,source_id,position)
values('account-primary','live-one','expense','expense-source',0);
select throws_ok($$insert into ledger_private.live_invoice_memberships(account_id,invoice_id,source_kind,source_id,position)
  values('account-primary','live-two','expense','expense-source',0)$$,'23505',null,'One active Invoice per source');
select throws_ok($$insert into ledger_private.live_invoice_memberships(account_id,invoice_id,source_kind,source_id,position)
  values('account-other','live-one','expense','other-source',0)$$,'23503',null,'Membership cannot cross Accounts');
select throws_ok($$insert into ledger_private.live_invoice_memberships(account_id,invoice_id,source_kind,source_id,position)
  values('account-primary','live-one','expense','other-source',0)$$,'23505',null,'Active line positions are unique');
insert into ledger_private.live_invoice_memberships(account_id,invoice_id,source_kind,source_id,position)
values('account-primary','live-one','item','sale-occurrence-one',1),
      ('account-primary','live-one','item','sale-occurrence-two',2),
      ('account-primary','live-one','fee_installment','fee-source',3);
select is((select count(*) from ledger_private.live_invoice_memberships where invoice_id='live-one'),4::bigint,
  'Repeated physical-item sales use distinct occurrence identities; Fee identity is representable');
-- Operator-only structural test, not an authorized cancellation implementation.
update ledger_private.live_invoice_memberships set released_at=now()
where invoice_id='live-one' and source_kind='expense';
insert into ledger_private.live_invoice_memberships(account_id,invoice_id,source_kind,source_id,position)
values('account-primary','live-two','expense','expense-source',0);
select is((select count(*) from ledger_private.live_invoice_memberships where source_id='expense-source'),2::bigint,
  'Releasing membership preserves its prior identity');
insert into ledger_private.expenses(id,account_id,project_id,category_id,vendor,expense_date,final_amount_minor_units,currency,created_at,created_by_principal_id)
values('invoice-expense','account-primary','invoice-membership-project','category-system','Vendor','2026-09-15',9007199254740993,'USD',now(),'principal-owner');
create function pg_temp.invoice_command(op text, invoice text default 'created-invoice', source text default 'invoice-expense')
returns text language sql as $$ select jsonb_build_object(
  'operationId',op,'accountId','account-primary','actorPrincipalId','principal-owner',
  'projectId','invoice-membership-project','clientId','client-existing','invoiceId',invoice,
  'contractVersion','invoice-create-v1','createdAtMs','1000','name','Phase 1','notes','Original notes',
  'sources',jsonb_build_array(jsonb_build_object('kind','expense','sourceId',source,'expectedRevision','1',
    'amountMinorUnits','9007199254740993','currency','USD')))::text $$;
select ok(has_function_privilege('authenticated','public.spike_create_invoice(text)','EXECUTE')
  and not has_function_privilege('anon','public.spike_create_invoice(text)','EXECUTE')
  and not has_function_privilege('service_role','public.spike_create_invoice(text)','EXECUTE'),
  'Creation endpoint is authenticated only, without direct table writes');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select ledger_private.create_live_invoice(pg_temp.invoice_command('unauth'))$$,
  '42501','Authenticated actor required','No unauthenticated writes');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select is((public.spike_create_invoice(pg_temp.invoice_command('create-invoice'))).phase,'applied','Exact Expense source creates Invoice through authenticated endpoint');
select is((public.spike_create_invoice(pg_temp.invoice_command('create-invoice'))).phase,'applied','Identical replay applies once');
reset role;
select is((select count(*) from ledger_private.live_invoice_memberships where invoice_id='created-invoice'),1::bigint,'Replay does not duplicate membership');
select is((select final_amount_minor_units from ledger_private.expenses where id='invoice-expense'),9007199254740993::bigint,'Creation preserves exact source money');
select is((select count(*) from public.spike_transactions where project_id='invoice-membership-project'),0::bigint,'Invoice demand creates no payment');
set local role authenticated;
select is(public.spike_read_live_invoice('account-primary','invoice-membership-project','created-invoice')->>'totalMinorUnits',
  '9007199254740993','Live read retains exact amount beyond JS integer precision');
select throws_ok($$select public.spike_read_live_invoice('account-other','invoice-membership-project','created-invoice')$$,
  '42501','invoice_not_available','Cross-account Invoice read denied');
reset role;
select throws_ok($$select ledger_private.create_live_invoice(pg_temp.invoice_command('create-invoice','other-invoice'))$$,
  '23505','Operation identity conflict','Changed replay cannot overwrite Invoice');
select is((ledger_private.create_live_invoice(pg_temp.invoice_command('competing','other-invoice'))).error_code,
  'invoice_source_reserved','Second Invoice cannot reserve same source');
select is((select count(*) from ledger_private.live_invoices where id='other-invoice'),0::bigint,'Rejected creation leaves no header');
select is((ledger_private.create_live_invoice(pg_temp.invoice_command('missing','missing-invoice','missing-source'))).error_code,
  'invoice_source_unavailable','Missing source cannot become demand');
select is((ledger_private.create_live_invoice((pg_temp.invoice_command('stale')::jsonb ||
  jsonb_build_object('sources',jsonb_build_array(jsonb_build_object('kind','expense','sourceId','invoice-expense',
  'expectedRevision','2','amountMinorUnits','9007199254740993','currency','USD'))))::text)).error_code,
  'invoice_source_changed','Stale review rejected before membership');
select is((ledger_private.create_live_invoice((pg_temp.invoice_command('fee')::jsonb ||
  jsonb_build_object('sources',jsonb_build_array(jsonb_build_object('kind','fee_installment','sourceId','fee',
  'expectedRevision','1','amountMinorUnits','100','currency','USD'))))::text)).error_code,
  'invoice_source_unavailable','Missing Fee source cannot be dropped or substituted');
select is((ledger_private.create_live_invoice((pg_temp.invoice_command('wrong-client')::jsonb ||
  '{"clientId":"wrong-client"}'::jsonb)::text)).error_code,'invoice_project_unavailable','Client must match current Project');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values('invoice-item','account-primary','Chair','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
values('invoice-placement','account-primary','invoice-item','project','invoice-membership-project','2026-01-01','principal-owner');
insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,
 amount_minor_units,currency,created_at,created_by_principal_id)
values('invoice-charge','account-primary','invoice-membership-project','invoice-item','invoice-placement',
 'category-furnishings',12345,'USD','2026-01-01','principal-owner');
insert into ledger_private.expenses(id,account_id,project_id,category_id,vendor,expense_date,final_amount_minor_units,currency,created_at,created_by_principal_id)
values('mixed-expense','account-primary','invoice-membership-project','category-system','Delivery','2026-09-15',55,'USD',now(),'principal-owner');
create function pg_temp.mixed_invoice(op text, amount text default '12345', item_source text default 'invoice-charge') returns text language sql as $$
select (pg_temp.invoice_command(op,'mixed-invoice')::jsonb || jsonb_build_object('sources',jsonb_build_array(
  jsonb_build_object('kind','item','sourceId',item_source,'expectedRevision','1','amountMinorUnits',amount,'currency','USD'),
  jsonb_build_object('kind','expense','sourceId','mixed-expense','expectedRevision','1','amountMinorUnits','55','currency','USD'))))::text $$;
select is((ledger_private.create_live_invoice(pg_temp.mixed_invoice('item-wrong-amount','12346'))).error_code,
  'invoice_source_changed','Item charge must match reviewed amount');
select is((select count(*) from ledger_private.live_invoice_memberships where source_id='mixed-expense'),0::bigint,
  'Failure on Item leaves no partial Expense membership');
select is((ledger_private.create_live_invoice(pg_temp.mixed_invoice('physical-id','12345','invoice-item'))).error_code,
  'invoice_source_unavailable','Physical Item ID cannot replace occurrence ID');
select is((ledger_private.create_live_invoice(pg_temp.mixed_invoice('mixed-create'))).phase,'applied',
  'Mixed Item and Expense Invoice creates atomically');
select is((select string_agg(source_kind,',' order by position) from ledger_private.live_invoice_memberships where invoice_id='mixed-invoice'),
  'item,expense','Lock ordering does not reorder visible lines');
select is((select scope_kind||':'||project_id from public.spike_item_placements where id='invoice-placement'),
  'project:invoice-membership-project','Invoice creation does not relocate Item');
select is(public.spike_read_live_invoice('account-primary','invoice-membership-project','mixed-invoice')->>'totalMinorUnits',
  '12400','Live mixed total resolves both sources');
update ledger_private.expenses set final_amount_minor_units=100,vendor='Updated delivery',revision=revision+1 where id='mixed-expense';
select is(public.spike_read_live_invoice('account-primary','invoice-membership-project','mixed-invoice')->>'totalMinorUnits',
  '12445','Source edit changes live Invoice total without copying money');
select is(public.spike_read_live_invoice('account-primary','invoice-membership-project','mixed-invoice')->'lines'->1->>'description',
  'Updated delivery','Source description remains live');
update ledger_private.item_charge_occurrences set revision=2,withdrawn_at='2026-02-01',withdrawn_by_principal_id='principal-owner'
where id='invoice-charge';
select throws_ok($$select public.spike_read_live_invoice('account-primary','invoice-membership-project','mixed-invoice')$$,
  '55000','invoice_sources_incomplete','Withdrawn Item cannot silently disappear from live total');
select is((ledger_private.create_live_invoice((pg_temp.mixed_invoice('withdrawn-charge')::jsonb ||
  jsonb_build_object('sources',jsonb_build_array(pg_temp.mixed_invoice('withdrawn-charge')::jsonb->'sources'->0)))::text)).error_code,
  'invoice_source_unavailable','Withdrawn source is not eligible for new membership');
insert into ledger_private.fee_installments(id,account_id,project_id,category_id,label,amount_minor_units,currency,created_at,created_by_principal_id)
values('planned-fee','account-primary','invoice-membership-project','category-design-fee','Design fee 1 of 3',250000,'USD',now(),'principal-owner');
create function pg_temp.fee_invoice(op text) returns text language sql as $$
select (pg_temp.invoice_command(op,'fee-invoice')::jsonb || jsonb_build_object('sources',jsonb_build_array(
  jsonb_build_object('kind','fee_installment','sourceId','planned-fee','expectedRevision','1',
    'amountMinorUnits','250000','currency','USD'))))::text $$;
select is((ledger_private.create_live_invoice(pg_temp.fee_invoice('fee-create'))).phase,'applied','Fee source creates live demand');
select is((select source_kind from ledger_private.live_invoice_memberships where invoice_id='fee-invoice'),
  'fee_installment','Fee is not converted to Expense or Transaction');
select is(public.spike_read_live_invoice('account-primary','invoice-membership-project','fee-invoice')->>'totalMinorUnits',
  '250000','Live Fee reads its source amount');
select ok(not has_table_privilege('authenticated','ledger_private.fee_installments','SELECT,INSERT,UPDATE,DELETE'),
  'Fee storage has no unvalidated direct client access');
select throws_ok($$update ledger_private.fee_installments set amount_minor_units=250001 where id='planned-fee'$$,
  '23514','Fee edit requires original identity and next revision','Fee edits require a new revision');
select ledger_private.import_client_payment('fee-payment','account-primary','invoice-membership-project','client-existing',
  250000,'USD','synthetic-fee-test','fee-payment',decode('01','hex'));
insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
values('fee-invoice','account-primary','invoice-membership-project','client-existing','fee-payment',1,'USD',250000);
select throws_ok($$insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,
 source_kind,source_id,source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
 values('fee-line','account-primary','fee-invoice',0,'USD','fee_installment','planned-fee',2,'category-design-fee',250000,'Frozen fee','{}')$$,
 '23514','Collected Fee source changed','Cannot freeze stale Fee revision');
insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,
 source_kind,source_id,source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
values('fee-line','account-primary','fee-invoice',0,'USD','fee_installment','planned-fee',1,'category-design-fee',250000,'Frozen fee','{}');
update ledger_private.collected_invoices set sealed=true where id='fee-invoice';
select throws_ok($$select public.spike_read_live_invoice('account-primary','invoice-membership-project','fee-invoice')$$,
  '55000','invoice_sources_incomplete','Collected source cannot be reported as live demand');
select throws_ok($$update ledger_private.fee_installments set amount_minor_units=250001,revision=2 where id='planned-fee'$$,
 '23514','Collected Fee is immutable','Collection locks Fee amount');
select throws_ok($$delete from ledger_private.fee_installments where id='planned-fee'$$,
 '23514','Collected Fee is immutable','Collection retains Fee identity');
select is((ledger_private.create_live_invoice(pg_temp.fee_invoice('fee-rebill'))).error_code,
 'invoice_source_collected','Collected Fee cannot be invoiced again');
update public.spike_account_memberships set financial_access='none' where account_id='account-primary' and principal_id='principal-owner';
select throws_ok($$select ledger_private.create_live_invoice(pg_temp.invoice_command('create-invoice'))$$,
  '42501','Invoice access required','Even replay requires current access');
set local role authenticated;
select throws_ok($$select public.spike_read_live_invoice('account-primary','invoice-membership-project','created-invoice')$$,
  '42501','invoice_not_available','Financial withdrawal denies complete Invoice read');
reset role;
select ok(not has_function_privilege('anon','public.spike_read_live_invoice(text,text,text)','EXECUTE'),
  'Anonymous role cannot call read endpoint');
select * from finish();
rollback;
