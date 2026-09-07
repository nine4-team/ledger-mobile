begin;

select plan(52);

create function pg_temp.space_checklist_operation_id(
  account_id text,
  operation_key text
)
returns text
language sql
immutable
as $$
  select 'space-checklist-revision-'
    || encode(digest(convert_to(account_id, 'UTF8'), 'sha256'), 'hex') || '-'
    || substring(key.value from 1 for 8) || '-'
    || substring(key.value from 9 for 4) || '-'
    || substring(key.value from 13 for 4) || '-'
    || substring(key.value from 17 for 4) || '-'
    || substring(key.value from 21 for 12)
  from (
    select case
      when operation_key ~ '^[0-9a-f]{32}$' then operation_key
      else md5(operation_key)
    end as value
  ) as key
$$;

create function pg_temp.space_checklist_envelope(
  operation_id text,
  account_id text,
  actor_id text,
  captured_at_ms bigint,
  space_id text,
  expected_revision text,
  collection jsonb
)
returns text
language sql
immutable
security definer
set search_path = ''
as $$
  select format(
    '{"accountId":%s,"actorPrincipalId":%s,"clientCreatedAt":%s,"contractVersion":"space-checklist-revision-v1","operationId":%s,"payload":{"collection":%s,"spaceId":%s},"preconditions":[{"expectedRevision":{"revision":%s,"subject":{"id":%s,"kind":"space"}}}]}',
    to_json(account_id)::text,
    to_json(actor_id)::text,
    captured_at_ms,
    to_json(operation_id)::text,
    coalesce(
      ledger_private.canonical_space_checklist_collection(collection),
      collection::text
    ),
    to_json(space_id)::text,
    expected_revision,
    to_json(space_id)::text
  )
$$;

create function pg_temp.space_checklist_collection(
  checked boolean,
  item_text text default 'Confirm lamp'
)
returns jsonb
language sql
immutable
as $$
  select jsonb_build_object(
    'checklists',
    jsonb_build_array(
      jsonb_build_object(
        'id', 'checklist-arrival',
        'items', jsonb_build_array(),
        'name', 'Install',
        'presentationOrder', 1
      ),
      jsonb_build_object(
        'id', 'checklist-installation',
        'items', jsonb_build_array(
          jsonb_build_object(
            'id', 'item-lamp',
            'isChecked', checked,
            'presentationOrder', 1,
            'text', item_text
          ),
          jsonb_build_object(
            'id', 'item-walls',
            'isChecked', true,
            'presentationOrder', 2,
            'text', 'Inspect walls'
          )
        ),
        'name', 'Install',
        'presentationOrder', 2
      )
    )
  )
$$;

create function pg_temp.call_space_checklist_revision(
  operation_key text,
  actor_id text,
  space_id text,
  expected_revision text,
  collection jsonb,
  account_id text default 'account-primary',
  captured_at timestamptz default '2026-09-07T04:00:00Z'
)
returns public.spike_operation_results
language sql
as $$
  with identity as (
    select pg_temp.space_checklist_operation_id(account_id, operation_key) as value
  ), envelope as (
    select pg_temp.space_checklist_envelope(
      identity.value,
      account_id,
      actor_id,
      floor(extract(epoch from captured_at) * 1000)::bigint,
      space_id,
      expected_revision,
      collection
    ) as value
    from identity
  )
  select public.spike_revise_space_checklists(
    identity.value,
    account_id,
    actor_id,
    'space-checklist-revision-v1',
    captured_at,
    space_id,
    expected_revision,
    collection,
    encode(digest(convert_to(envelope.value, 'UTF8'), 'sha256'), 'hex'),
    envelope.value
  )
  from identity
  cross join envelope
$$;

insert into public.spike_projects (
  id,
  account_id,
  client_id,
  display_name,
  description,
  lifecycle,
  revision,
  created_at,
  updated_at,
  created_at_ms,
  updated_at_ms,
  created_by_principal_id
) values (
  'project-space-checklist',
  'account-primary',
  'client-existing',
  'Checklist Project',
  'Must remain unchanged',
  'active',
  9,
  '2026-09-04T12:00:00Z',
  '2026-09-04T12:00:00Z',
  1788523200000,
  1788523200000,
  'principal-owner'
);

