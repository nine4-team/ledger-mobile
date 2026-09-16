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
update public.spike_account_memberships set state='active',financial_access='full'
  where account_id='account-primary' and principal_id='principal-owner';
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
create function pg_temp.edit_command(op text,revision text default '1') returns text language sql as $$
  select (pg_temp.expense_command(op,'expense-created')::jsonb || jsonb_build_object(
    'contractVersion','expense-edit-v1','expectedRevision',revision,'notes','Edited notes'))::text
$$;
select is((ledger_private.edit_expense(pg_temp.edit_command('expense-edit-op'))).phase,'applied','Expense edit applies');
select is((select revision from ledger_private.expenses where id='expense-created'),2::bigint,'Revision advances once');
select is((select notes from ledger_private.expenses where id='expense-created'),'Edited notes','Entry edit persisted');
select is((ledger_private.edit_expense(pg_temp.edit_command('expense-edit-op'))).phase,'applied','Exact edit replay returns success');
select is((select revision from ledger_private.expenses where id='expense-created'),2::bigint,'Replay cannot apply twice');
select throws_ok($$select ledger_private.edit_expense(pg_temp.edit_command('expense-edit-op','2'))$$,
  '23505','Operation identity conflict','Changed retry is refused');
select is((ledger_private.edit_expense(pg_temp.edit_command('expense-edit-stale'))).error_code,
  'expense_revision_conflict','Stale edit receives durable rejection');
select is((ledger_private.edit_expense((pg_temp.edit_command('expense-edit-media','2')::jsonb ||
  '{"receiptAttachmentIds":["unverified"]}'::jsonb)::text)).error_code,
  'expense_receipt_invalid','Bare receipt IDs cannot bypass verified media');
select is((ledger_private.edit_expense((pg_temp.edit_command('expense-edit-invalid','2')::jsonb ||
  '{"date":"2025-02-29"}'::jsonb)::text)).phase,'rejected','Invalid date rejects atomically');
select is((select revision from ledger_private.expenses where id='expense-created'),2::bigint,'Rejected edits preserve revision');
select throws_ok($$select ledger_private.edit_expense((pg_temp.edit_command('edit-other-actor','2')::jsonb ||
  '{"actorPrincipalId":"principal-other"}'::jsonb)::text)$$,'42501','Authenticated actor required','Actor cannot be forged');
select throws_ok($$select ledger_private.edit_expense((pg_temp.edit_command('edit-other-account','2')::jsonb ||
  '{"accountId":"account-other"}'::jsonb)::text)$$,'42501','Expense access required','Cross-account command denied');
select is((ledger_private.edit_expense((pg_temp.edit_command('edit-other-project','2')::jsonb ||
  '{"projectId":"missing-project"}'::jsonb)::text)).error_code,'expense_project_unavailable','Unknown Project cannot edit source');
select is((ledger_private.edit_expense((pg_temp.edit_command('edit-other-source','2')::jsonb ||
  '{"expenseId":"missing-expense"}'::jsonb)::text)).error_code,'expense_unavailable','Missing Expense is not created');
select is((ledger_private.edit_expense((pg_temp.edit_command('edit-currency','2')::jsonb ||
  '{"currency":"EUR"}'::jsonb)::text)).error_code,'expense_integrity_conflict','Currency cannot be rewritten');
select is((ledger_private.edit_expense((pg_temp.edit_command('edit-category','2')::jsonb ||
  '{"categoryId":"missing-category"}'::jsonb)::text)).error_code,'expense_category_unavailable','Unavailable category denied');
select throws_ok($$select ledger_private.edit_expense((pg_temp.edit_command('edit-extra','2')::jsonb ||
  '{"unexpected":"value"}'::jsonb)::text)$$,'22023','Invalid Expense edit command','Unknown fields rejected');
select throws_ok($$select ledger_private.edit_expense(pg_temp.edit_command('edit-zero','0'))$$,
  '22023','Invalid Expense edit command','Invalid revision rejected');
select is((ledger_private.edit_expense((pg_temp.edit_command('edit-bad-lines','2')::jsonb ||
  '{"receiptLines":[{"id":"invalid"}]}'::jsonb)::text)).error_code,'expense_receipt_invalid','Malformed lines rejected before mutation');
select is((select count(*) from ledger_private.expense_receipt_lines where expense_id='expense-created'),1::bigint,
  'Rejected line replacement preserves existing lines');
