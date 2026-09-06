begin;
select plan(81);

create function pg_temp.archive_operation_id(account_id text, operation_key text)
returns text
language sql
immutable
as $$
  select 'project-archive-'
    || encode(digest(convert_to(account_id, 'UTF8'), 'sha256'), 'hex')
    || '-'
    || substring(md5(operation_key) from 1 for 8) || '-'
    || substring(md5(operation_key) from 9 for 4) || '-'
    || substring(md5(operation_key) from 13 for 4) || '-'
    || substring(md5(operation_key) from 17 for 4) || '-'
    || substring(md5(operation_key) from 21 for 12)
$$;

create function pg_temp.archive_envelope(
  operation_id text,
  account_id text,
  actor_principal_id text,
  captured_at_ms bigint,
  project_id text,
  expected_revision text
)
returns text
language sql
immutable
as $$
  select format(
    '{"accountId":%s,"actorPrincipalId":%s,"clientCreatedAt":%s,"contractVersion":"project-archive-v1","operationId":%s,"payload":{"projectId":%s},"preconditions":[{"expectedRevision":{"revision":%s,"subject":{"id":%s,"kind":"project"}}}]}',
    to_json(account_id)::text,
    to_json(actor_principal_id)::text,
    captured_at_ms,
    to_json(operation_id)::text,
    to_json(project_id)::text,
    expected_revision,
    to_json(project_id)::text
  )
$$;

create function pg_temp.call_archive(
  operation_key text,
  actor_principal_id text,
  project_id text,
  expected_revision text,
  account_id text default 'account-primary',
  captured_at timestamptz default '2026-09-05T12:00:00Z'
)
returns public.spike_operation_results
language sql
as $$
  with command_identity as (
    select pg_temp.archive_operation_id(account_id, operation_key) as value
  ),
  envelope as (
    select pg_temp.archive_envelope(
      command_identity.value,
      account_id,
      actor_principal_id,
      floor(extract(epoch from captured_at) * 1000)::bigint,
      project_id,
      expected_revision
    ) as value
    from command_identity
  )
  select public.spike_archive_project(
    command_identity.value,
    account_id,
    actor_principal_id,
    'project-archive-v1',
    captured_at,
    project_id,
    expected_revision,
    encode(digest(convert_to(envelope.value, 'UTF8'), 'sha256'), 'hex'),
    envelope.value
  )
  from command_identity cross join envelope
$$;

insert into public.spike_clients (
  id, account_id, display_name, lifecycle, revision, created_at, updated_at,
  created_at_ms, updated_at_ms, created_by_principal_id
) values (
  'client-other-archive', 'account-other', 'Other Archive Client', 'active', 3,
  '2026-09-04T12:00:00Z', '2026-09-04T12:00:00Z',
  1788523200000, 1788523200000, 'principal-other'
);

insert into public.spike_projects (
  id, account_id, client_id, display_name, description, lifecycle, revision,
  created_at, updated_at, created_at_ms, updated_at_ms,
  created_by_principal_id
) values
  (
    'project-archive-main', 'account-primary', 'client-existing',
    '  Project Archive Main  ', 'Preserve this description', 'active', 41,
    '2026-09-04T12:00:00Z', '2026-09-04T12:00:00Z',
    1788523200000, 1788523200000, 'principal-owner'
  ),
  (
    'project-archive-conflict', 'account-primary', 'client-existing',
    'Conflict Boundary', null, 'active', 7,
    '2026-09-04T12:00:00Z', '2026-09-04T12:00:00Z',
    1788523200000, 1788523200000, 'principal-owner'
  ),
  (
    'project-archive-max', 'account-primary', 'client-existing',
    'Signed Maximum', null, 'active', 9223372036854775807,
    '2026-09-04T12:00:00Z', '2026-09-04T12:00:00Z',
    1788523200000, 1788523200000, 'principal-owner'
  ),
  (
    'project-archive-other', 'account-other', 'client-other-archive',
    'Other Account Project', null, 'active', 1,
    '2026-09-04T12:00:00Z', '2026-09-04T12:00:00Z',
    1788523200000, 1788523200000, 'principal-other'
  );