insert into public.spike_spaces (
  id,
  account_id,
  scope_kind,
  project_id,
  display_name,
  lifecycle,
  revision
) values
  (
    'space-checklist-main', 'account-primary', 'project',
    'project-space-checklist', 'Main Space', 'active', 7
  ),
  (
    'space-checklist-race', 'account-primary', 'project',
    'project-space-checklist', 'Race Space', 'active', 11
  ),
  (
    'space-checklist-archived', 'account-primary', 'project',
    'project-space-checklist', 'Archived Space', 'archived', 5
  ),
  (
    'space-checklist-inventory', 'account-primary', 'business_inventory',
    null, 'Inventory Space', 'active', 3
  ),
  (
    'space-checklist-untouched', 'account-primary', 'business_inventory',
    null, 'Untouched Space', 'active', 2
  ),
  (
    'space-checklist-other', 'account-other', 'business_inventory',
    null, 'Other Account Space', 'active', 4
  );

insert into public.spike_project_category_allocations (
  id,
  account_id,
  project_id,
  category_id,
  allocation_minor_units,
  allocation_currency,
  revision,
  created_at,
  updated_at,
  created_at_ms,
  updated_at_ms,
  created_by_principal_id
) values (
  'allocation-space-checklist',
  'account-primary',
  'project-space-checklist',
  'category-furnishings',
  42000,
  'USD',
  4,
  '2026-09-04T12:00:00Z',
  '2026-09-04T12:00:00Z',
  1788523200000,
  1788523200000,
  'principal-owner'
);

insert into public.spike_space_core_details (
  id,
  account_id,
  notes,
  created_at,
  updated_at,
  created_at_ms,
  updated_at_ms
)
select
  space.id,
  space.account_id,
  'Preserve notes for ' || space.id,
  '2026-09-04T12:00:00Z',
  '2026-09-04T12:00:00Z',
  1788523200000,
  1788523200000
from public.spike_spaces as space
where space.id like 'space-checklist-%';

insert into public.spike_space_checklists (
  id,
  account_id,
  space_id,
  checklist_id,
  name,
  presentation_order
) values
  (
    'fixture-checklist-main', 'account-primary', 'space-checklist-main',
    'checklist-old', 'Old checklist', 8
  ),
  (
    'fixture-checklist-inventory', 'account-primary', 'space-checklist-inventory',
    'checklist-inventory', 'Inventory checklist', 1
  ),
  (
    'fixture-checklist-untouched', 'account-primary', 'space-checklist-untouched',
    'checklist-untouched', 'Untouched checklist', 1
  ),
  (
    'fixture-checklist-other', 'account-other', 'space-checklist-other',
    'checklist-other', 'Other checklist', 1
  );

insert into public.spike_space_checklist_items (
  id,
  account_id,
  space_id,
  checklist_id,
  item_id,
  item_text,
  is_checked,
  presentation_order
) values
  (
    'fixture-item-main', 'account-primary', 'space-checklist-main',
    'checklist-old', 'item-old', 'Old item', false, 1
  ),
  (
    'fixture-item-inventory', 'account-primary', 'space-checklist-inventory',
    'checklist-inventory', 'item-inventory', 'Inventory item', false, 1
  ),
  (
    'fixture-item-untouched', 'account-primary', 'space-checklist-untouched',
    'checklist-untouched', 'item-untouched', 'Untouched item', false, 1
  ),
  (
    'fixture-item-other', 'account-other', 'space-checklist-other',
    'checklist-other', 'item-other', 'Other item', false, 1
  );

create temp table space_checklist_before as
select
  (
    select to_jsonb(space) - 'revision'
    from public.spike_spaces as space
    where space.id = 'space-checklist-main'
  ) as main_space_without_revision,
  (
    select to_jsonb(detail) - array['updated_at', 'updated_at_ms']
    from public.spike_space_core_details as detail
    where detail.id = 'space-checklist-main'
  ) as main_detail_without_update,
  (
    select detail.updated_at
    from public.spike_space_core_details as detail
    where detail.id = 'space-checklist-main'
  ) as main_updated_at,
  (
    select jsonb_agg(to_jsonb(space) order by space.id)
    from public.spike_spaces as space
    where space.id in ('space-checklist-untouched', 'space-checklist-other')
  ) as unrelated_spaces,
  (
    select jsonb_agg(to_jsonb(checklist) order by checklist.id)
    from public.spike_space_checklists as checklist
    where checklist.space_id in ('space-checklist-untouched', 'space-checklist-other')
  ) as unrelated_checklists,
  (
    select jsonb_agg(to_jsonb(item) order by item.id)
    from public.spike_space_checklist_items as item
    where item.space_id in ('space-checklist-untouched', 'space-checklist-other')
  ) as unrelated_items,
  (
    select jsonb_agg(to_jsonb(project) order by project.id)
    from public.spike_projects as project
    where project.id = 'project-space-checklist'
  ) as project_rows,
  (
    select jsonb_agg(to_jsonb(client) order by client.id)
    from public.spike_clients as client
  ) as client_rows,
  (
    select jsonb_agg(to_jsonb(category) order by category.id)
    from public.spike_budget_categories as category
  ) as category_rows,
  (
    select jsonb_agg(to_jsonb(allocation) order by allocation.id)
    from public.spike_project_category_allocations as allocation
  ) as allocation_rows;

