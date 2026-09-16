begin;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values('fee-create-project','account-primary','client-existing','Fee creation',now(),now(),1,1,'principal-owner');
create function pg_temp.fee_command(op text, amount text default '100') returns text language sql as $$
select jsonb_build_object('operationId',op,'accountId','account-primary','actorPrincipalId','principal-owner',
  'projectId','fee-create-project','installmentId',op,'categoryId','category-design-fee',
  'contractVersion','fee-installment-create-v1','createdAtMs','1000','label','Design fee',
  'amountMinorUnits',amount,'currency','USD','sortOrder','')::text $$;
select ok(has_function_privilege('authenticated','public.spike_create_fee_installment(text)','EXECUTE')
  and not has_function_privilege('anon','public.spike_create_fee_installment(text)','EXECUTE')
  and not has_function_privilege('service_role','public.spike_create_fee_installment(text)','EXECUTE'),
  'Only authenticated sessions may call the endpoint');
select ok(not has_table_privilege('authenticated','ledger_private.fee_installments','INSERT,UPDATE,DELETE'),
  'Endpoint grants do not grant direct Fee writes');
select set_config('request.jwt.claims','{}',true);
select throws_ok($$select ledger_private.create_fee_installment(pg_temp.fee_command('unauth'))$$,
  '42501','Authenticated actor required','Anonymous request denied');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
set local role authenticated;
select is((public.spike_create_fee_installment(pg_temp.fee_command('fee-first'))).phase,'applied','Authenticated endpoint permits creation without cap');
select is((public.spike_create_fee_installment(pg_temp.fee_command('fee-first'))).phase,'applied','Identical retry returns original');
set constraints ledger_private.fee_creation_evidence immediate;
reset role;
select ok(not has_table_privilege('authenticated','ledger_private.imported_fee_sources','SELECT,INSERT,UPDATE,DELETE')
  and not has_table_privilege('service_role','ledger_private.imported_fee_sources','SELECT,INSERT,UPDATE,DELETE'),
  'Import evidence remains operator-only');
select throws_ok($$insert into ledger_private.fee_installments
  (id,account_id,project_id,category_id,label,amount_minor_units,currency,created_at,created_by_principal_id)
  values('fee-unknown-time','account-primary','fee-create-project','category-design-fee','Fee',1,'USD',null,'principal-owner')$$,
  '23514','Unknown Fee creation metadata requires retained import evidence','Missing creation time requires import evidence');
select throws_ok($$insert into ledger_private.fee_installments
  (id,account_id,project_id,category_id,label,amount_minor_units,currency,created_at,created_by_principal_id)
  values('fee-unknown-creator','account-primary','fee-create-project','category-design-fee','Fee',1,'USD',now(),null)$$,
  '23514','Unknown Fee creation metadata requires retained import evidence','Missing creator requires import evidence');
select is((select count(*) from ledger_private.fee_installments where project_id='fee-create-project'),1::bigint,'Retry inserts once');
select throws_ok($$select ledger_private.create_fee_installment(pg_temp.fee_command('fee-first','101'))$$,
  '23505','Operation identity conflict','Changed retry rejected');
insert into public.spike_project_category_allocations(id,account_id,project_id,category_id,allocation_minor_units,allocation_currency,
  created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values('fee-create-cap','account-primary','fee-create-project','category-design-fee',200,'USD',now(),now(),1,1,'principal-owner');
select is((ledger_private.create_fee_installment(pg_temp.fee_command('fee-second'))).phase,'applied','Equality at cap allowed');
select is((ledger_private.create_fee_installment(pg_temp.fee_command('fee-over','1'))).error_code,'fee_total_exceeded','Cap includes all installments');
select is((select count(*) from ledger_private.fee_installments where id='fee-over'),0::bigint,'Rejected command inserts nothing');
update public.spike_project_category_allocations set allocation_minor_units=300 where id='fee-create-cap';
select is((ledger_private.create_fee_installment(pg_temp.fee_command('fee-over','1'))).error_code,'fee_total_exceeded','Rejected result stable after cap changes');
select is((ledger_private.create_fee_installment((pg_temp.fee_command('fee-wrong-category')::jsonb ||
  '{"categoryId":"category-system"}'::jsonb)::text)).error_code,'fee_category_unavailable','Non-Fee category denied');
select is((ledger_private.create_fee_installment((pg_temp.fee_command('fee-currency')::jsonb ||
  '{"currency":"EUR"}'::jsonb)::text)).error_code,'fee_currency_mismatch','Currency must match total and existing demand');
select is((ledger_private.create_fee_installment(pg_temp.fee_command('fee-zero','0'))).error_code,'fee_invalid_draft','Zero amount denied');
select is((ledger_private.create_fee_installment((pg_temp.fee_command('fee-order')::jsonb ||
  '{"sortOrder":"2147483648"}'::jsonb)::text)).error_code,'fee_integrity_conflict','Storage order overflow rejected atomically');
update public.spike_project_category_allocations set allocation_minor_units=0 where id='fee-create-cap';
select is((ledger_private.create_fee_installment(pg_temp.fee_command('fee-zero-cap','1'))).error_code,'fee_total_exceeded','Configured zero is not uncapped');
select throws_ok($$select ledger_private.create_fee_installment((pg_temp.fee_command('fee-other-account')::jsonb ||
  '{"accountId":"account-other"}'::jsonb)::text)$$,'42501','Fee access required','Cross-account denied');
update public.spike_account_memberships set financial_access='none' where account_id='account-primary' and principal_id='principal-owner';
select throws_ok($$select ledger_private.create_fee_installment(pg_temp.fee_command('fee-first'))$$,
  '42501','Fee access required','Withdrawal denies even old successful replay');
select is((select count(*) from public.spike_transactions where project_id='fee-create-project'),0::bigint,'Fee demand creates no payment Transaction');
select * from finish();
rollback;