insert into public.spike_project_category_allocations (
  id, account_id, project_id, category_id, allocation_minor_units,
  allocation_currency, revision, created_at, updated_at, created_at_ms,
  updated_at_ms, created_by_principal_id
) values (
  'allocation-archive-main', 'account-primary', 'project-archive-main',
  'category-furnishings', 12345, 'USD', 9,
  '2026-09-04T12:00:00Z', '2026-09-04T12:00:00Z',
  1788523200000, 1788523200000, 'principal-owner'
);

create temp table archive_before as
select
  (select to_jsonb(project) - array['lifecycle', 'revision', 'updated_at', 'updated_at_ms']
   from public.spike_projects as project
   where project.id = 'project-archive-main') as project_preserved,
  (select to_jsonb(client)
   from public.spike_clients as client
   where client.id = 'client-existing') as client_row,
  (select jsonb_agg(to_jsonb(category) order by category.id)
   from public.spike_budget_categories as category
   where category.account_id = 'account-primary') as category_rows,
  (select jsonb_agg(to_jsonb(allocation) order by allocation.id)
   from public.spike_project_category_allocations as allocation
   where allocation.project_id = 'project-archive-main') as allocation_rows,
  (select updated_at from public.spike_projects where id = 'project-archive-main')
    as old_updated_at,
  (select updated_at_ms from public.spike_projects where id = 'project-archive-main')
    as old_updated_at_ms;
grant select on archive_before to authenticated;

set local role authenticated;
select set_config('request.jwt.claims', '{}', true);

