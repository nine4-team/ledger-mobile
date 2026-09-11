begin;
select plan(19);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select is(
  (select phase from public.spike_create_client(
    'operation-create-client-north',
    'account-primary',
    'principal-owner',
    'client-create-v1',
    '2026-09-04T12:00:00Z',
    'client-north',
    'North House',
    pg_catalog.encode(extensions.digest(convert_to(
      '{"accountId":"account-primary","actorPrincipalId":"principal-owner","clientCreatedAt":1788523200000,"contractVersion":"client-create-v1","operationId":"operation-create-client-north","payload":{"clientId":"client-north","displayName":"North House"},"preconditions":[]}',
      'UTF8'
    ), 'sha256'), 'hex'),
    '{"accountId":"account-primary","actorPrincipalId":"principal-owner","clientCreatedAt":1788523200000,"contractVersion":"client-create-v1","operationId":"operation-create-client-north","payload":{"clientId":"client-north","displayName":"North House"},"preconditions":[]}'
  )),
  'applied',
  'authorized creation applies'
);

select is(
  (select display_name from public.spike_clients where id = 'client-north'),
  'North House',
  'the authoritative Client is readable through RLS'
);

select is(
  (select revision from public.spike_clients where id = 'client-north'),
  1::bigint,
  'the Client starts at revision one'
);

select is(
  (select phase from public.spike_create_client(
    'operation-create-client-north',
    'account-primary',
    'principal-owner',
    'client-create-v1',
    '2026-09-04T12:00:00Z',
    'client-north',
    'North House',
    pg_catalog.encode(extensions.digest(convert_to(
      '{"accountId":"account-primary","actorPrincipalId":"principal-owner","clientCreatedAt":1788523200000,"contractVersion":"client-create-v1","operationId":"operation-create-client-north","payload":{"clientId":"client-north","displayName":"North House"},"preconditions":[]}',
      'UTF8'
    ), 'sha256'), 'hex'),
    '{"accountId":"account-primary","actorPrincipalId":"principal-owner","clientCreatedAt":1788523200000,"contractVersion":"client-create-v1","operationId":"operation-create-client-north","payload":{"clientId":"client-north","displayName":"North House"},"preconditions":[]}'
  )),
  'applied',
  'an exact replay returns the immutable result'
);

select is(
  (select count(*) from public.spike_clients where id = 'client-north'),
  1::bigint,
  'an exact replay creates no duplicate Client'
);

select is(
  (select count(*) from public.spike_operation_results where operation_id = 'operation-create-client-north'),
  1::bigint,
  'an exact replay creates no duplicate operation result'
);

select throws_ok(
  $$select public.spike_create_client(
    'operation-create-client-north',
    'account-primary',
    'principal-owner',
    'client-create-v1',
    '2026-09-04T12:00:00Z',
    'client-other-payload',
    'Changed',
    repeat('a', 64),
    '{}'
  )$$,
  '23505',
  'operation id is already bound to a different command',
  'a reused OperationID cannot bind a changed payload'
);

select is(
  (select phase from public.spike_create_client(
    'operation-create-client-twin',
    'account-primary',
    'principal-owner',
    'client-create-v1',
    '2026-09-04T12:01:00Z',
    'client-twin',
    'North House',
    pg_catalog.encode(extensions.digest(convert_to(
      '{"accountId":"account-primary","actorPrincipalId":"principal-owner","clientCreatedAt":1788523260000,"contractVersion":"client-create-v1","operationId":"operation-create-client-twin","payload":{"clientId":"client-twin","displayName":"North House"},"preconditions":[]}',
      'UTF8'
    ), 'sha256'), 'hex'),
    '{"accountId":"account-primary","actorPrincipalId":"principal-owner","clientCreatedAt":1788523260000,"contractVersion":"client-create-v1","operationId":"operation-create-client-twin","payload":{"clientId":"client-twin","displayName":"North House"},"preconditions":[]}'
  )),
  'applied',
  'equal display names remain distinct stable Client identities'
);

select is(
  (select phase from public.spike_create_client(
    'operation-bad-envelope',
    'account-primary',
    'principal-owner',
    'client-create-v1',
    '2026-09-04T12:02:00Z',
    'client-bad-envelope',
    'Bad Envelope',
    repeat('b', 64),
    '{}'
  )),
  'rejected',
  'a permanent validation failure is acknowledged as a durable rejection'
);

