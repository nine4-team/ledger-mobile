begin;
select plan(22);

create function pg_temp.project_envelope(
  operation_id text,
  account_id text,
  actor_principal_id text,
  created_at_ms bigint,
  project_id text,
  selection_kind text,
  client_id text,
  new_client_display_name text,
  project_display_name text,
  project_description text,
  allocations jsonb
)
returns text
language sql
immutable
as $$
  select jsonb_build_object(
    'accountId', account_id,
    'actorPrincipalId', actor_principal_id,
    'clientCreatedAt', created_at_ms,
    'contractVersion', 'project-create-v1',
    'operationId', operation_id,
    'payload',
      jsonb_build_object(
        'categoryAllocations', allocations,
        'clientSelection',
          jsonb_build_object('clientId', client_id, 'kind', selection_kind)
          || case when new_client_display_name is null
            then '{}'::jsonb
            else jsonb_build_object('displayName', new_client_display_name)
          end,
        'displayName', project_display_name,
        'projectId', project_id
      ) || case when project_description is null
        then '{}'::jsonb
        else jsonb_build_object('description', project_description)
      end,
    'preconditions', '[]'::jsonb
  )::text
$$;

create function pg_temp.call_project(
  operation_id text,
  actor_principal_id text,
  project_id text,
  selection_kind text,
  client_id text,
  new_client_display_name text default null,
  project_display_name text default 'Test Project',
  project_description text default null,
  allocations jsonb default '[]'::jsonb,
  account_id text default 'account-primary',
  created_at timestamptz default '2026-09-04T12:00:00Z'
)
returns public.spike_operation_results
language sql
as $$
  with envelope as (
    select pg_temp.project_envelope(
      operation_id,
      account_id,
      actor_principal_id,
      floor(extract(epoch from created_at) * 1000)::bigint,
      project_id,
      selection_kind,
      client_id,
      new_client_display_name,
      project_display_name,
      project_description,
      allocations
    ) as value
  )
  select public.spike_create_project(
    operation_id,
    account_id,
    actor_principal_id,
    'project-create-v1',
    created_at,
    project_id,
    selection_kind,
    client_id,
    new_client_display_name,
    project_display_name,
    project_description,
    allocations,
    encode(digest(convert_to(envelope.value, 'UTF8'), 'sha256'), 'hex'),
    envelope.value
  )
  from envelope
$$;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select is(
  (select phase from pg_temp.call_project(
    'operation-project-existing', 'principal-owner', 'project-existing-client',
    'existing', 'client-existing'
  )),
  'applied',
  'an authorized Project with an existing Client and zero categories applies'
);

select is(
  (select count(*) from public.spike_project_category_allocations
    where project_id = 'project-existing-client'),
  0::bigint,
  'zero categories creates no allocation rows'
);

select is(
  (select phase from pg_temp.call_project(
    'operation-project-existing', 'principal-owner', 'project-existing-client',
    'existing', 'client-existing'
  )),
  'applied',
  'an exact replay returns the immutable applied result'
);

select is(
  (select count(*) from public.spike_projects where id = 'project-existing-client'),
  1::bigint,
  'an exact replay creates no duplicate Project'
);

select throws_ok(
  $$select pg_temp.call_project(
    'operation-project-existing', 'principal-owner', 'project-rebound',
    'existing', 'client-existing'
  )$$,
  '23505',
  'operation id is already bound to a different command',
  'a reused OperationID cannot bind another Project'
);

select is(
  (select phase from pg_temp.call_project(
    'operation-project-new-client', 'principal-owner', 'project-new-client',
    'new', 'client-created-with-project', 'Created With Project',
    '  Preserved Name  ', 'Canonical description',
    '[
      {"categoryId":"category-design-fee","allocation":{"currency":"EUR","minorUnits":2500}},
      {"categoryId":"category-furnishings"}
    ]'::jsonb
  )),
  'applied',
  'new Client, Project, nullable allocation, and mixed currency apply atomically'
);

select is(
  (select display_name from public.spike_clients
    where id = 'client-created-with-project'),
  'Created With Project',
  'the new Client is created in the same command'
);

