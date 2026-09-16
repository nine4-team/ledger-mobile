begin;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values('revision-project','account-primary','client-existing','Revision test',now(),now(),1,1,'principal-owner');
insert into ledger_private.expenses(id,account_id,project_id,category_id,vendor,expense_date,final_amount_minor_units,currency,created_at,created_by_principal_id)
values('revision-a','account-primary','revision-project','category-system','A','2026-09-16',100,'USD',now(),'principal-owner'),
      ('revision-b','account-primary','revision-project','category-system','B','2026-09-16',100,'USD',now(),'principal-owner');
create function pg_temp.revision_command(op text, rev text, source text) returns text language sql as $$
select jsonb_build_object('operationId',op,'accountId','account-primary','actorPrincipalId','principal-owner',
 'projectId','revision-project','clientId','client-existing','invoiceId','revision-invoice',
 'contractVersion','invoice-revise-created-v1','createdAtMs','1000','expectedRevision',rev,'name',op,'notes','Notes',
 'sources',jsonb_build_array(jsonb_build_object('kind','expense','sourceId',source,'expectedRevision','1',
 'amountMinorUnits','100','currency','USD')))::text $$;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((ledger_private.create_live_invoice((pg_temp.revision_command('revision-create','1','revision-a')::jsonb
 -'expectedRevision'||'{"contractVersion":"invoice-create-v1"}'::jsonb)::text)).phase,'applied','Shared validation preserves initial creation');
set local role authenticated;
select is((public.spike_revise_created_invoice(pg_temp.revision_command('revision-edit','1','revision-b'))).phase,'applied','Authenticated endpoint replaces reviewed membership');
reset role;
select is((select revision from ledger_private.live_invoices where id='revision-invoice'),2::bigint,'Header revision increments once');
select is((select name from ledger_private.live_invoices where id='revision-invoice'),'revision-edit','Metadata changes atomically');
select is((select source_id from ledger_private.live_invoice_memberships where invoice_id='revision-invoice' and released_at is null),'revision-b','New source active');
select ok((select released_at is not null from ledger_private.live_invoice_memberships where invoice_id='revision-invoice' and source_id='revision-a'),'Old source history retained');
select is((ledger_private.revise_created_invoice(pg_temp.revision_command('revision-edit','1','revision-b'))).phase,'applied','Replay succeeds after revision advanced');
select is((select count(*) from ledger_private.live_invoice_memberships where invoice_id='revision-invoice'),2::bigint,'Replay adds no history');
select throws_ok($$select ledger_private.revise_created_invoice(pg_temp.revision_command('revision-edit','1','revision-a'))$$,'23505','Operation identity conflict','Changed replay denied');
select is((ledger_private.revise_created_invoice(pg_temp.revision_command('revision-stale','1','revision-a'))).error_code,'invoice_revision_conflict','Stale revision rejected');
select is((ledger_private.revise_created_invoice(pg_temp.revision_command('revision-missing','2','missing'))).error_code,'invoice_source_unavailable','Missing source rejected');
select is((select revision from ledger_private.live_invoices where id='revision-invoice'),2::bigint,'Rejection leaves header unchanged');
select is((select source_id from ledger_private.live_invoice_memberships where invoice_id='revision-invoice' and released_at is null),'revision-b','Rejection leaves complete old membership');
select is((ledger_private.revise_created_invoice(pg_temp.revision_command('revision-readd','2','revision-a'))).phase,'applied','Original source can be re-added');
select is((select count(*) from ledger_private.live_invoice_memberships where invoice_id='revision-invoice' and source_id='revision-a'),2::bigint,'Re-add preserves both occurrences');
select is((select joined_at_revision from ledger_private.live_invoice_memberships where invoice_id='revision-invoice' and released_at is null),3::bigint,'New membership binds new Invoice revision');
update ledger_private.live_invoices set status='sent' where id='revision-invoice';
select is((ledger_private.revise_created_invoice(pg_temp.revision_command('revision-sent','3','revision-a'))).error_code,'invoice_not_editable','Sent policy is not silently implemented');
update ledger_private.live_invoices set status='paid' where id='revision-invoice';
select is((ledger_private.revise_created_invoice(pg_temp.revision_command('revision-paid','3','revision-a'))).error_code,'invoice_not_editable','Paid editing denied');
update ledger_private.live_invoices set status='canceled' where id='revision-invoice';
select is((ledger_private.revise_created_invoice(pg_temp.revision_command('revision-canceled','3','revision-a'))).error_code,'invoice_not_editable','Canceled editing denied');
select ok(not has_function_privilege('authenticated','ledger_private.apply_live_invoice(text,boolean)','EXECUTE'),'Shared helper is not an exposed mode switch');
select ok(has_function_privilege('authenticated','public.spike_revise_created_invoice(text)','EXECUTE'),'Authenticated endpoint available');
select ok(not has_function_privilege('anon','public.spike_revise_created_invoice(text)','EXECUTE'),'Anonymous endpoint denied');
select ok(not has_function_privilege('service_role','public.spike_revise_created_invoice(text)','EXECUTE'),'Service role is not a user command bypass');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select ledger_private.revise_created_invoice(pg_temp.revision_command('revision-anon','3','revision-a'))$$,'42501','Authenticated actor required','Anonymous denied');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
update public.spike_account_memberships set financial_access='none' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select throws_ok($$select public.spike_revise_created_invoice(pg_temp.revision_command('revision-edit','1','revision-b'))$$,'42501','Invoice access required','Revocation denies prior successful endpoint replay');
reset role;
select is((select count(*) from public.spike_transactions where project_id='revision-project'),0::bigint,'Editing demand never creates payment');
select * from finish();
rollback;
