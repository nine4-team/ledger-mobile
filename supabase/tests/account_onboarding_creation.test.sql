begin;
select no_plan();
insert into auth.users(id,aud,role,email,encrypted_password)
 values('90000000-0000-0000-0000-000000000096','authenticated','authenticated','onboarding@ledger-tests.invalid','');
set local role authenticated;
select set_config('request.jwt.claim.sub','90000000-0000-0000-0000-000000000096',true);
select set_config('request.jwt.claims','{"sub":"90000000-0000-0000-0000-000000000096","role":"authenticated","is_anonymous":false}',true);
select throws_ok('select public.spike_read_authenticated_accounts()','42501','identity_not_linked',
  'unmapped identity is not silently called empty');
select set_config('test.new_principal',public.spike_prepare_authenticated_principal(),true);
select is(public.spike_prepare_authenticated_principal(),current_setting('test.new_principal'),
  'repeated bootstrap preserves identity');
select is(public.spike_read_authenticated_accounts()->'accounts','[]'::jsonb,
  'explicit bootstrap permits authoritative zero membership without granting an Account');
reset role;
select is((select count(*) from public.spike_principals where auth_user_id='90000000-0000-0000-0000-000000000096'),
  1::bigint,'one binding for the authenticated subject');
select ok(not has_function_privilege('anon','public.spike_create_initial_account(uuid,text)','EXECUTE'),
  'anonymous API cannot create Accounts');
select ok(not has_table_privilege('authenticated','ledger_private.account_creation_receipts','SELECT'),
  'creation receipts are not exposed');
update public.spike_account_memberships set state='removed' where principal_id='principal-restricted';
set local role authenticated;
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated","is_anonymous":false}',true);
select is(public.spike_prepare_authenticated_principal(),'principal-restricted',
  'bootstrap preserves existing identity rather than replacing it');
select set_config('test.created_account',public.spike_create_initial_account(
  '10000000-0000-0000-0000-000000000099','My account')->>'accountId',true);
select is(public.spike_create_initial_account('10000000-0000-0000-0000-000000000099','My account')->>'accountId',
  current_setting('test.created_account'),'retry returns the same Account');
select is((select count(*) from public.spike_account_memberships where state='active'),1::bigint,
  'one visible active membership');
select is((select role from public.spike_account_memberships where account_id=current_setting('test.created_account')),
  'owner','caller owns the Account');
select is((select financial_access from public.spike_account_memberships where account_id=current_setting('test.created_account')),
  'full','owner has full financial access');
select is((select count(*) from public.spike_budget_categories where account_id=current_setting('test.created_account')),
  4::bigint,'all four original defaults are created atomically');
select is((select furnishings_category_id from public.spike_accounts where id=current_setting('test.created_account')),
  current_setting('test.created_account') || ':furnishings','canonical Furnishings identity is explicit');
select is((select visibility_class from public.spike_budget_categories where id=current_setting('test.created_account') || ':design-fee'),
  'company_financial','existing Fee visibility derivation applies');
select throws_ok($$select public.spike_create_initial_account('10000000-0000-0000-0000-000000000099','Different')$$,
  '22023','account_creation_retry_mismatch','changed retry cannot alter prior Account');
select throws_ok($$select public.spike_create_initial_account('10000000-0000-0000-0000-000000000098','My account')$$,
  '42501','account_already_available','different retry key cannot create a second Account');
select set_config('request.jwt.claim.sub','10000000-0000-0000-0000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select count(*) from public.spike_accounts where id=current_setting('test.created_account')),0::bigint,
  'another identity cannot read the new Account');
select throws_ok($$select public.spike_create_initial_account('10000000-0000-0000-0000-000000000099','My account')$$,
  '42501','account_already_available','same key cannot expose another identity receipt');
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","is_anonymous":true}',true);
select throws_ok('select public.spike_prepare_authenticated_principal()',
  '42501','authentication_required','anonymous Auth identity cannot bootstrap');
select throws_ok($$select public.spike_create_initial_account('10000000-0000-0000-0000-000000000099','My account')$$,
  '42501','authentication_required','anonymous Auth identity cannot create');
reset role;
select * from finish();
rollback;
