begin;
select plan(33);

-- Keep the actual migrated Project table untouched for the schema assertions
-- below. Separately rehearse the exact additive column against a scratch row
-- that predates the ALTER; the static target gate binds this DDL to migration.
create temporary table project_config_migration_probe (
  id text primary key
);

insert into project_config_migration_probe (id)
values ('project-config-preexisting');

alter table project_config_migration_probe
  add column category_configuration_revision numeric not null default 1,
  add constraint project_config_migration_probe_revision_check
    check (
      scale(category_configuration_revision) = 0
      and category_configuration_revision >= 1::numeric
      and category_configuration_revision <= 18446744073709551615::numeric
    );

create function pg_temp.insert_project(
  project_id text,
  project_revision bigint,
  configuration_revision numeric
)
returns void
language sql
as $$
  insert into public.spike_projects (
    id, account_id, client_id, display_name, lifecycle, revision,
    category_configuration_revision,
    created_at, updated_at, created_at_ms, updated_at_ms,
    created_by_principal_id
  ) values (
    project_id, 'account-primary', 'client-existing', project_id, 'active',
    project_revision, configuration_revision,
    '2026-09-06T12:00:00Z', '2026-09-06T12:00:00Z',
    1788696000000, 1788696000000, 'principal-owner'
  )
$$;

create function pg_temp.project_envelope(
  operation_id text,
  project_id text,
  allocations jsonb
)
returns text
language sql
immutable
as $$
  select jsonb_build_object(
    'accountId', 'account-primary',
    'actorPrincipalId', 'principal-owner',
    'clientCreatedAt', 1788696000000,
    'contractVersion', 'project-create-v1',
    'operationId', operation_id,
    'payload', jsonb_build_object(
      'categoryAllocations', allocations,
      'clientSelection', jsonb_build_object(
        'clientId', 'client-existing',
        'kind', 'existing'
      ),
      'displayName', project_id,
      'projectId', project_id
    ),
    'preconditions', '[]'::jsonb
  )::text
$$;

create function pg_temp.call_project(
  operation_id text,
  project_id text,
  allocations jsonb
)
returns public.spike_operation_results
language sql
as $$
  with envelope as (
    select pg_temp.project_envelope(
      operation_id,
      project_id,
      allocations
    ) as value
  )
  select public.spike_create_project(
    operation_id,
    'account-primary',
    'principal-owner',
    'project-create-v1',
    '2026-09-06T12:00:00Z',
    project_id,
    'existing',
    'client-existing',
    null,
    project_id,
    null,
    allocations,
    encode(digest(convert_to(envelope.value, 'UTF8'), 'sha256'), 'hex'),
    envelope.value
  )
  from envelope
$$;

create function pg_temp.archive_operation_id(operation_key text)
returns text
language sql
immutable
as $$
  select 'project-archive-'
    || encode(digest(convert_to('account-primary', 'UTF8'), 'sha256'), 'hex')
    || '-'
    || substring(md5(operation_key) from 1 for 8) || '-'
    || substring(md5(operation_key) from 9 for 4) || '-'
    || substring(md5(operation_key) from 13 for 4) || '-'
    || substring(md5(operation_key) from 17 for 4) || '-'
    || substring(md5(operation_key) from 21 for 12)
$$;

create function pg_temp.archive_envelope(
  operation_id text,
  project_id text,
  expected_revision text
)
returns text
language sql
immutable
as $$
  select format(
    '{"accountId":"account-primary","actorPrincipalId":"principal-owner","clientCreatedAt":1788696000000,"contractVersion":"project-archive-v1","operationId":%s,"payload":{"projectId":%s},"preconditions":[{"expectedRevision":{"revision":%s,"subject":{"id":%s,"kind":"project"}}}]}',
    to_json(operation_id)::text,
    to_json(project_id)::text,
    expected_revision,
    to_json(project_id)::text
  )
$$;

create function pg_temp.call_archive(
  operation_key text,
  project_id text,
  expected_revision text
)
returns public.spike_operation_results
language sql
as $$
  with command_identity as (
    select pg_temp.archive_operation_id(operation_key) as value
  ),
  envelope as (
    select pg_temp.archive_envelope(
      command_identity.value,
      project_id,
      expected_revision
    ) as value
    from command_identity
  )
  select public.spike_archive_project(
    command_identity.value,
    'account-primary',
    'principal-owner',
    'project-archive-v1',
    '2026-09-06T12:00:00Z',
    project_id,
    expected_revision,
    encode(digest(convert_to(envelope.value, 'UTF8'), 'sha256'), 'hex'),
    envelope.value
  )
  from command_identity cross join envelope
