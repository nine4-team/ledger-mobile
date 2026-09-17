begin;
select no_plan();
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
insert into public.spike_transactions(id,account_id,amount_minor_units,currency,type,origin,scope_kind,category_id,
 source,notes,payment_method,transaction_date,non_item_receipt_lines)
values('edit-receipt','account-primary',9007199254740993,'USD','return','vendor_payment','business_inventory','category-system',
 'Vendor','Retain notes','Card','2024-02-29','[{"id":"tax","description":"Tax","amountMinorUnits":"100","effect":"increase"}]');
create temp table receipt_before as select to_jsonb(t)-array['non_item_receipt_lines','receipt_lines_revision'] as value
 from public.spike_transactions t where id='edit-receipt';
create function pg_temp.receipt_command(op text, lines jsonb, expected jsonb default
 '[{"id":"tax","description":"Tax","amountMinorUnits":"100","effect":"increase","quantity":null}]')
returns text language sql as $$
 select jsonb_build_object('operationId',op,'accountId','account-primary','actorPrincipalId','principal-restricted',
 'contractVersion','transaction-receipt-lines-edit-v1','createdAtMs','1000','transactionId','edit-receipt',
 'scopeKind','business_inventory','projectId',null,'clientId',null,'currency','USD','expectedLines',expected,'lines',lines)::text;
$$;
select is((ledger_private.edit_transaction_receipt_lines(pg_temp.receipt_command('receipt-first',
 '[{"id":"tax","description":"Printed tax refund","amountMinorUnits":"101","effect":"decrease","quantity":"-2"}]'))).phase,
 'applied','Member can save mismatched receipt lines; missing/null quantity compare equally');
select is((select non_item_receipt_lines->0->>'amountMinorUnits' from public.spike_transactions where id='edit-receipt'),
 '101','Exact magnitude retained');
select is((select to_jsonb(t)-array['non_item_receipt_lines','receipt_lines_revision'] from public.spike_transactions t where id='edit-receipt'),
 (select value from receipt_before),'Cash, identity, descriptive revision and all other facts unchanged');
select is((ledger_private.edit_transaction_receipt_lines(pg_temp.receipt_command('receipt-first',
 '[{"id":"tax","description":"Printed tax refund","amountMinorUnits":"101","effect":"decrease","quantity":"-2"}]'))).phase,
 'applied','Exact retry reuses accepted result despite now-stale expected lines');
select is((select receipt_lines_revision from public.spike_transactions where id='edit-receipt'),2::bigint,
 'Applied edit advances once; retry does not advance revision');
select is((select receipt_lines_revision from public.spike_operation_results where operation_id='receipt-first'),'2',
 'Immutable result records exact applied revision');
select throws_ok($$select ledger_private.edit_transaction_receipt_lines(pg_temp.receipt_command('receipt-first','[]'))$$,
 '23505','Operation identity conflict','Changed retry rejected');
select is((ledger_private.edit_transaction_receipt_lines(pg_temp.receipt_command('receipt-stale','[]'))).error_code,
 'transaction_receipt_edit_stale','Stale replacement cannot erase another edit');
select is((ledger_private.edit_transaction_receipt_lines(pg_temp.receipt_command('receipt-stale','[]'))).phase,
 'rejected','Rejected operation remains rejected on retry');
select is((select receipt_lines_revision from public.spike_operation_results where operation_id='receipt-stale'),null::text,
 'Rejected edit has no applied revision');
select is((select receipt_lines_revision from public.spike_transactions where id='edit-receipt'),2::bigint,
 'Rejected edit does not advance revision');
select is((ledger_private.edit_transaction_receipt_lines(pg_temp.receipt_command('receipt-clear','[]',
 '[{"id":"tax","description":"Printed tax refund","amountMinorUnits":"101","effect":"decrease","quantity":"-2"}]'))).phase,
 'applied','Reviewed lines can explicitly be cleared');
select is((select non_item_receipt_lines from public.spike_transactions where id='edit-receipt'),'[]'::jsonb,'Clear readback');
select is((select receipt_lines_revision from public.spike_transactions where id='edit-receipt'),3::bigint,
 'Later accepted edit advances revision');
select is((select receipt_lines_revision from public.spike_operation_results where operation_id='receipt-first'),'2',
 'Later edit cannot rewrite an earlier operation revision');
select is((ledger_private.edit_transaction_receipt_lines(pg_temp.receipt_command('receipt-noop','[]','[]'))).phase,
 'applied','Same-value request leaves receipt unchanged');
update public.spike_transactions set non_item_receipt_lines=
 '[{"id":"z","description":"Printed quantity","amountMinorUnits":"1","effect":"increase","quantity":"-0"}]'
 where id='edit-receipt';
select is((ledger_private.edit_transaction_receipt_lines(pg_temp.receipt_command('receipt-zero','[]',
 '[{"id":"z","description":"Printed quantity","amountMinorUnits":"1","effect":"increase","quantity":"0"}]'))).phase,
 'applied','Decoded signed zero quantity does not invent a stale conflict');
update public.spike_transactions set receipt_lines_revision=9223372036854775807 where id='edit-receipt';
select is((ledger_private.edit_transaction_receipt_lines(pg_temp.receipt_command('receipt-overflow',
 '[{"id":"overflow","description":"Must not survive","amountMinorUnits":"1","effect":"increase"}]','[]'))).error_code,
 'transaction_receipt_edit_integrity_conflict','Revision overflow rejects the edit atomically');
