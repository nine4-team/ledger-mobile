begin;
select no_plan();

select ok(not (select prosecdef from pg_proc where oid =
  'public.spike_read_authenticated_accounts()'::regprocedure), 'lookup obeys caller RLS');
select ok(not has_function_privilege('anon', 'public.spike_read_authenticated_accounts()', 'EXECUTE'),
  'anonymous API role cannot call lookup');
select ok(not has_function_privilege('service_role', 'public.spike_read_authenticated_accounts()', 'EXECUTE'),
  'application lookup does not grant service role execution');
select ok(has_function_privilege('authenticated', 'public.spike_read_authenticated_accounts()', 'EXECUTE'),
  'authenticated callers may discover their own Accounts');

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated","is_anonymous":false}', true);
select is(public.spike_read_authenticated_accounts()->>'principalId', 'principal-owner',
  'identity is resolved from authenticated subject, not a client-supplied principal');
select is(public.spike_read_authenticated_accounts()->'accounts',
  '[{"id":"account-primary","displayName":"Synthetic Primary Account"}]'::jsonb,
  'snapshot contains only own active Accounts and display-safe fields');
select is((select count(*) from jsonb_object_keys(public.spike_read_authenticated_accounts())), 2::bigint,
  'no provider metadata, tokens, role, or implicit selected Account returned');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select is(public.spike_read_authenticated_accounts()->>'principalId', 'principal-restricted',
  'restricted employee can discover their identity without financial access');
select is(jsonb_array_length(public.spike_read_authenticated_accounts()->'accounts'), 1,
  'financial restrictions do not hide legitimate Account membership');

reset role;
update public.spike_account_memberships set state='removed'
  where account_id='account-primary' and principal_id='principal-restricted';
set local role authenticated;
select is(public.spike_read_authenticated_accounts()->'accounts', '[]'::jsonb,
  'removed membership disappears; mapped identity with no memberships has a true empty result');
select is(public.spike_read_authenticated_accounts()->>'principalId', 'principal-restricted',
  'zero membership does not manufacture or replace identity');

select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated","is_anonymous":true}', true);
select throws_ok('select public.spike_read_authenticated_accounts()', '42501', 'authentication_required',
  'anonymous Auth user is rejected even if a mapping exists');
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000099', true);
select set_config('request.jwt.claims', '{"sub":"90000000-0000-0000-0000-000000000099","role":"authenticated"}', true);
select throws_ok('select public.spike_read_authenticated_accounts()', '42501', 'identity_not_linked',
  'unmapped authenticated user is not reported as zero memberships');
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);
select throws_ok('select public.spike_read_authenticated_accounts()', '42501', 'authentication_required',
  'missing identity is rejected without listing Accounts');

reset role;
select * from finish();
rollback;