grant select on space_checklist_before to authenticated;

select ok(
  has_function_privilege(
    'authenticated',
    'public.spike_revise_space_checklists(text,text,text,text,timestamptz,text,text,jsonb,text,text)',
    'EXECUTE'
  ),
  'the authenticated Data API role has an explicit RPC execute grant'
);

select ok(
  not has_function_privilege(
    'anon',
    'public.spike_revise_space_checklists(text,text,text,text,timestamptz,text,text,jsonb,text,text)',
    'EXECUTE'
  ),
  'the anonymous Data API role has no RPC execute grant'
);

select ok(
  not (
    select procedure.prosecdef
    from pg_proc as procedure
    where procedure.oid =
      'public.spike_revise_space_checklists(text,text,text,text,timestamptz,text,text,jsonb,text,text)'::regprocedure
  ),
  'the public Data API wrapper is security invoker'
);

select ok(
  (
    select procedure.prosecdef
    from pg_proc as procedure
    where procedure.oid =
      'ledger_private.spike_revise_space_checklists(text,text,text,text,timestamptz,text,text,jsonb,text,text)'::regprocedure
  ),
  'the private writer is the only security-definer mutation boundary'
);

select is(
  (
    select count(*)
    from pg_class
    where oid in (
      'public.spike_spaces'::regclass,
      'public.spike_space_core_details'::regclass,
      'public.spike_space_checklists'::regclass,
      'public.spike_space_checklist_items'::regclass,
      'public.spike_operation_results'::regclass
    )
      and relrowsecurity
  ),
  5::bigint,
  'RLS is enabled on every relation touched by the command'
);