select is((select non_item_receipt_lines from public.spike_transactions where id='edit-receipt'),'[]'::jsonb,
 'Revision overflow retains prior receipt lines');
select is((select receipt_lines_revision from public.spike_transactions where id='edit-receipt'),9223372036854775807::bigint,
 'Revision overflow retains prior revision');
select is((select receipt_lines_revision from public.spike_operation_results where operation_id='receipt-overflow'),null::text,
 'Overflow rejection cannot claim an applied revision');
select throws_ok($$select ledger_private.edit_transaction_receipt_lines(pg_temp.receipt_command('receipt-invalid',
 '[{"id":"tax","description":"Tax","amountMinorUnits":"0","effect":"increase"}]','[]'))$$,
 '22023','Invalid receipt edit command','Invalid magnitude denied');
select throws_ok($$select ledger_private.edit_transaction_receipt_lines(pg_temp.receipt_command('receipt-duplicate',
 '[{"id":"x","description":"Tax","amountMinorUnits":"1","effect":"increase"},{"id":"x","description":"Tax","amountMinorUnits":"1","effect":"increase"}]','[]'))$$,
 '22023','Invalid receipt edit command','Duplicate source IDs denied');
select throws_ok($$select ledger_private.edit_transaction_receipt_lines((pg_temp.receipt_command('receipt-cash','[]','[]')::jsonb
 || '{"amountMinorUnits":"0"}')::text)$$,'22023','Invalid receipt edit command','Cash is not writable');
select throws_ok($$select ledger_private.edit_transaction_receipt_lines((pg_temp.receipt_command('receipt-foreign','[]','[]')::jsonb
 || '{"accountId":"account-other"}')::text)$$,'42501','Receipt edit access required','Foreign tenant denied');
select throws_ok($$select ledger_private.edit_transaction_receipt_lines((pg_temp.receipt_command('receipt-actor','[]','[]')::jsonb
 || '{"actorPrincipalId":"principal-owner"}')::text)$$,'42501','Authenticated actor required','Actor spoofing denied');
select throws_ok($$select ledger_private.edit_transaction_receipt_lines((pg_temp.receipt_command('receipt-currency','[]','[]')::jsonb
 || '{"currency":"EUR"}')::text)$$,'42501','Receipt edit unavailable','Currency mismatch denied');
insert into public.spike_budget_categories(id,account_id,display_name,kind,visibility_class,presentation_order,lifecycle,is_system,excludes_from_overall_budget,created_at_ms,updated_at_ms)
values('receipt-fee','account-primary','Receipt Fee','fee','company_financial',61,'active',false,false,1,1);
update public.spike_transactions set category_id='receipt-fee' where id='edit-receipt';
select throws_ok($$select ledger_private.edit_transaction_receipt_lines(pg_temp.receipt_command('receipt-hidden','[]','[]'))$$,
 '42501','Receipt edit unavailable','Hidden Fee denied');
select throws_ok($$select ledger_private.edit_transaction_receipt_lines(pg_temp.receipt_command('receipt-noop','[]','[]'))$$,
 '42501','Receipt edit unavailable','Replay rechecks current visibility');
update public.spike_transactions set category_id='category-system' where id='edit-receipt';
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values('receipt-project','account-primary','client-existing','Receipt project',now(),now(),1,1,'principal-owner');
select ledger_private.import_client_payment('receipt-paid','account-primary','receipt-project','client-existing',100,'USD',
 'synthetic-receipt','paid','\x01'::bytea);
create temp table receipt_paid_before as select to_jsonb(t) as value from public.spike_transactions t where id='receipt-paid';
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select throws_ok($$select ledger_private.edit_transaction_receipt_lines((pg_temp.receipt_command('receipt-paid-edit','[]','[]')::jsonb
 || '{"actorPrincipalId":"principal-owner","transactionId":"receipt-paid","scopeKind":"project","projectId":"receipt-project","clientId":"client-existing"}')::text)$$,
 '42501','Receipt edit unavailable','Owner cannot edit immutable client payment via vendor receipt command');
select is((select to_jsonb(t) from public.spike_transactions t where id='receipt-paid'),
 (select value from receipt_paid_before),'Immutable payment unchanged');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',true);
update public.spike_account_memberships set state='removed' where account_id='account-primary' and principal_id='principal-restricted';
select throws_ok($$select ledger_private.edit_transaction_receipt_lines(pg_temp.receipt_command('receipt-noop','[]','[]'))$$,
 '42501','Receipt edit access required','Removed member cannot replay');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select ledger_private.edit_transaction_receipt_lines(pg_temp.receipt_command('receipt-anon','[]','[]'))$$,
 '42501','Authenticated actor required','Anonymous actor denied');
select ok(has_function_privilege('authenticated','public.spike_edit_transaction_receipt_lines(text)','execute'),
 'Authenticated checked endpoint available');
select ok(not has_function_privilege('anon','public.spike_edit_transaction_receipt_lines(text)','execute'),
 'Anonymous endpoint execution absent');
select ok(not has_function_privilege('anon','ledger_private.edit_transaction_receipt_lines(text)','execute'),
 'Anonymous execution absent');
select * from finish();
rollback;
