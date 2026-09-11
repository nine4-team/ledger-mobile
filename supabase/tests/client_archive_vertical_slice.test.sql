-- CONFIG-86F1E734BC70: executable replacement for the retained READY marker.
begin;
select plan(53);

create function pg_temp.client_archive_operation_id(account_id text, operation_key text)
returns text language sql immutable as $$
  select 'client-archive-'
    || encode(digest(convert_to(account_id, 'UTF8'), 'sha256'), 'hex') || '-'
    || substring(key.value from 1 for 8) || '-'
    || substring(key.value from 9 for 4) || '-'
    || substring(key.value from 13 for 4) || '-'
    || substring(key.value from 17 for 4) || '-'
    || substring(key.value from 21 for 12)
  from (select case when operation_key ~ '^[0-9a-f]{32}$'
    then operation_key else md5(operation_key) end as value) as key
$$;

create function pg_temp.client_archive_envelope(
  operation_id text, account_id text, actor_id text, captured_at_ms bigint,
  client_id text, expected_revision text
) returns text language sql immutable as $$
  select format(
    '{"accountId":%s,"actorPrincipalId":%s,"clientCreatedAt":%s,"contractVersion":"client-archive-v1","operationId":%s,"payload":{"clientId":%s},"preconditions":[{"expectedRevision":{"revision":%s,"subject":{"id":%s,"kind":"client"}}}]}',
    to_json(account_id)::text, to_json(actor_id)::text, captured_at_ms,
    to_json(operation_id)::text, to_json(client_id)::text, expected_revision,
    to_json(client_id)::text
  )
$$;

create function pg_temp.call_client_archive(
  operation_key text, actor_id text, client_id text, expected_revision text,
  account_id text default 'account-primary',
  captured_at timestamptz default '2026-09-05T12:00:00Z'
) returns public.spike_operation_results language sql as $$
  with identity as (
    select pg_temp.client_archive_operation_id(account_id, operation_key) value
  ), envelope as (
    select pg_temp.client_archive_envelope(
      identity.value, account_id, actor_id,
      floor(extract(epoch from captured_at) * 1000)::bigint,
      client_id, expected_revision
    ) value from identity
  )
  select public.spike_archive_client(
    identity.value, account_id, actor_id, 'client-archive-v1', captured_at,
    client_id, expected_revision,
    encode(digest(convert_to(envelope.value, 'UTF8'), 'sha256'), 'hex'),
    envelope.value
  ) from identity cross join envelope
$$;

insert into public.spike_clients (
  id, account_id, display_name, lifecycle, revision, created_at, updated_at,
  created_at_ms, updated_at_ms, created_by_principal_id
) values
  ('client-archive-main', 'account-primary', '  Preserve Client Name  ', 'active', 41,
   '2026-09-04T12:00:00Z', '2026-09-04T12:00:00Z', 1788523200000, 1788523200000, 'principal-owner'),
  ('client-archive-conflict', 'account-primary', 'Conflict', 'active', 7,
   '2026-09-04T12:00:00Z', '2026-09-04T12:00:00Z', 1788523200000, 1788523200000, 'principal-owner'),
  ('client-archive-max', 'account-primary', 'Maximum', 'active', 9223372036854775807,
   '2026-09-04T12:00:00Z', '2026-09-04T12:00:00Z', 1788523200000, 1788523200000, 'principal-owner'),
  ('client-archive-other', 'account-other', 'Other', 'active', 1,
   '2026-09-04T12:00:00Z', '2026-09-04T12:00:00Z', 1788523200000, 1788523200000, 'principal-other');

insert into public.spike_projects (
  id, account_id, client_id, display_name, description, lifecycle, revision,
  created_at, updated_at, created_at_ms, updated_at_ms, created_by_principal_id
) values (
  'project-for-client-archive', 'account-primary', 'client-archive-main',
  'Preserved Project', 'Preserved history boundary', 'active', 9,
  '2026-09-04T12:00:00Z', '2026-09-04T12:00:00Z',
  1788523200000, 1788523200000, 'principal-owner'
);

insert into public.spike_project_category_allocations (
  id, account_id, project_id, category_id, allocation_minor_units,
  allocation_currency, revision, created_at, updated_at, created_at_ms,
  updated_at_ms, created_by_principal_id
) values (
  'allocation-for-client-archive', 'account-primary', 'project-for-client-archive',
  'category-furnishings', 12345, 'USD', 3,
  '2026-09-04T12:00:00Z', '2026-09-04T12:00:00Z',
  1788523200000, 1788523200000, 'principal-owner'
);