select throws_ok(
  $$select pg_temp.call_archive(
    'operation-archive-unauthenticated', 'principal-owner',
    'project-archive-main', '41'
  )$$,
  '28000',
  'authentication required',
  'authentication is checked before command or subject inspection'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select throws_ok(
  $$select pg_temp.call_archive(
    'operation-archive-restricted-existing', 'principal-restricted',
    'project-archive-main', '41'
  )$$,
  '42501',
  'active project-management membership required',
  'a restricted active member cannot archive an existing Project'
);

select throws_ok(
  $$select pg_temp.call_archive(
    'operation-archive-restricted-missing', 'principal-restricted',
    'project-does-not-exist', '41'
  )$$,
  '42501',
  'active project-management membership required',
  'a restricted caller receives the same denial for a missing Project'
);

select is(
  (select count(*) from public.spike_operation_results
   where command_type = 'archive_project'),
  0::bigint,
  'authorization denial discloses and records no operation result'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select throws_ok(
  $$select pg_temp.call_archive(
    'operation-archive-actor-mismatch', 'principal-restricted',
    'project-archive-main', '41'
  )$$,
  '42501',
  'actor is not the authenticated principal',
  'the caller cannot forge another actor'
);

select throws_ok(
  $$select pg_temp.call_archive(
    'operation-archive-cross-account', 'principal-owner',
    'project-archive-other', '1', 'account-other'
  )$$,
  '42501',
  'active project-management membership required',
  'the caller cannot forge another Account scope'
);

reset role;
update public.spike_account_memberships
set state = 'removed'
where account_id = 'account-primary' and principal_id = 'principal-owner';
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select throws_ok(
  $$select pg_temp.call_archive(
    'operation-archive-revoked', 'principal-owner',
    'project-archive-main', '41'
  )$$,
  '42501',
  'active project-management membership required',
  'a revoked member cannot archive'
);

reset role;
update public.spike_account_memberships
set state = 'active'
where account_id = 'account-primary' and principal_id = 'principal-owner';
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);

select throws_ok(
  $$with identity as (
    select pg_temp.archive_operation_id(
      'account-primary', 'cross-command-reservation'
    ) as value
  ), envelope as (
    select format(
      '{"accountId":"account-other","actorPrincipalId":"principal-other","clientCreatedAt":1788609600000,"contractVersion":"client-create-v1","operationId":%s,"payload":{"clientId":"client-reserved-prefix","displayName":"Reserved Prefix"},"preconditions":[]}',
      to_json(identity.value)::text
    ) as value
    from identity
  )
  select public.spike_create_client(
    identity.value, 'account-other', 'principal-other', 'client-create-v1',
    '2026-09-05T12:00:00Z', 'client-reserved-prefix', 'Reserved Prefix',
    encode(digest(convert_to(envelope.value, 'UTF8'), 'sha256'), 'hex'),
    envelope.value
  )
  from identity cross join envelope$$,
  '22023',
  'project archive request identity invalid',
  'a non-archive command cannot occupy an exact Account A archive namespace ID'
);

select is(
  (select count(*) from public.spike_clients
   where id = 'client-reserved-prefix'),
  0::bigint,
  'namespace rejection rolls back the cross-account Client insert'
);

select is(
  (select count(*) from public.spike_operation_results
   where operation_id = pg_temp.archive_operation_id(
     'account-primary', 'cross-command-reservation'
   )),
  0::bigint,
  'namespace rejection leaves no cross-command result row'
);

select is(
  (select phase from pg_temp.call_archive(
    'operation-archive-account-b', 'principal-other',
    'project-archive-other', '1', 'account-other'
  )),
  'applied',
  'Account B can create its own namespaced immutable archive result'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select is(
  (select phase from pg_temp.call_archive(
    'cross-command-reservation', 'principal-owner',
    'project-reserved-prefix-missing', '1'
  )),
  'rejected',
  'the rightful Account can reuse the reserved ID for an archive command'
);

select is(
  (select error_code from public.spike_operation_results
   where operation_id = pg_temp.archive_operation_id(
     'account-primary', 'cross-command-reservation'
   )),
  'project_archive_revision_conflict',
  'rightful reuse records only the generic missing-Project conflict'
);

select throws_ok(
  $$with identity as (
    select pg_temp.archive_operation_id(
      'account-other', 'operation-archive-account-b'
    ) as value
  ), envelope as (
    select pg_temp.archive_envelope(
      identity.value, 'account-primary', 'principal-owner', 1788609600000,
      'project-archive-main', '41'
    ) as value
    from identity
  )
  select public.spike_archive_project(
    identity.value, 'account-primary', 'principal-owner', 'project-archive-v1',
    '2026-09-05T12:00:00Z', 'project-archive-main', '41',
    encode(digest(convert_to(envelope.value, 'UTF8'), 'sha256'), 'hex'),
    envelope.value
  )
  from identity cross join envelope$$,
  '22023',
  'project archive request identity invalid',
  'an Account B archive ID is structurally invalid in authorized Account A scope'
);

select is(
  (select count(*) from public.spike_operation_results
   where operation_id = pg_temp.archive_operation_id(
     'account-other', 'operation-archive-account-b'
   )),
  0::bigint,
  'Account A cannot disclose the existing Account B result through RLS'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);

select is(
  (select count(*) from public.spike_operation_results
   where operation_id = pg_temp.archive_operation_id(
     'account-primary', 'cross-command-reservation'
   )),
  0::bigint,
  'Account B cannot observe Account A rightful reuse of the reserved ID'
);

reset role;
select is(
  (select account_id || ':' || count(*)::text
   from public.spike_operation_results
   where operation_id = pg_temp.archive_operation_id(
     'account-other', 'operation-archive-account-b'
   )
   group by account_id),
  'account-other:1',
  'wrongly namespaced presentation creates no Account A result or duplicate'
);

select is(
  (select account_id || ':' || count(*)::text
   from public.spike_operation_results
   where operation_id = pg_temp.archive_operation_id(
     'account-primary', 'cross-command-reservation'
   )
   group by account_id),
  'account-primary:1',
  'reserved ID has exactly one immutable result owned by its rightful Account'
);
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select throws_ok(
  $$select public.spike_archive_project(
    'invalid operation', 'account-primary', 'principal-owner',
    'project-archive-v1', '2026-09-05T12:00:00Z',
    'project-archive-main', '41', repeat('a', 64), '{}'
  )$$,
  '22023',
  'project archive request identity invalid',
  'an unrecordable OperationID fails with the bounded transport error'
);

select throws_ok(
  $$select public.spike_archive_project(
    null, 'account-primary', 'principal-owner', 'project-archive-v1',
    '2026-09-05T12:00:00Z', 'project-archive-main', '41',
    repeat('a', 64), '{}'
  )$$,
  '22023',
  'project archive request identity invalid',
  'a null OperationID fails with the same bounded transport error'
);

select throws_ok(
  $$select public.spike_archive_project(
    pg_temp.archive_operation_id('account-primary', 'transport-fingerprint'),
    'account-primary',
    'principal-owner', 'project-archive-v1', '2026-09-05T12:00:00Z',
    'project-archive-main', '41', null, '{}'
  )$$,
  '22023',
  'project archive request identity invalid',
  'an unrecordable fingerprint fails without identity substitution'
);

select throws_ok(
  $$select public.spike_archive_project(
    pg_temp.archive_operation_id('account-primary', 'transport-bad-fingerprint'),
    'account-primary',
    'principal-owner', 'project-archive-v1', '2026-09-05T12:00:00Z',
    'project-archive-main', '41', 'not-a-fingerprint', '{}'
  )$$,
  '22023',
  'project archive request identity invalid',
  'an invalid fingerprint cannot fall through to a result constraint'
);

select throws_ok(
  $$select public.spike_archive_project(
    pg_temp.archive_operation_id('account-primary', 'transport-envelope'),
    'account-primary',
    'principal-owner', 'project-archive-v1', '2026-09-05T12:00:00Z',
    'project-archive-main', '41', repeat('a', 64), null
  )$$,
  '22023',
  'project archive request identity invalid',
  'a null envelope fails before immutable-result insertion'
);

select throws_ok(
  $$select public.spike_archive_project(
    pg_temp.archive_operation_id('account-primary', 'transport-time'),
    'account-primary', 'principal-owner',
    'project-archive-v1', null, 'project-archive-main', '41',
    repeat('a', 64), '{}'
  )$$,
  '22023',
  'project archive request identity invalid',
  'a null timestamp fails before immutable-result insertion'
);

select throws_ok(
  $$select public.spike_archive_project(
    pg_temp.archive_operation_id('account-primary', 'transport-submillisecond'),
    'account-primary',
    'principal-owner', 'project-archive-v1', '2026-09-05T12:00:00.000001Z',
    'project-archive-main', '41', repeat('a', 64), '{}'
  )$$,
  '22023',
  'project archive request identity invalid',
  'a timestamp outside the canonical millisecond wire precision fails boundedly'
);

select throws_ok(
  $$select public.spike_archive_project(
    pg_temp.archive_operation_id('account-primary', 'transport-contract'),
    'account-primary',
    'principal-owner', null, '2026-09-05T12:00:00Z',
    'project-archive-main', '41', repeat('a', 64), '{}'
  )$$,
  '22023',
  'project archive request identity invalid',
  'a null contract identity fails before immutable-result insertion'
);

select throws_ok(
  $$select public.spike_archive_project(
    pg_temp.archive_operation_id('account-primary', 'transport-bad-contract'),
    'account-primary',
    'principal-owner', 'bad contract', '2026-09-05T12:00:00Z',
    'project-archive-main', '41', repeat('a', 64), '{}'
  )$$,
  '22023',
  'project archive request identity invalid',
  'an invalid contract identifier fails boundedly instead of hitting storage'
);

select throws_ok(
  $$select public.spike_archive_project(
    pg_temp.archive_operation_id('account-primary', 'transport-project'),
    'account-primary',
    'principal-owner', 'project-archive-v1', '2026-09-05T12:00:00Z',
    null, '41', repeat('a', 64), '{}'
  )$$,
  '22023',
  'project archive request identity invalid',
  'a null Project identity fails before immutable-result insertion'
);

select throws_ok(
  $$select public.spike_archive_project(
    pg_temp.archive_operation_id('account-primary', 'transport-bad-project'),
    'account-primary',
    'principal-owner', 'project-archive-v1', '2026-09-05T12:00:00Z',
    'bad project', '41', repeat('a', 64), '{}'
  )$$,
  '22023',
  'project archive request identity invalid',
  'an invalid Project identifier fails boundedly instead of being sanitized'
);

select is(
  (select count(*) from public.spike_operation_results
   where operation_id in (
     select pg_temp.archive_operation_id('account-primary', operation_key)
     from (values
       ('transport-fingerprint'),
       ('transport-bad-fingerprint'),
       ('transport-envelope'),
       ('transport-time'),
       ('transport-submillisecond'),
       ('transport-contract'),
       ('transport-bad-contract'),
       ('transport-project'),
       ('transport-bad-project')
     ) as transport(operation_key)
   )),
  0::bigint,
  'unrecordable requests create no sanitized or partial result identity'
);

select is(
  (with envelope as (
    select pg_temp.archive_envelope(
      'project-archive-820fcd051d436cfe81328997babf666384118e46578dce1afe250c40b3d3f07f-11111111-2222-4333-8444-555555555555',
      'account-primary', 'principal-owner', 1788609600000,
      'project-archive-vector', '41'
    ) as value
  )
  select result.error_code
  from envelope
  cross join lateral public.spike_archive_project(
    'project-archive-820fcd051d436cfe81328997babf666384118e46578dce1afe250c40b3d3f07f-11111111-2222-4333-8444-555555555555',
    'account-primary', 'principal-owner', 'project-archive-v1',
    '2026-09-05T12:00:00Z', 'project-archive-vector', '41',
    encode(digest(convert_to(envelope.value, 'UTF8'), 'sha256'), 'hex'),
    envelope.value
  ) as result),
  'project_archive_revision_conflict',
  'an authorized missing Project returns the generic durable conflict'
);

select is(
  (select request_sha256 from public.spike_operation_results
   where operation_id = 'project-archive-820fcd051d436cfe81328997babf666384118e46578dce1afe250c40b3d3f07f-11111111-2222-4333-8444-555555555555'),
  '9ac984815935b833e106d154f3b8f968e4d7a7f877d8199bb1698bfbd9e6bc43',
  'request_sha256 matches the frozen nine-field length-prefixed test vector'
);

select is(
  (select phase from pg_temp.call_archive(
    'operation-archive-main', 'principal-owner', 'project-archive-main', '41'
  )),
  'applied',
  'an authorized exact active revision applies'
);

select is(
  (select result_code from public.spike_operation_results
   where operation_id = pg_temp.archive_operation_id(
     'account-primary', 'operation-archive-main'
   )),
  'project_archived',
  'the immutable terminal result has the bounded applied code'
);

select is(
  (select lifecycle from public.spike_projects where id = 'project-archive-main'),
  'archived',
  'the Project moves from active to archived'
);

select is(
  (select revision from public.spike_projects where id = 'project-archive-main'),
  42::bigint,
  'the exact signed physical revision increments once'
);

select ok(
  (select project.updated_at > before.old_updated_at
   from public.spike_projects as project cross join archive_before as before
   where project.id = 'project-archive-main'),
  'the server timestamp advances monotonically'
);

select ok(
  (select project.updated_at_ms > before.old_updated_at_ms
   from public.spike_projects as project cross join archive_before as before
   where project.id = 'project-archive-main'),
  'the integer server timestamp advances monotonically'
);

select is(
  (select to_jsonb(project) - array['lifecycle', 'revision', 'updated_at', 'updated_at_ms']
   from public.spike_projects as project where project.id = 'project-archive-main'),
  (select project_preserved from archive_before),
  'every other Project field remains byte-identical'
);

select is(
  (select to_jsonb(client) from public.spike_clients as client
   where client.id = 'client-existing'),
  (select client_row from archive_before),
  'the related Client row remains byte-identical'
);

select is(
  (select jsonb_agg(to_jsonb(category) order by category.id)
   from public.spike_budget_categories as category
   where category.account_id = 'account-primary'),
  (select category_rows from archive_before),
  'budget-category definitions remain byte-identical'
);

select is(
  (select jsonb_agg(to_jsonb(allocation) order by allocation.id)
   from public.spike_project_category_allocations as allocation
   where allocation.project_id = 'project-archive-main'),
  (select allocation_rows from archive_before),
  'Project allocation rows remain byte-identical'
);

select is(
  (select count(*) from public.spike_operation_results
   where operation_id = pg_temp.archive_operation_id(
     'account-primary', 'operation-archive-main'
   )),
  1::bigint,
  'one apply writes exactly one immutable result'
);

select is(
  (select to_jsonb(replayed) from pg_temp.call_archive(
    'operation-archive-main', 'principal-owner', 'project-archive-main', '41'
  ) as replayed),
  (select to_jsonb(result) from public.spike_operation_results as result
   where result.operation_id = pg_temp.archive_operation_id(
     'account-primary', 'operation-archive-main'
   )),
  'exact lost-response replay returns the byte-identical result'
);

select is(
  (select count(*) from public.spike_operation_results
   where operation_id = pg_temp.archive_operation_id(
     'account-primary', 'operation-archive-main'
   )),
  1::bigint,
  'exact replay inserts no duplicate result'
);

select throws_ok(
  $$with envelope as (
    select pg_temp.archive_envelope(
      pg_temp.archive_operation_id('account-primary', 'operation-archive-main'),
      'account-primary', 'principal-owner',
      1788609600000, 'project-archive-main', '41'
    ) as value
  )
  select public.spike_archive_project(
    pg_temp.archive_operation_id('account-primary', 'operation-archive-main'),
    'account-primary', 'principal-owner',
    'project-archive-v1', '2026-09-05T12:00:00Z',
    'project-archive-main', '42',
    encode(digest(convert_to(envelope.value, 'UTF8'), 'sha256'), 'hex'),
    envelope.value
  ) from envelope$$,
  '23505',
  'operation id is already bound to a different command',
  'replay rejects a changed redundant expected-revision RPC field'
);

select throws_ok(
  $$with envelope as (
    select pg_temp.archive_envelope(
      pg_temp.archive_operation_id('account-primary', 'operation-archive-main'),
      'account-primary', 'principal-owner',
      1788609600000, 'project-archive-main', '41'
    ) as value
  )
  select public.spike_archive_project(
    pg_temp.archive_operation_id('account-primary', 'operation-archive-main'),
    'account-primary', 'principal-owner',
    'project-archive-v1', '2026-09-05T12:00:00.001Z',
    'project-archive-main', '41',
    encode(digest(convert_to(envelope.value, 'UTF8'), 'sha256'), 'hex'),
    envelope.value
  ) from envelope$$,
  '23505',
  'operation id is already bound to a different command',
  'replay rejects a changed redundant captured-at RPC field'
);

select throws_ok(
  $$select pg_temp.call_archive(
    'operation-archive-main', 'principal-owner',
    'project-archive-conflict', '7'
  )$$,
  '23505',
  'operation id is already bound to a different command',
  'changed same-ID replay cannot rebind its Project or fingerprint'
);

select is(
  (select phase from pg_temp.call_archive(
    'operation-archive-main-again', 'principal-owner',
    'project-archive-main', '42'
  )),
  'rejected',
  'an already archived Project produces a durable conflict'
);

select is(
  (select error_code from public.spike_operation_results
   where operation_id = pg_temp.archive_operation_id(
     'account-primary', 'operation-archive-main-again'
   )),
  'project_archive_revision_conflict',
  'already archived, missing, and revision conflicts share one non-enumerating code'
);

select is(
  (select revision from public.spike_projects where id = 'project-archive-main'),
  42::bigint,
  'an already-archived conflict cannot increment again'
);

select is(
  (select error_code from pg_temp.call_archive(
    'operation-archive-future', 'principal-owner',
    'project-archive-conflict', '8'
  )),
  'project_archive_revision_conflict',
  'a future revision is a durable conflict'
);

select is(
  (select error_code from pg_temp.call_archive(
    'operation-archive-zero', 'principal-owner',
    'project-archive-conflict', '0'
  )),
  'project_archive_revision_conflict',
  'a stale zero revision is a durable conflict'
);

select is(
  (select error_code from pg_temp.call_archive(
    'operation-archive-out-signed', 'principal-owner',
    'project-archive-conflict', '9223372036854775808'
  )),
  'project_archive_revision_conflict',
  'a UInt64 revision above signed bigint cannot match a physical row'
);

select is(
  (select error_code from pg_temp.call_archive(
    'operation-archive-uint-max', 'principal-owner',
    'project-archive-conflict', '18446744073709551615'
  )),
  'project_archive_revision_conflict',
  'UInt64 maximum remains exact and conflicts without coercion or wrap'
);

select is(
  (select error_code from pg_temp.call_archive(
    'operation-archive-over-uint', 'principal-owner',
    'project-archive-conflict', '18446744073709551616'
  )),
  'project_archive_payload_invalid',
  'a decimal above UInt64 maximum is durably rejected as invalid'
);

select is(
  (select phase from pg_temp.call_archive(
    'operation-archive-conflict-apply', 'principal-owner',
    'project-archive-conflict', '7'
  )),
  'applied',
  'conflicting attempts do not prevent a later exact revision apply'
);

select is(
  (select revision from public.spike_projects
   where id = 'project-archive-conflict'),
  8::bigint,
  'only the exact apply increments the conflicted Project'
);

select is(
  (select error_code from pg_temp.call_archive(
    'operation-archive-signed-exhausted', 'principal-owner',
    'project-archive-max', '9223372036854775807'
  )),
  'project_archive_revision_conflict',
  'signed bigint maximum cannot increment or wrap'
);

select is(
  (select lifecycle || ':' || revision::text from public.spike_projects
   where id = 'project-archive-max'),
  'active:9223372036854775807',
  'revision exhaustion leaves the Project unchanged'
);

select is(
  (select error_code from public.spike_archive_project(
    pg_temp.archive_operation_id('account-primary', 'operation-archive-bad-json'),
    'account-primary', 'principal-owner',
    'project-archive-v1', '2026-09-05T12:00:00Z', 'project-archive-max', '1',
    encode(digest(convert_to('{', 'UTF8'), 'sha256'), 'hex'), '{'
  )),
  'project_archive_command_encoding_invalid',
  'malformed command JSON becomes a bounded durable rejection'
);

select is(
  (select to_jsonb(replayed) from public.spike_archive_project(
    pg_temp.archive_operation_id('account-primary', 'operation-archive-bad-json'),
    'account-primary', 'principal-owner',
    'project-archive-v1', '2026-09-05T12:00:00Z', 'project-archive-max', '1',
    encode(digest(convert_to('{', 'UTF8'), 'sha256'), 'hex'), '{'
  ) as replayed),
  (select to_jsonb(result) from public.spike_operation_results as result
   where result.operation_id = pg_temp.archive_operation_id(
     'account-primary', 'operation-archive-bad-json'
   )),
  'an exact rejected-command replay returns its immutable result'
);

select throws_ok(
  $$select public.spike_archive_project(
    pg_temp.archive_operation_id('account-primary', 'operation-archive-bad-json'),
    'account-primary', 'principal-owner',
    'project-archive-v1', '2026-09-05T12:00:00Z', 'project-archive-max', '2',
    encode(digest(convert_to('{', 'UTF8'), 'sha256'), 'hex'), '{'
  )$$,
  '23505',
  'operation id is already bound to a different command',
  'changed redundant fields cannot replay a previously rejected command'
);

select is(
  (select error_code from public.spike_archive_project(
    pg_temp.archive_operation_id('account-primary', 'operation-archive-fingerprint'),
    'account-primary', 'principal-owner',
    'project-archive-v1', '2026-09-05T12:00:00Z', 'project-archive-max', '1',
    repeat('a', 64),
    pg_temp.archive_envelope(
      pg_temp.archive_operation_id('account-primary', 'operation-archive-fingerprint'),
      'account-primary', 'principal-owner',
      1788609600000, 'project-archive-max', '1'
    )
  )),
  'project_archive_fingerprint_mismatch',
  'a valid-shaped but wrong fingerprint is durably rejected'
);

select ok(
  not has_function_privilege(
    'public',
    'public.spike_archive_project(text,text,text,text,timestamptz,text,text,text,text)',
    'EXECUTE'
  ),
  'PUBLIC has no archive RPC execution privilege'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.spike_archive_project(text,text,text,text,timestamptz,text,text,text,text)',
    'EXECUTE'
  ),
  'anon has no archive RPC execution privilege'
);

select ok(
  has_function_privilege(
    'authenticated',
    'public.spike_archive_project(text,text,text,text,timestamptz,text,text,text,text)',
    'EXECUTE'
  ),
  'authenticated has the one public archive RPC privilege'
);

select ok(
  (select not procedure.prosecdef
     and procedure.proconfig @> array['search_path=""']::text[]
   from pg_proc as procedure
   where procedure.oid =
     'public.spike_archive_project(text,text,text,text,timestamptz,text,text,text,text)'::regprocedure),
  'the public archive RPC is security-invoker with an empty search path'
);

select ok(
  (select procedure.prosecdef
     and procedure.proconfig @> array['search_path=""']::text[]
   from pg_proc as procedure
   where procedure.oid =
     'ledger_private.spike_archive_project(text,text,text,text,timestamptz,text,text,text,text)'::regprocedure),
  'the privileged handler is explicitly security-definer with an empty search path'
);

select ok(
  not has_function_privilege(
    'anon',
    'ledger_private.spike_archive_project(text,text,text,text,timestamptz,text,text,text,text)',
    'EXECUTE'
  ),
  'anon cannot execute the privileged private handler'
);

select ok(
  not has_function_privilege(
    'service_role',
    'public.spike_archive_project(text,text,text,text,timestamptz,text,text,text,text)',
    'EXECUTE'
  ),
  'service_role has no archive RPC execution path'
);

select ok(
  not has_function_privilege(
    'service_role',
    'ledger_private.spike_archive_project(text,text,text,text,timestamptz,text,text,text,text)',
    'EXECUTE'
  ),
  'service_role cannot execute the privileged archive handler'
);

select ok(
  not has_table_privilege('authenticated', 'public.spike_projects', 'UPDATE'),
  'authenticated has no direct Project UPDATE privilege'
);

select ok(
  not has_table_privilege(
    'authenticated', 'public.spike_operation_results', 'INSERT,UPDATE,DELETE'
  ),
  'authenticated has no direct operation-result write privilege'
);

select throws_ok(
  $$update public.spike_projects
    set lifecycle = 'active' where id = 'project-archive-main'$$,
  '42501',
  'permission denied for table spike_projects',
  'an authenticated caller cannot restore or directly mutate a Project'
);

select throws_ok(
  $$update public.spike_operation_results
    set phase = 'rejected'
    where operation_id = pg_temp.archive_operation_id(
      'account-primary', 'operation-archive-main'
    )$$,
  '42501',
  'permission denied for table spike_operation_results',
  'an authenticated caller cannot mutate immutable terminal evidence'
);

set local role anon;
select throws_ok(
  $$select public.spike_archive_project(
    'operation-archive-anon', 'account-primary', 'principal-owner',
    'project-archive-v1', now(), 'project-archive-main', '42', repeat('a', 64), '{}'
  )$$,
  '42501',
  'permission denied for function spike_archive_project',
  'anonymous callers cannot invoke the archive RPC'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);

select is(
  (select count(*) from public.spike_projects
   where account_id = 'account-primary' and id like 'project-archive-%'),
  0::bigint,
  'another Account cannot enumerate the archived Project rows'
);

select is(
  (select count(*) from public.spike_operation_results
   where account_id = 'account-primary' and command_type = 'archive_project'),
  0::bigint,
  'another Account cannot enumerate archive results'
);

reset role;
select ok(
  position('delete ' in lower(pg_get_functiondef(
    'ledger_private.spike_archive_project(text,text,text,text,timestamptz,text,text,text,text)'::regprocedure
  ))) = 0,
  'the trusted archive handler contains no delete statement'
);

select ok(
  position('spike_clients' in lower(pg_get_functiondef(
    'ledger_private.spike_archive_project(text,text,text,text,timestamptz,text,text,text,text)'::regprocedure
  ))) = 0
  and position('spike_budget_categories' in lower(pg_get_functiondef(
    'ledger_private.spike_archive_project(text,text,text,text,timestamptz,text,text,text,text)'::regprocedure
  ))) = 0
  and position('spike_project_category_allocations' in lower(pg_get_functiondef(
    'ledger_private.spike_archive_project(text,text,text,text,timestamptz,text,text,text,text)'::regprocedure
  ))) = 0,
  'the trusted handler names no represented Client/category/allocation relation'
);

select * from finish();
rollback;