select is(
  (select error_code from public.spike_operation_results where operation_id = 'operation-bad-envelope'),
  'client_creation_fingerprint_mismatch',
  'the durable rejection carries a stable error code'
);

select is(
  (select error_code from public.spike_create_client(
    'operation-created-at-mismatch',
    'account-primary',
    'principal-owner',
    'client-create-v1',
    '2026-09-04T12:03:00Z',
    'client-created-at-mismatch',
    'Timestamp Mismatch',
    pg_catalog.encode(extensions.digest(convert_to(
      '{"accountId":"account-primary","actorPrincipalId":"principal-owner","clientCreatedAt":1788523320001,"contractVersion":"client-create-v1","operationId":"operation-created-at-mismatch","payload":{"clientId":"client-created-at-mismatch","displayName":"Timestamp Mismatch"},"preconditions":[]}',
      'UTF8'
    ), 'sha256'), 'hex'),
    '{"accountId":"account-primary","actorPrincipalId":"principal-owner","clientCreatedAt":1788523320001,"contractVersion":"client-create-v1","operationId":"operation-created-at-mismatch","payload":{"clientId":"client-created-at-mismatch","displayName":"Timestamp Mismatch"},"preconditions":[]}'
  )),
  'client_creation_envelope_mismatch',
  'the handler binds the signed envelope timestamp to the typed RPC parameter'
);

select is(
  (select error_code from public.spike_create_client(
    'operation-created-at-overflow',
    'account-primary',
    'principal-owner',
    'client-create-v1',
    '2026-09-04T12:03:00Z',
    'client-created-at-overflow',
    'Timestamp Overflow',
    pg_catalog.encode(extensions.digest(convert_to(
      '{"accountId":"account-primary","actorPrincipalId":"principal-owner","clientCreatedAt":999999999999999999999999999999,"contractVersion":"client-create-v1","operationId":"operation-created-at-overflow","payload":{"clientId":"client-created-at-overflow","displayName":"Timestamp Overflow"},"preconditions":[]}',
      'UTF8'
    ), 'sha256'), 'hex'),
    '{"accountId":"account-primary","actorPrincipalId":"principal-owner","clientCreatedAt":999999999999999999999999999999,"contractVersion":"client-create-v1","operationId":"operation-created-at-overflow","payload":{"clientId":"client-created-at-overflow","displayName":"Timestamp Overflow"},"preconditions":[]}'
  )),
  'client_creation_envelope_mismatch',
  'an out-of-range envelope timestamp is durably rejected instead of aborting the operation'
);

select throws_ok(
  $$insert into public.spike_clients (
    id, account_id, display_name, lifecycle, revision, created_at, updated_at,
    created_at_ms, updated_at_ms,
    created_by_principal_id
  ) values (
    'client-direct', 'account-primary', 'Direct', 'active', 1, now(), now(),
    1, 1,
    'principal-owner'
  )$$,
  '42501',
  'permission denied for table spike_clients',
  'authenticated clients cannot bypass the command handler'
);

select throws_ok(
  $$update public.spike_operation_results set phase = 'rejected'
    where operation_id = 'operation-create-client-north'$$,
  '42501',
  'permission denied for table spike_operation_results',
  'authenticated clients cannot mutate an operation result'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select throws_ok(
  $$select public.spike_create_client(
    'operation-restricted', 'account-primary', 'principal-restricted',
    'client-create-v1', now(), 'client-restricted', 'Restricted', repeat('c', 64), '{}'
  )$$,
  '42501',
  'active client-management membership required',
  'an active member without the spike capability cannot create Clients'
);

select is(
  (select count(*) from public.spike_clients
    where id in ('client-north', 'client-twin')),
  2::bigint,
  'a restricted active member can read the Clients created by this test'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);

select is(
  (select count(*) from public.spike_clients),
  0::bigint,
  'another Account cannot observe Client rows or counts'
);

select is(
  (select count(*) from public.spike_operation_results),
  0::bigint,
  'another Account cannot observe operation rows or counts'
);

select throws_ok(
  $$select public.spike_create_client(
    'operation-cross-account', 'account-primary', 'principal-other',
    'client-create-v1', now(), 'client-cross-account', 'Cross Account', repeat('d', 64), '{}'
  )$$,
  '42501',
  'active client-management membership required',
  'a caller cannot forge cross-Account command scope'
);

select * from finish();
rollback;