create temp table client_archive_before as
select
  (select to_jsonb(client) - array['lifecycle','revision','updated_at','updated_at_ms']
   from public.spike_clients client where id = 'client-archive-main') client_preserved,
  (select updated_at from public.spike_clients where id = 'client-archive-main') old_updated_at,
  (select updated_at_ms from public.spike_clients where id = 'client-archive-main') old_updated_at_ms,
  (select jsonb_agg(to_jsonb(project) order by id) from public.spike_projects project
   where client_id = 'client-archive-main') projects,
  (select jsonb_agg(to_jsonb(allocation) order by id)
   from public.spike_project_category_allocations allocation
   where project_id = 'project-for-client-archive') allocations;
grant select on client_archive_before to authenticated;

set local role authenticated;
select set_config('request.jwt.claims', '{}', true);
select throws_ok(
  $$select pg_temp.call_client_archive('unauth', 'principal-owner', 'client-archive-main', '41')$$,
  '28000', 'authentication required', 'authentication precedes Client inspection'
);

select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select throws_ok(
  $$select pg_temp.call_client_archive('restricted-existing', 'principal-restricted', 'client-archive-main', '41')$$,
  '42501', 'active client-management membership required', 'restricted member is denied'
);
select throws_ok(
  $$select pg_temp.call_client_archive('restricted-missing', 'principal-restricted', 'missing-client', '41')$$,
  '42501', 'active client-management membership required', 'denial is non-enumerating'
);
select is((select count(*) from public.spike_operation_results where command_type='archive_client'),
  0::bigint, 'denial records no result');

select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select throws_ok(
  $$select pg_temp.call_client_archive('actor-mismatch', 'principal-restricted', 'client-archive-main', '41')$$,
  '42501', 'actor is not the authenticated principal', 'actor binding is enforced'
);
select throws_ok(
  $$select pg_temp.call_client_archive('cross-account', 'principal-owner', 'client-archive-other', '1', 'account-other')$$,
  '42501', 'active client-management membership required', 'cross-Account scope is denied'
);

reset role;
update public.spike_account_memberships set state='removed'
where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);
select throws_ok(
  $$select pg_temp.call_client_archive('revoked', 'principal-owner', 'client-archive-main', '41')$$,
  '42501', 'active client-management membership required', 'revoked member is denied'
);
reset role;
update public.spike_account_memberships set state='active'
where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}', true);

select throws_ok(
  $$select public.spike_archive_client('invalid operation', 'account-primary', 'principal-owner',
    'client-archive-v1', '2026-09-05T12:00:00Z', 'client-archive-main', '41', repeat('a',64), '{}')$$,
  '22023', 'client archive request identity invalid', 'invalid operation identity is a bounded transport error'
);
select throws_ok(
  $$select public.spike_archive_client(
    pg_temp.client_archive_operation_id('account-other','wrong-account'),
    'account-primary', 'principal-owner', 'client-archive-v1', '2026-09-05T12:00:00Z',
    'client-archive-main', '41', repeat('a',64), '{}')$$,
  '22023', 'client archive request identity invalid', 'operation identity is Account-bound'
);

select is('client-archive-'
  || encode(digest(convert_to('account-primary','UTF8'),'sha256'),'hex')
  || '-11111111-2222-4333-8444-555555555555',
  'client-archive-820fcd051d436cfe81328997babf666384118e46578dce1afe250c40b3d3f07f-11111111-2222-4333-8444-555555555555',
  'Client archive identity has the exact Account digest and canonical UUID bytes');
select is(encode(digest(convert_to(pg_temp.client_archive_envelope(
  'client-archive-820fcd051d436cfe81328997babf666384118e46578dce1afe250c40b3d3f07f-11111111-2222-4333-8444-555555555555',
  'account-primary','principal-owner',1788609600000,'client-archive-vector','41'
), 'UTF8'), 'sha256'), 'hex'),
  'b78d5bc5e1668cb70d55ea870279388b1619e0ef22965b84e9864362cf4af578',
  'canonical Client archive envelope matches the frozen digest vector');
select is((select error_code from pg_temp.call_client_archive(
  '11111111222243338444555555555555','principal-owner','client-archive-vector','41')),
  'client_archive_revision_conflict', 'authorized missing Client is a generic durable conflict');
