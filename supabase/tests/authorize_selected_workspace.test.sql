begin;
select no_plan();
select ok(not (select prosecdef from pg_proc where oid =
  'public.spike_authorize_workspace(text)'::regprocedure), 'activation obeys caller RLS');
select ok(not has_function_privilege('anon', 'public.spike_authorize_workspace(text)', 'EXECUTE'),
  'anonymous role cannot activate');
select ok(not has_function_privilege('service_role', 'public.spike_authorize_workspace(text)', 'EXECUTE'),
  'client activation is not a service-role endpoint');

set local role authenticated;
select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000001', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select is(public.spike_authorize_workspace('account-primary'),
  '{"principalId":"principal-owner","accountId":"account-primary","role":"owner","financialAccess":"full"}'::jsonb,
  'owner activation resolves exact identity and current permissions');
select throws_ok($$select public.spike_authorize_workspace('account-other')$$,
  '42501', 'workspace_access_denied', 'foreign Account is denied');
select throws_ok($$select public.spike_authorize_workspace('missing')$$,
  '42501', 'workspace_access_denied', 'missing Account cannot be distinguished from foreign');
select throws_ok($$select public.spike_authorize_workspace(null)$$,
  '42501', 'workspace_access_denied', 'selection cannot be omitted');

select set_config('request.jwt.claim.sub', '10000000-0000-0000-0000-000000000002', true);
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select is(public.spike_authorize_workspace('account-primary'),
  '{"principalId":"principal-restricted","accountId":"account-primary","role":"employee","financialAccess":"none"}'::jsonb,
  'restricted membership is not upgraded by activation');
reset role;
update public.spike_account_memberships set state='removed'
  where account_id='account-primary' and principal_id='principal-restricted';
set local role authenticated;
select throws_ok($$select public.spike_authorize_workspace('account-primary')$$,
  '42501', 'workspace_access_denied', 'removal after discovery wins over old selection');
select set_config('request.jwt.claims', '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated","is_anonymous":true}', true);
select throws_ok($$select public.spike_authorize_workspace('account-primary')$$,
  '42501', 'authentication_required', 'anonymous Auth identities cannot activate');
select set_config('request.jwt.claim.sub', '90000000-0000-0000-0000-000000000099', true);
select set_config('request.jwt.claims', '{"sub":"90000000-0000-0000-0000-000000000099","role":"authenticated"}', true);
select throws_ok($$select public.spike_authorize_workspace('account-primary')$$,
  '42501', 'identity_not_linked', 'unmapped identity is not a membership or removal result');
select set_config('request.jwt.claim.sub', '', true);
select set_config('request.jwt.claims', '{}', true);
select throws_ok($$select public.spike_authorize_workspace('account-primary')$$,
  '42501', 'authentication_required', 'no identity is denied');
reset role;
select * from finish();
rollback;