select public.spike_begin_expense_attachment_upload('edit-receipt','account-primary','expense-project','expense-created',repeat('c',64),12,'application/pdf','New.pdf');
create function pg_temp.add_receipt_command(op text, revision text default '2') returns text language sql as $$
  select (pg_temp.edit_command(op,revision)::jsonb || '{"receiptAttachmentIds":["edit-receipt"]}'::jsonb)::text
$$;
select is((ledger_private.edit_expense(pg_temp.add_receipt_command('edit-unpublished'))).error_code,
  'expense_receipt_invalid','Reservation without verified object cannot be attached');
insert into public.item_image_objects(id,account_id,content_sha256,byte_count,media_type,storage_path)
values('edit-receipt','account-primary',repeat('c',64),12,'application/pdf','accounts/account-primary/attachments/edit-receipt/'||repeat('c',64));
update ledger_private.expense_attachment_uploads set expense_id='different-expense' where id='edit-receipt';
select is((ledger_private.edit_expense(pg_temp.add_receipt_command('edit-wrong-receipt-parent'))).error_code,
  'expense_receipt_invalid','Verified object reserved for another Expense cannot attach');
update ledger_private.expense_attachment_uploads set expense_id='expense-created',principal_id='principal-restricted' where id='edit-receipt';
select is((ledger_private.edit_expense(pg_temp.add_receipt_command('edit-wrong-receipt-actor'))).error_code,
  'expense_receipt_invalid','Another actor pending upload cannot attach');
update ledger_private.expense_attachment_uploads set principal_id='principal-owner' where id='edit-receipt';
select is((select revision from ledger_private.expenses where id='expense-created'),2::bigint,'Wrong-parent/actor rejection preserves source');
select is((ledger_private.edit_expense(pg_temp.add_receipt_command('edit-add-receipt'))).phase,'applied','Verified same-parent receipt addition applies');
select is((ledger_private.edit_expense(pg_temp.add_receipt_command('edit-add-receipt'))).phase,'applied','Receipt addition retries exactly');
select is((select revision from ledger_private.expenses where id='expense-created'),3::bigint,'Receipt addition advances source exactly once');
select is((select count(*) from ledger_private.expense_receipt_attachments where expense_id='expense-created'),1::bigint,'Receipt addition replay does not duplicate link');
select is((ledger_private.edit_expense(pg_temp.edit_command('edit-remove-receipt','3'))).error_code,
  'expense_receipt_change_unavailable','Edit cannot remove retained receipt');
select is((ledger_private.edit_expense((pg_temp.add_receipt_command('edit-duplicate-receipt','3')::jsonb ||
  '{"receiptAttachmentIds":["edit-receipt","edit-receipt"]}'::jsonb)::text)).phase,'rejected','Duplicate addition rolls back');
select is((select revision from ledger_private.expenses where id='expense-created'),3::bigint,'Rejected duplicate preserves source revision');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select ledger_private.edit_expense(pg_temp.edit_command('expense-edit-op'))$$,
  '42501','Authenticated actor required','Anonymous caller cannot replay accepted edit');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
update public.spike_account_memberships set financial_access='none'
  where account_id='account-primary' and principal_id='principal-owner';
select throws_ok($$select ledger_private.edit_expense(pg_temp.edit_command('expense-edit-op'))$$,
  '42501','Expense access required','Access withdrawal blocks accepted edit replay');
select ok(not has_function_privilege(r,'ledger_private.edit_expense(text)','EXECUTE'),r||' cannot call edit writer')
  from unnest(array['anon','service_role']) r;
select ok(not has_function_privilege(r,'public.spike_edit_expense(text)','EXECUTE'),r||' cannot call edit endpoint')
  from unnest(array['anon','service_role']) r;
set local role authenticated;
select throws_ok($$select public.spike_edit_expense(pg_temp.edit_command('expense-edit-op'))$$,
  '42501','Expense access required','Actual endpoint denies withdrawn financial access');
reset role;
update public.spike_account_memberships set financial_access='full'
  where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select is((public.spike_edit_expense(pg_temp.add_receipt_command('expense-edit-endpoint','3'))).phase,
  'applied','Authenticated endpoint applies allowed edit');
select is((public.spike_edit_expense(pg_temp.add_receipt_command('expense-edit-endpoint','3'))).phase,
  'applied','Authenticated endpoint supports exact replay');
select throws_ok($$select public.spike_edit_expense((pg_temp.edit_command('edit-endpoint-cross','3')::jsonb ||
  '{"accountId":"account-other"}'::jsonb)::text)$$,'42501','Expense access required','Actual endpoint denies cross Account');
reset role;
select * from finish();
rollback;
