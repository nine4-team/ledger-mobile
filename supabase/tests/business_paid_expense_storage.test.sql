begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('expense-project','account-primary','client-existing','Expense project',now(),now(),1,1,'principal-owner');
create temp table payments_before as select count(*) as n from public.spike_transactions;
insert into ledger_private.expenses(id,account_id,project_id,category_id,vendor,expense_date,final_amount_minor_units,currency,notes,created_at,created_by_principal_id)
values ('expense-test','account-primary','expense-project','category-system','  Vendor  ','2024-02-29',9223372036854775807,'USD',E'Original\nnotes',now(),'principal-owner');
insert into ledger_private.expense_receipt_lines(account_id,expense_id,id,position,description,magnitude_minor_units,currency,effect)
values ('account-primary','expense-test','delivery',0,'Delivery',25,'USD','increase');
select is((select final_amount_minor_units from ledger_private.expenses where id='expense-test'),9223372036854775807::bigint,'Exact final amount, independent of optional receipt detail');
select is((select vendor from ledger_private.expenses where id='expense-test'),'  Vendor  ','Original source wording retained');
select is((select expense_date::text from ledger_private.expenses where id='expense-test'),'2024-02-29','Calendar date retained');
select is((select count(*) from public.spike_transactions),(select n from payments_before),'Expense storage creates no client payment');
select throws_ok($$update ledger_private.expenses set account_id='account-other' where id='expense-test'$$,'23503',null,'Project and category cannot cross Account');
select throws_ok($$update ledger_private.expenses set expense_date='infinity' where id='expense-test'$$,'23514',null,'Infinite date rejected');
select throws_ok($$update ledger_private.expense_receipt_lines set currency='EUR' where expense_id='expense-test'$$,'23503',null,'Receipt currency must match Expense');
select throws_ok($$update ledger_private.expense_receipt_lines set magnitude_minor_units=0 where expense_id='expense-test'$$,'23514',null,'Receipt line keeps existing positive magnitude contract');
select throws_ok($$insert into ledger_private.expense_receipt_lines select * from ledger_private.expense_receipt_lines where expense_id='expense-test'$$,'23505',null,'Duplicate line identity rejected');
select throws_ok($$insert into ledger_private.expense_receipt_attachments values ('account-primary','expense-test','missing-object',0)$$,'23503',null,'No fabricated attachment object');
select ok(relrowsecurity and relforcerowsecurity,'Expense RLS enabled and forced') from pg_class where oid='ledger_private.expenses'::regclass;
select ok(not has_table_privilege(r,t,'SELECT,INSERT,UPDATE,DELETE'),r||' has no direct access to '||t)
from unnest(array['anon','authenticated','service_role']) r
cross join unnest(array['ledger_private.expenses','ledger_private.expense_receipt_lines','ledger_private.expense_receipt_attachments']) t;
set local role authenticated;
select throws_ok($$select * from ledger_private.expenses$$,'42501',null,'Actual authenticated direct read denied until scoped API exists');
select throws_ok($$update ledger_private.expenses set notes='unauthorized'$$,'42501',null,'No direct mutation bypass');
reset role;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
create function pg_temp.expense_command(op text,expense text) returns text language sql as $$
  select jsonb_build_object('operationId',op,'accountId','account-primary','actorPrincipalId','principal-owner',
    'projectId','expense-project','expenseId',expense,'contractVersion','expense-create-v1','createdAtMs','1788523200000',
    'vendor','Business vendor','date','2024-02-29','amountMinorUnits','9007199254740993','currency','USD',
    'categoryId','category-system','notes','Source notes','receiptAttachmentIds','[]'::jsonb,
    'receiptLines',jsonb_build_array(jsonb_build_object('id','delivery','description','Delivery','magnitudeMinorUnits','25',
      'currency','USD','effect','increase','quantity',null)))::text
$$;
select is((ledger_private.create_expense(pg_temp.expense_command('expense-create-op','expense-created'))).phase,'applied','Create Expense and receipt detail atomically');
select is((ledger_private.create_expense(pg_temp.expense_command('expense-create-op','expense-created'))).phase,'applied','Exact retry returns saved result');
select is((select count(*) from ledger_private.expenses where id='expense-created'),1::bigint,'Retry does not duplicate Expense');
select is((select count(*) from ledger_private.expense_receipt_lines where expense_id='expense-created'),1::bigint,'Retry does not duplicate receipt details');
select is((select count(*) from public.spike_transactions),(select n from payments_before),'Creation command does not create payment');
select throws_ok($$select ledger_private.create_expense(pg_temp.expense_command('expense-create-op','changed-identity'))$$,'23505','Operation identity conflict','Retry identity cannot change payload');
select is((ledger_private.create_expense(jsonb_set(pg_temp.expense_command('expense-bad-media','expense-rejected')::jsonb,
  '{receiptAttachmentIds}','["missing-object"]')::text)).phase,'rejected','Missing media rejects complete creation');