$$;

select is(
  (select data_type from information_schema.columns
   where table_schema = 'public'
     and table_name = 'spike_projects'
     and column_name = 'category_configuration_revision'),
  'numeric',
  'the authoritative category-configuration generation uses exact numeric storage'
);

select is(
  (select is_nullable from information_schema.columns
   where table_schema = 'public'
     and table_name = 'spike_projects'
     and column_name = 'category_configuration_revision'),
  'NO',
  'every Project has a category-configuration generation, including an empty set'
);

select ok(
  (select column_default in ('1', '1::numeric', '''1''::numeric')
   from information_schema.columns
   where table_schema = 'public'
     and table_name = 'spike_projects'
     and column_name = 'category_configuration_revision'),
  'new and migration-existing target Projects initialize to generation 1'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.spike_projects'::regclass
      and conname = 'spike_projects_category_configuration_revision_check'
      and contype = 'c'
      and pg_get_constraintdef(oid) like '%scale(category_configuration_revision) = 0%'
      and pg_get_constraintdef(oid) like '%category_configuration_revision >= (1)::numeric%'
      and pg_get_constraintdef(oid) like
        '%category_configuration_revision <= ''18446744073709551615''::numeric%'
  ),
  'the named invariant admits exactly positive integral UInt64 generations'
);

select is(
  col_description(
    'public.spike_projects'::regclass,
    (select attnum from pg_attribute
     where attrelid = 'public.spike_projects'::regclass
       and attname = 'category_configuration_revision')
  ),
  'Independent complete Project category-configuration generation; never derived from Project or allocation-row revisions.',
  'the database documents the independent aggregate boundary'
);

select is(
  (select category_configuration_revision
   from project_config_migration_probe where id = 'project-config-preexisting'),
  1::numeric,
  'a row present before the exact additive column is backfilled to generation 1'
);

insert into public.spike_projects (
  id, account_id, client_id, display_name, lifecycle, revision,
  created_at, updated_at, created_at_ms, updated_at_ms,
  created_by_principal_id
) values (
  'project-config-empty', 'account-primary', 'client-existing',
  'Empty Configuration', 'active', 1,
  '2026-09-06T12:00:00Z', '2026-09-06T12:00:00Z',
  1788696000000, 1788696000000, 'principal-owner'
);

select is(
  (select category_configuration_revision
   from public.spike_projects where id = 'project-config-empty'),
  1::numeric,
  'an empty configuration still owns generation 1'
);

select pg_temp.insert_project('project-config-nonempty', 5, 17);

insert into public.spike_project_category_allocations (
  id, account_id, project_id, category_id,
  allocation_minor_units, allocation_currency, revision,
  created_at, updated_at, created_at_ms, updated_at_ms,
  created_by_principal_id
) values (
  'allocation-config-independent', 'account-primary',
  'project-config-nonempty', 'category-furnishings',
  0, 'USD', 999,
  '2026-09-06T12:00:00Z', '2026-09-06T12:00:00Z',
  1788696000000, 1788696000000, 'principal-owner'
);

select is(
  (select category_configuration_revision
   from public.spike_projects where id = 'project-config-nonempty'),
  17::numeric,
  'a nonempty configuration preserves its one set-level generation'
);

select is(
  (select revision from public.spike_project_category_allocations
   where id = 'allocation-config-independent'),
  999::bigint,
  'allocation-row revision remains a separate value'
);

select pg_temp.insert_project(
  'project-config-uint64-max',
  1,
  18446744073709551615::numeric
);

select is(
  (select category_configuration_revision::text
   from public.spike_projects where id = 'project-config-uint64-max'),
  '18446744073709551615',
  'the full UInt64 maximum remains lossless and canonical as decimal text'
);

select throws_ok(
  $$select pg_temp.insert_project('project-config-zero', 1, 0)$$,
  '23514', null,
  'zero is not a valid category-configuration generation'
);

select throws_ok(
  $$select pg_temp.insert_project(
    'project-config-overflow', 1, 18446744073709551616::numeric
  )$$,
  '23514', null,
  'a generation above UInt64 maximum is rejected'
);

select throws_ok(
  $$select pg_temp.insert_project('project-config-fractional', 1, 1.5)$$,
  '23514', null,
  'fractional generations are rejected instead of rounded'
);

select throws_ok(
  $$select pg_temp.insert_project('project-config-null', 1, null)$$,
  '23502', null,
  'null cannot erase the generation of an empty set'
);

select ok(
  not exists (
    select 1 from public.spike_projects
    where category_configuration_revision is null
  ),
  'all target rows satisfy the non-null backfill invariant'
);

select is(
  (select count(*) from pg_policy
   where polrelid = 'public.spike_projects'::regclass),
  1::bigint,
  'the additive foundation changes no Project RLS policy'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password,
  email_confirmed_at, raw_app_meta_data, raw_user_meta_data,
  created_at, updated_at
) values
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000004',
    'authenticated', 'authenticated', 'removed@ledger-spike.invalid', '', now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000005',
    'authenticated', 'authenticated', 'nonmember@ledger-spike.invalid', '', now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  );

insert into public.spike_principals (id, auth_user_id) values
  ('principal-removed', '10000000-0000-0000-0000-000000000004'),
  ('principal-nonmember', '10000000-0000-0000-0000-000000000005');

insert into public.spike_account_memberships (
  account_id, principal_id, role, state,
  can_manage_clients, can_manage_projects,
  can_manage_project_budgets, financial_access
) values (
  'account-primary', 'principal-removed', 'employee', 'removed',
  false, false, false, 'none'
);

select ok(
  not has_table_privilege('anon', 'public.spike_projects', 'SELECT'),
  'anonymous callers have no Project or configuration-revision read privilege'
);

select ok(
  not has_table_privilege(
    'anon', 'public.spike_projects', 'INSERT,UPDATE,DELETE'
  ),
  'anonymous callers have no Project insert, update or delete privilege'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select is(
  (select phase from pg_temp.call_project(
    'operation-project-config-empty',
    'project-config-created-empty',
    '[]'::jsonb
  )),
  'applied',
  'the real Project command creates an empty category configuration'
);

select is(
  (select category_configuration_revision
   from public.spike_projects where id = 'project-config-created-empty'),
  1::numeric,
  'the real Project command initializes an empty configuration to generation 1'
);

select is(
  (select phase from pg_temp.call_project(
    'operation-project-config-nonempty',
    'project-config-created-nonempty',
    '[{"categoryId":"category-furnishings"}]'::jsonb
  )),
  'applied',
  'the real Project command creates a nonempty category configuration'
);

select is(
  (select category_configuration_revision
   from public.spike_projects where id = 'project-config-created-nonempty'),
  1::numeric,
  'the real Project command initializes a nonempty configuration to generation 1'
);

select is(
  (select count(*) from public.spike_projects
   where account_id = 'account-primary'
     and id like 'project-config-%'),
  5::bigint,
  'an active member retains the existing Project read policy'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',
  true
);

select is(
  (select count(*) from public.spike_projects
   where account_id = 'account-primary'),
  0::bigint,
  'a removed Account member cannot infer Project configuration revisions'
);

select throws_ok(
  $$update public.spike_projects
    set category_configuration_revision = 18
    where id = 'project-config-nonempty'$$,
  '42501', 'permission denied for table spike_projects',
  'a removed Account member cannot mutate Project configuration revisions'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}',
  true
);

select is(
  (select count(*) from public.spike_projects
   where account_id = 'account-primary'),
  0::bigint,
  'an authenticated principal with no membership cannot infer Project revisions'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);

select is(
  (select count(*) from public.spike_projects
   where account_id = 'account-primary'),
  0::bigint,
  'a principal outside the Account cannot infer Project revisions'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select is(
  (select phase from pg_temp.call_archive(
    'category-config-independence', 'project-config-nonempty', '5'
  )),
  'applied',
  'the existing Project archive command remains applicable'
);

select is(
  (select revision from public.spike_projects
   where id = 'project-config-nonempty'),
  6::bigint,
  'Project archive advances only the Project entity revision'
);

select is(
  (select category_configuration_revision
   from public.spike_projects where id = 'project-config-nonempty'),
  17::numeric,
  'Project archive leaves category-configuration generation unchanged'
);

select is(
  (select revision from public.spike_project_category_allocations
   where id = 'allocation-config-independent'),
  999::bigint,
  'Project archive also leaves allocation-row revision unchanged'
);

select throws_ok(
  $$update public.spike_projects
    set category_configuration_revision = 18
    where id = 'project-config-nonempty'$$,
  '42501', 'permission denied for table spike_projects',
  'authenticated clients receive no direct configuration writer'
);

select ok(
  not has_table_privilege(
    'authenticated', 'public.spike_projects', 'INSERT,UPDATE,DELETE'
  ),
  'the foundation grants no authenticated Project insert, update or delete authority'
);

select * from finish();
rollback;