select ok(
  not has_table_privilege(
    'authenticated', 'public.spike_spaces',
    'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  )
  and not has_table_privilege(
    'authenticated', 'public.spike_space_core_details',
    'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  )
  and not has_table_privilege(
    'authenticated', 'public.spike_space_checklists',
    'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  )
  and not has_table_privilege(
    'authenticated', 'public.spike_space_checklist_items',
    'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  )
  and not has_table_privilege(
    'authenticated', 'public.spike_operation_results',
    'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ),
  'authenticated receives no direct-table mutation grant'
);

select ok(
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'spike_spaces',
        'spike_space_core_details',
        'spike_space_checklists',
        'spike_space_checklist_items',
        'spike_operation_results'
      )
      and cmd <> 'SELECT'
  ),
  'no client mutation policy bypasses the trusted handler'
);

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);

select throws_ok(
  $$select pg_temp.call_space_checklist_revision(
    'anonymous', 'principal-owner', 'space-checklist-main', '7',
    pg_temp.space_checklist_collection(true)
  )$$,
  '42501',
  'permission denied for function spike_revise_space_checklists',
  'anonymous invocation is denied at the Data API boundary'
);

set local role authenticated;
select set_config('request.jwt.claims', '{}', true);

select throws_ok(
  $$select pg_temp.call_space_checklist_revision(
    'unauthenticated', 'principal-owner', 'space-checklist-main', '7',
    pg_temp.space_checklist_collection(true)
  )$$,
  '28000',
  'authentication required',
  'authentication is checked before Space or operation inspection'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select throws_ok(
  $$select pg_temp.call_space_checklist_revision(
    'forged-actor', 'principal-restricted', 'space-checklist-main', '7',
    pg_temp.space_checklist_collection(true)
  )$$,
  '42501',
  'actor is not the authenticated principal',
  'a forged payload actor is denied before Space inspection'
);

select throws_ok(
  $$select pg_temp.call_space_checklist_revision(
    'cross-account', 'principal-owner', 'space-checklist-other', '4',
    pg_temp.space_checklist_collection(true), 'account-other'
  )$$,
  '42501',
  'active Account membership required',
  'a cross-Account caller is denied without Space enumeration'
);

reset role;
update public.spike_account_memberships
set state = 'removed'
where account_id = 'account-primary'
  and principal_id = 'principal-restricted';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select throws_ok(
  $$select pg_temp.call_space_checklist_revision(
    'inactive', 'principal-restricted', 'space-checklist-inventory', '3',
    '{"checklists":[]}'::jsonb
  )$$,
  '42501',
  'active Account membership required',
  'an inactive member is denied without Space enumeration'
);

reset role;
update public.spike_account_memberships
set state = 'active'
where account_id = 'account-primary'
  and principal_id = 'principal-restricted';

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select throws_ok(
  $$select public.spike_revise_space_checklists(
    'invalid-operation-id',
    'account-primary',
    'principal-restricted',
    'space-checklist-revision-v1',
    '2026-09-07T04:00:00Z',
    'space-checklist-main',
    '7',
    pg_temp.space_checklist_collection(true),
    repeat('a', 64),
    '{}'
  )$$,
  '22023',
  'Space checklist revision request identity invalid',
  'a non-namespaced OperationID is refused before result insertion'
);

select is(
  (
    select phase
    from pg_temp.call_space_checklist_revision(
      'restricted-active',
      'principal-restricted',
      'space-checklist-inventory',
      '3',
      '{"checklists":[]}'::jsonb
    )
  ),
  'applied',
  'any active same-Account member may revise an active Space'
);

select is(
  (
    select revision
    from public.spike_spaces
    where id = 'space-checklist-inventory'
  ),
  4::bigint,
  'the active-member revision increments exactly once'
);

reset role;

select is(
  (
    select count(*)
    from public.spike_space_checklists
    where space_id = 'space-checklist-inventory'
  ),
  0::bigint,
  'an empty complete collection atomically clears the hierarchy'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);

select throws_ok(
  $$update public.spike_spaces
    set revision = revision + 1
    where id = 'space-checklist-main'$$,
  '42501',
  'permission denied for table spike_spaces',
  'authenticated cannot directly update a Space'
);

select throws_ok(
  $$delete from public.spike_space_checklists
    where space_id = 'space-checklist-main'$$,
  '42501',
  'permission denied for table spike_space_checklists',
  'authenticated cannot directly replace checklist rows'
);

select throws_ok(
  $$update public.spike_space_checklist_items
    set is_checked = true
    where space_id = 'space-checklist-main'$$,
  '42501',
  'permission denied for table spike_space_checklist_items',
  'authenticated cannot directly toggle a checklist item'
);

select throws_ok(
  $$update public.spike_operation_results
    set phase = 'rejected'
    where command_type = 'revise_space_checklists'$$,
  '42501',
  'permission denied for table spike_operation_results',
  'authenticated cannot mutate operation results'
);

reset role;
grant select on table
  public.spike_space_core_details,
  public.spike_space_checklists,
  public.spike_space_checklist_items
to authenticated;

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);

select is(
  (
    select error_code
    from pg_temp.call_space_checklist_revision(
      'wrong-account-identity',
      'principal-other',
      'space-checklist-main',
      '7',
      pg_temp.space_checklist_collection(true),
      'account-other'
    )
  ),
  'space_checklist_revision_conflict',
  'a wrong-Account Space identity is a non-enumerating durable conflict'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select is(
  (
    select error_code
    from pg_temp.call_space_checklist_revision(
      'missing-space',
      'principal-owner',
      'space-checklist-missing',
      '7',
      pg_temp.space_checklist_collection(true)
    )
  ),
  'space_checklist_revision_conflict',
  'a missing same-Account identity has the same durable conflict'
);

select is(
  (
    select error_code
    from pg_temp.call_space_checklist_revision(
      'archived-space',
      'principal-owner',
      'space-checklist-archived',
      '5',
      pg_temp.space_checklist_collection(true)
    )
  ),
  'space_checklist_revision_conflict',
  'an archived Space is not writable'
);

select is(
  (
    select phase
    from pg_temp.call_space_checklist_revision(
      'main',
      'principal-owner',
      'space-checklist-main',
      '7',
      pg_temp.space_checklist_collection(true)
    )
  ),
  'applied',
  'an exact active-Space revision applies'
);

select is(
  (
    select result_code
    from public.spike_operation_results
    where operation_id = pg_temp.space_checklist_operation_id(
      'account-primary', 'main'
    )
  ),
  'space_checklists_revised',
  'the immutable applied result has the exact result code'
);

select is(
  (
    select revision
    from public.spike_spaces
    where id = 'space-checklist-main'
  ),
  8::bigint,
  'the Space revision increments exactly once'
);

select is(
  (
    select string_agg(
      checklist.checklist_id || ':' || checklist.name || ':'
        || checklist.presentation_order::text,
      ',' order by checklist.presentation_order
    )
    from public.spike_space_checklists as checklist
    where checklist.space_id = 'space-checklist-main'
  ),
  'checklist-arrival:Install:1,checklist-installation:Install:2',
  'the complete ordered checklist collection replaces the old hierarchy'
);

select is(
  (
    select string_agg(
      item.checklist_id || ':' || item.item_id || ':' || item.item_text || ':'
        || item.is_checked::text || ':' || item.presentation_order::text,
      ',' order by item.checklist_id, item.presentation_order
    )
    from public.spike_space_checklist_items as item
    where item.space_id = 'space-checklist-main'
  ),
  'checklist-installation:item-lamp:Confirm lamp:true:1,checklist-installation:item-walls:Inspect walls:true:2',
  'the complete ordered item hierarchy and checked state are exact'
);

select is(
  (
    select to_jsonb(space) - 'revision'
    from public.spike_spaces as space
    where space.id = 'space-checklist-main'
  ),
  (select main_space_without_revision from space_checklist_before),
  'Space scope, identity, name, and lifecycle remain immutable'
);

select is(
  (
    select to_jsonb(detail) - array['updated_at', 'updated_at_ms']
    from public.spike_space_core_details as detail
    where detail.id = 'space-checklist-main'
  ),
  (select main_detail_without_update from space_checklist_before),
  'Space notes and creation evidence remain byte-identical'
);

select ok(
  (
    select detail.updated_at > before.main_updated_at
    from public.spike_space_core_details as detail
    cross join space_checklist_before as before
    where detail.id = 'space-checklist-main'
  ),
  'the authoritative Space update timestamp advances'
);

select is(
  (
    select to_jsonb(replay)
    from pg_temp.call_space_checklist_revision(
      'main',
      'principal-owner',
      'space-checklist-main',
      '7',
      pg_temp.space_checklist_collection(true)
    ) as replay
  ),
  (
    select to_jsonb(result)
    from public.spike_operation_results as result
    where result.operation_id = pg_temp.space_checklist_operation_id(
      'account-primary', 'main'
    )
  ),
  'an exact lost-response replay returns the byte-identical result'
);

select is(
  (
    select revision
    from public.spike_spaces
    where id = 'space-checklist-main'
  ),
  8::bigint,
  'exact replay does not increment the revision again'
);

select throws_ok(
  $$select pg_temp.call_space_checklist_revision(
    'main', 'principal-owner', 'space-checklist-main', '7',
    pg_temp.space_checklist_collection(false)
  )$$,
  '23505',
  'operation id is already bound to a different command',
  'changed same-ID replay cannot rebind the hierarchy or fingerprint'
);

select is(
  (
    select error_code
    from pg_temp.call_space_checklist_revision(
      'invalid-hierarchy',
      'principal-owner',
      'space-checklist-main',
      '8',
      jsonb_build_object(
        'checklists',
        jsonb_build_array(
          jsonb_build_object(
            'id', 'checklist-invalid',
            'items', jsonb_build_array(
              jsonb_build_object(
                'id', 'item-invalid-a',
                'isChecked', true,
                'presentationOrder', 1,
                'text', 'First'
              ),
              jsonb_build_object(
                'id', 'item-invalid-b',
                'isChecked', false,
                'presentationOrder', 1,
                'text', 'Second'
              )
            ),
            'name', 'Invalid',
            'presentationOrder', 1
          )
        )
      )
    )
  ),
  'space_checklist_revision_payload_invalid',
  'a malformed complete hierarchy is durably rejected'
);

select is(
  (
    select revision
    from public.spike_spaces
    where id = 'space-checklist-main'
  ),
  8::bigint,
  'invalid hierarchy rejection leaves the Space revision unchanged'
);

select is(
  (
    select error_code
    from pg_temp.call_space_checklist_revision(
      'stale',
      'principal-owner',
      'space-checklist-main',
      '7',
      pg_temp.space_checklist_collection(false)
    )
  ),
  'space_checklist_revision_conflict',
  'a stale expected revision is durably rejected'
);

select is(
  (
    select string_agg(
      item.item_id || ':' || item.is_checked::text,
      ',' order by item.presentation_order
    )
    from public.spike_space_checklist_items as item
    where item.space_id = 'space-checklist-main'
  ),
  'item-lamp:true,item-walls:true',
  'changed replay and stale rejection leave zero partial hierarchy writes'
);

select is(
  (
    select phase
    from pg_temp.call_space_checklist_revision(
      'race-winner',
      'principal-owner',
      'space-checklist-race',
      '11',
      pg_temp.space_checklist_collection(true, 'Winner')
    )
  ),
  'applied',
  'the first mutation at one revision applies'
);

select is(
  (
    select error_code
    from pg_temp.call_space_checklist_revision(
      'race-loser',
      'principal-owner',
      'space-checklist-race',
      '11',
      pg_temp.space_checklist_collection(false, 'Loser')
    )
  ),
  'space_checklist_revision_conflict',
  'a competing command at the consumed revision loses atomically'
);

select is(
  (
    select revision
    from public.spike_spaces
    where id = 'space-checklist-race'
  ),
  12::bigint,
  'competing commands produce only one revision increment'
);

select is(
  (
    select item_text
    from public.spike_space_checklist_items
    where space_id = 'space-checklist-race'
      and item_id = 'item-lamp'
  ),
  'Winner',
  'the losing competing command leaves no partial replacement'
);

select ok(
  pg_get_functiondef(
    'ledger_private.spike_revise_space_checklists(text,text,text,text,timestamptz,text,text,jsonb,text,text)'::regprocedure
  ) ilike '%for update%',
  'the trusted handler serializes mutation through the exact Space row lock'
);

reset role;

select is(
  (
    select jsonb_agg(to_jsonb(space) order by space.id)
    from public.spike_spaces as space
    where space.id in ('space-checklist-untouched', 'space-checklist-other')
  ),
  (select unrelated_spaces from space_checklist_before),
  'unrelated and cross-Account Spaces remain byte-identical'
);

select is(
  (
    select jsonb_agg(to_jsonb(checklist) order by checklist.id)
    from public.spike_space_checklists as checklist
    where checklist.space_id in ('space-checklist-untouched', 'space-checklist-other')
  ),
  (select unrelated_checklists from space_checklist_before),
  'unrelated and cross-Account checklists remain byte-identical'
);

select is(
  (
    select jsonb_agg(to_jsonb(item) order by item.id)
    from public.spike_space_checklist_items as item
    where item.space_id in ('space-checklist-untouched', 'space-checklist-other')
  ),
  (select unrelated_items from space_checklist_before),
  'unrelated and cross-Account checklist items remain byte-identical'
);

select is(
  (
    select jsonb_agg(to_jsonb(project) order by project.id)
    from public.spike_projects as project
    where project.id = 'project-space-checklist'
  ),
  (select project_rows from space_checklist_before),
  'the related Project and its scope remain byte-identical'
);

select is(
  (
    select jsonb_agg(to_jsonb(client) order by client.id)
    from public.spike_clients as client
  ),
  (select client_rows from space_checklist_before),
  'Client rows receive no unrelated mutation'
);

select is(
  (
    select jsonb_agg(to_jsonb(category) order by category.id)
    from public.spike_budget_categories as category
  ),
  (select category_rows from space_checklist_before),
  'budget-category and accounting authority receive no mutation'
);

select is(
  (
    select jsonb_agg(to_jsonb(allocation) order by allocation.id)
    from public.spike_project_category_allocations as allocation
  ),
  (select allocation_rows from space_checklist_before),
  'project budget allocations receive no accounting mutation'
);

select is(
  (
    select count(*)
    from public.spike_operation_results
    where operation_id = pg_temp.space_checklist_operation_id(
      'account-primary', 'main'
    )
  ),
  1::bigint,
  'one accepted OperationID owns exactly one terminal result'
);

reset role;

select throws_ok(
  $$update public.spike_operation_results
    set result_code = 'tampered'
    where operation_id = pg_temp.space_checklist_operation_id(
      'account-primary', 'main'
    )$$,
  '55000',
  'spike operation results are immutable',
  'the terminal result remains immutable even to its table owner'
);

select * from finish();

rollback;