select is((select request_sha256 from public.spike_operation_results where operation_id=
  'client-archive-820fcd051d436cfe81328997babf666384118e46578dce1afe250c40b3d3f07f-11111111-2222-4333-8444-555555555555'),
  '1c06768afba8dc718a657a3d89a9b46b9ddccb630e823fdaa2c1e4a8d1460cd2',
  'request_sha256 matches the frozen nine-field length-prefixed vector');

select is((select phase from pg_temp.call_client_archive(
  'main', 'principal-owner', 'client-archive-main', '41')), 'applied',
  'active exact revision applies');
select is((select result_code from public.spike_operation_results where operation_id=
  pg_temp.client_archive_operation_id('account-primary','main')), 'client_archived',
  'applied result code is exact');
select is((select lifecycle from public.spike_clients where id='client-archive-main'),
  'archived', 'Client lifecycle changes to archived');
select is((select revision from public.spike_clients where id='client-archive-main'),
  42::bigint, 'revision increments exactly once');
select ok((select client.updated_at > before.old_updated_at
  from public.spike_clients client cross join client_archive_before before
  where client.id='client-archive-main'), 'timestamp advances monotonically');
select ok((select client.updated_at_ms > before.old_updated_at_ms
  from public.spike_clients client cross join client_archive_before before
  where client.id='client-archive-main'), 'millisecond timestamp advances monotonically');
select is((select to_jsonb(client)-array['lifecycle','revision','updated_at','updated_at_ms']
  from public.spike_clients client where id='client-archive-main'),
  (select client_preserved from client_archive_before), 'all other Client fields are preserved');
select is((select jsonb_agg(to_jsonb(project) order by id) from public.spike_projects project
  where client_id='client-archive-main'), (select projects from client_archive_before),
  'all related Projects are byte-identical');
select is((select jsonb_agg(to_jsonb(allocation) order by id)
  from public.spike_project_category_allocations as allocation
  where project_id='project-for-client-archive'),
  (select allocations from client_archive_before), 'all related allocations are byte-identical');

select is((select to_jsonb(replay) from pg_temp.call_client_archive(
  'main','principal-owner','client-archive-main','41') replay),
  (select to_jsonb(result) from public.spike_operation_results result where operation_id=
    pg_temp.client_archive_operation_id('account-primary','main')),
  'lost-response replay returns the byte-identical immutable result');
select throws_ok(
  $$select pg_temp.call_client_archive('main','principal-owner','client-archive-conflict','7')$$,
  '23505', 'operation id is already bound to a different command', 'changed replay cannot rebind'
);
select is((select error_code from pg_temp.call_client_archive(
  'already-archived','principal-owner','client-archive-main','42')),
  'client_archive_revision_conflict', 'already archived is a generic durable conflict');
select is((select error_code from pg_temp.call_client_archive(
  'stale','principal-owner','client-archive-conflict','6')),
  'client_archive_revision_conflict', 'stale revision conflicts');
select is((select error_code from pg_temp.call_client_archive(
  'future','principal-owner','client-archive-conflict','8')),
  'client_archive_revision_conflict', 'future revision conflicts');
select is((select error_code from pg_temp.call_client_archive(
  'signed-boundary','principal-owner','client-archive-conflict','9223372036854775808')),
  'client_archive_revision_conflict', 'out-of-signed-range UInt64 remains exact');
select is((select error_code from pg_temp.call_client_archive(
  'uint-max','principal-owner','client-archive-conflict','18446744073709551615')),
  'client_archive_revision_conflict', 'UInt64 maximum remains exact');
select is((select error_code from pg_temp.call_client_archive(
  'over-uint','principal-owner','client-archive-conflict','18446744073709551616')),
  'client_archive_payload_invalid', 'above UInt64 maximum is invalid');
select is((select error_code from pg_temp.call_client_archive(
  'signed-exhausted','principal-owner','client-archive-max','9223372036854775807')),
  'client_archive_revision_conflict', 'signed bigint exhaustion cannot wrap');

select is((select error_code from public.spike_archive_client(
  pg_temp.client_archive_operation_id('account-primary','bad-json'),
  'account-primary','principal-owner','client-archive-v1','2026-09-05T12:00:00Z',
  'client-archive-conflict','7', encode(digest(convert_to('{','UTF8'),'sha256'),'hex'),'{')),
  'client_archive_command_encoding_invalid', 'malformed JSON is durably rejected');