select is(
  (select display_name from public.spike_projects where id = 'project-new-client'),
  '  Preserved Name  ',
  'Project display bytes are preserved instead of trimmed'
);

select is(
  (select allocation_minor_units from public.spike_project_category_allocations
    where project_id = 'project-new-client'
      and category_id = 'category-design-fee'),
  2500::bigint,
  'a positive allocation preserves integer minor units'
);

select is(
  (select allocation_currency from public.spike_project_category_allocations
    where project_id = 'project-new-client'
      and category_id = 'category-design-fee'),
  'EUR',
  'a Project allocation preserves its own currency'
);

select is(
  (select allocation_minor_units is null from public.spike_project_category_allocations
    where project_id = 'project-new-client'
      and category_id = 'category-furnishings'),
  true,
  'enabled without allocation remains distinct from explicit zero'
);

select is(
  (select error_code from pg_temp.call_project(
    'operation-project-null-kind', 'principal-owner', 'project-null-kind',
    null, 'client-existing'
  )),
  'project_setup_payload_invalid',
  'a null Client-selection discriminator is durably rejected'
);

select is(
  (select count(*) from public.spike_projects where id = 'project-null-kind'),
  0::bigint,
  'the null discriminator cannot create a Project'
);

select is(
  (select error_code from pg_temp.call_project(
    'operation-project-system-category', 'principal-owner',
    'project-system-category', 'existing', 'client-existing', null,
    'System Category', null,
    '[{"categoryId":"category-system"}]'::jsonb
  )),
  'project_setup_category_not_selectable',
  'system categories cannot be selected by an app command'
);

select throws_ok(
  $$insert into public.spike_projects (
    id, account_id, client_id, display_name, lifecycle, revision,
    created_at, updated_at, created_at_ms, updated_at_ms,
    created_by_principal_id
  ) values (
    'project-direct', 'account-primary', 'client-existing', 'Direct',
    'active', 1, now(), now(), 1, 1, 'principal-owner'
  )$$,
  '42501',
  'permission denied for table spike_projects',
  'authenticated clients cannot bypass the Project command handler'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select throws_ok(
  $$select pg_temp.call_project(
    'operation-project-restricted', 'principal-restricted',
    'project-restricted', 'existing', 'client-existing'
  )$$,
  '42501',
  'active project-management membership required',
  'an employee without Project capability cannot create a Project'
);

reset role;
update public.spike_account_memberships
set can_manage_projects = true,
    can_manage_project_budgets = true
where account_id = 'account-primary' and principal_id = 'principal-restricted';
set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select is(
  (select phase from pg_temp.call_project(
    'operation-project-delegated', 'principal-restricted',
    'project-delegated', 'existing', 'client-existing'
  )),
  'applied',
  'delegated Project capability permits a nonfinancial Project'
);

select is(
  (select error_code from pg_temp.call_project(
    'operation-project-hidden-category', 'principal-restricted',
    'project-hidden-category', 'existing', 'client-existing', null,
    'Hidden Category', null,
    '[{"categoryId":"category-design-fee"}]'::jsonb
  )),
  'project_setup_category_not_selectable',
  'budget capability does not bypass financial category visibility'
);

select is(
  (select count(*) from public.spike_budget_categories),
  2::bigint,
  'a nonfinancial member cannot infer the hidden category row through RLS'
);

select is(
  (select count(*) from public.spike_project_category_allocations
    where category_id = 'category-design-fee'),
  0::bigint,
  'a nonfinancial member cannot infer hidden allocation rows through RLS'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);

select is(
  (select count(*) from public.spike_projects),
  0::bigint,
  'another Account cannot observe Project rows or counts'
);

set local role anon;
select throws_ok(
  $$select public.spike_create_project(
    'operation-anon', 'account-primary', 'principal-owner', 'project-create-v1',
    now(), 'project-anon', 'existing', 'client-existing', null, 'Anon', null,
    '[]'::jsonb, repeat('a', 64), '{}'
  )$$,
  '42501',
  'permission denied for function spike_create_project',
  'anonymous callers cannot invoke the Project RPC'
);

select * from finish();
rollback;