select is((select count(*) from ledger_private.expenses where id='expense-rejected'),0::bigint,'Media rejection rolls back Expense');
select is((select count(*) from ledger_private.expense_receipt_lines where expense_id='expense-rejected'),0::bigint,'Media rejection rolls back receipt lines');
select is((ledger_private.create_expense(jsonb_set(pg_temp.expense_command('expense-bad-media','expense-rejected')::jsonb,
  '{receiptAttachmentIds}','["missing-object"]')::text)).phase,'rejected','Rejected replay remains rejected');
select is((ledger_private.create_expense(jsonb_set(pg_temp.expense_command('expense-bad-project','expense-other')::jsonb,
  '{projectId}','"other-project"')::text)).error_code,'expense_project_unavailable','Foreign Project cannot receive Expense');
select is((ledger_private.create_expense(jsonb_set(pg_temp.expense_command('expense-bad-line','expense-line-bad')::jsonb,
  '{receiptLines,0,currency}','"EUR"')::text)).phase,'rejected','Receipt currency mismatch rejects command');
select is((select count(*) from ledger_private.expenses where id='expense-line-bad'),0::bigint,'Bad receipt rolls back Expense');
select throws_ok($$select ledger_private.create_expense(jsonb_set(pg_temp.expense_command('expense-spoof','expense-spoofed')::jsonb,
  '{actorPrincipalId}','"principal-restricted"')::text)$$,'42501','Authenticated actor required','Actor spoof rejected');
set local role authenticated;
select is((public.spike_create_expense(pg_temp.expense_command('expense-api-op','expense-api'))).phase,'applied','Authenticated endpoint applies canonical command');
select is((public.spike_create_expense(pg_temp.expense_command('expense-api-op','expense-api'))).phase,'applied','Endpoint retry returns canonical result');
select ok(not has_function_privilege('anon','public.spike_create_expense(text)','EXECUTE'),'Anonymous create denied');
select ok(not has_function_privilege('service_role','public.spike_create_expense(text)','EXECUTE'),'No service-role creation bypass');
select ok(not (select prosecdef from pg_proc where oid='public.spike_create_expense(text)'::regprocedure),'Public create wrapper is security invoker');
select is(public.spike_read_expense('account-primary','expense-project','expense-test')->>'amountMinorUnits','9223372036854775807','Scoped API preserves Int64 as decimal text');
select lives_ok('set constraints all immediate','Deferred native creation checks work as authenticated without private table grants');
set constraints all deferred;
select is(public.spike_read_expense('account-primary','expense-project','expense-test')#>>'{receiptLines,0,description}','Delivery','Embedded receipt evidence read');
select is(public.spike_read_expense('account-primary','expense-project','expense-test')->'receiptAttachmentIds','[]'::jsonb,'Known empty attachments remain empty');
select throws_ok($$select public.spike_read_expense('account-other','expense-project','expense-test')$$,'42501','expense_not_available','Cross Account read denied');
select throws_ok($$select public.spike_read_expense('account-primary','other-project','expense-test')$$,'42501','expense_not_available','Cross Project read denied');
reset role;
update public.spike_account_memberships set financial_access='none' where account_id='account-primary' and principal_id='principal-owner';
select throws_ok($$select ledger_private.create_expense(pg_temp.expense_command('expense-no-access','expense-denied'))$$,'42501','Expense access required','Financial downgrade denies creation');
set local role authenticated;
select throws_ok($$select public.spike_read_expense('account-primary','expense-project','expense-test')$$,'42501','expense_not_available','Financial access downgrade denies Expense');
reset role;
update public.spike_account_memberships set financial_access='full',state='removed' where account_id='account-primary' and principal_id='principal-owner';
select throws_ok($$select ledger_private.create_expense(pg_temp.expense_command('expense-create-op','expense-created'))$$,'42501','Expense access required','Removed member cannot replay a formerly accepted command');
set local role authenticated;
select throws_ok($$select public.spike_read_expense('account-primary','expense-project','expense-test')$$,'42501','expense_not_available','Removed membership denies Expense');
reset role;
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select ledger_private.read_expense('account-primary','expense-project','expense-test')$$,'42501','expense_not_available','Missing authenticated identity denied even with privileged caller');
select ok(not has_function_privilege('anon','public.spike_read_expense(text,text,text)','EXECUTE'),'Anonymous cannot invoke endpoint');
select ok(not has_function_privilege('service_role','public.spike_read_expense(text,text,text)','EXECUTE'),'No service-role endpoint bypass');
select * from finish();
rollback;