select ok(not has_function_privilege('public',
  'public.spike_archive_client(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE'),
  'PUBLIC cannot execute archive RPC');
select ok(not has_function_privilege('anon',
  'public.spike_archive_client(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE'),
  'anon cannot execute archive RPC');
select ok(has_function_privilege('authenticated',
  'public.spike_archive_client(text,text,text,text,timestamptz,text,text,text,text)','EXECUTE'),
  'authenticated can invoke the public Data API archive RPC');
select ok((select not prosecdef and proconfig @> array['search_path=""']::text[]
  from pg_proc where oid='public.spike_archive_client(text,text,text,text,timestamptz,text,text,text,text)'::regprocedure),
  'public RPC is security invoker with empty search path');
select ok((select prosecdef and proconfig @> array['search_path=""']::text[]
  from pg_proc where oid='ledger_private.spike_archive_client(text,text,text,text,timestamptz,text,text,text,text)'::regprocedure),
  'private handler is security definer with empty search path');
select ok(not has_table_privilege('authenticated','public.spike_clients','UPDATE'),
  'authenticated cannot directly mutate Clients');
select ok(not has_table_privilege('authenticated','public.spike_operation_results','INSERT,UPDATE,DELETE'),
  'authenticated cannot mutate immutable results');
select throws_ok($$update public.spike_clients set lifecycle='active' where id='client-archive-main'$$,
  '42501','permission denied for table spike_clients','direct restore is denied');

select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}', true);
select is((select lifecycle from public.spike_clients where id='client-archive-main'),
  'archived', 'restricted same-Account member retains archived Client read access');
select is((select count(*) from public.spike_projects where client_id='client-archive-main'),
  1::bigint, 'restricted same-Account member retains related Project read access');
select is((select phase from public.spike_operation_results where operation_id=
  pg_temp.client_archive_operation_id('account-primary','main')),
  'applied', 'restricted same-Account member retains operation-result read access');
select throws_ok(
  $$select pg_temp.call_client_archive('restricted-after','principal-restricted','client-archive-main','42')$$,
  '42501','active client-management membership required',
  'restricted read access does not grant archive mutation capability');

set local role anon;
select throws_ok($$select public.spike_archive_client('x','account-primary','principal-owner',
  'client-archive-v1',now(),'client-archive-main','42',repeat('a',64),'{}')$$,
  '42501','permission denied for function spike_archive_client','anonymous invocation is denied');

set local role authenticated;
select set_config('request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}', true);
select is((select count(*) from public.spike_clients where id='client-archive-main'),
  0::bigint, 'RLS hides another Account Client');
select is((select count(*) from public.spike_operation_results where command_type='archive_client'),
  0::bigint, 'RLS hides another Account results');

reset role;
select ok(position('delete ' in lower(pg_get_functiondef(
  'ledger_private.spike_archive_client(text,text,text,text,timestamptz,text,text,text,text)'::regprocedure)))=0,
  'archive handler has no delete path');
select ok(position('spike_projects' in lower(pg_get_functiondef(
  'ledger_private.spike_archive_client(text,text,text,text,timestamptz,text,text,text,text)'::regprocedure)))=0
  and position('spike_project_category_allocations' in lower(pg_get_functiondef(
  'ledger_private.spike_archive_client(text,text,text,text,timestamptz,text,text,text,text)'::regprocedure)))=0,
  'archive handler contains no related-row mutation path');
select ok(position('for update' in lower(pg_get_functiondef(
  'ledger_private.spike_create_project_with_client_lock(text,text,text,text,timestamptz,text,text,text,text,text,text,jsonb,text,text)'::regprocedure))) > 0,
  'Project Setup wrapper takes the indexed Client row lock');
select ok(position('spike_create_project_with_client_lock' in lower(pg_get_functiondef(
  'public.spike_create_project(text,text,text,text,timestamptz,text,text,text,text,text,text,jsonb,text,text)'::regprocedure))) > 0,
  'the public Project Setup RPC routes through the repaired lock boundary');
select ok(not has_function_privilege('authenticated',
  'ledger_private.spike_create_project(text,text,text,text,timestamptz,text,text,text,text,text,text,jsonb,text,text)',
  'EXECUTE'), 'authenticated cannot bypass the repaired Project Setup boundary');
select ok((select indisunique from pg_index where indexrelid =
  'public.spike_clients_account_id_id_key'::regclass),
  'Client locking predicate is backed by the unique Account/Client index');

select * from finish();
rollback;
