begin;

select plan(84);

select is(
  (
    select string_agg(
      column_name || ':' || data_type || ':' || is_nullable,
      ',' order by ordinal_position
    )
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'spike_spaces'
  ),
  'id:text:NO,account_id:text:NO,scope_kind:text:NO,project_id:text:YES,display_name:text:NO,lifecycle:text:NO,revision:bigint:NO',
  'the existing Space relation remains exactly seven columns'
);

select ok(
  has_table_privilege('authenticated', 'public.spike_spaces', 'SELECT'),
  'the existing authenticated Space SELECT grant remains intact'
);

select ok(
  not has_table_privilege(
    'authenticated', 'public.spike_spaces',
    'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ),
  'the existing Space relation gains no authenticated mutation privilege'
);

select is(
  (
    select count(*)
    from pg_policies
    where schemaname = 'public' and tablename = 'spike_spaces'
  ),
  1::bigint,
  'the existing Space relation still has exactly one policy'
);

select ok(
  exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename = 'spike_spaces'
      and policyname = 'spike_spaces_select_active_member'
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and qual like '%lifecycle%active%'
      and qual like '%has_active_membership%account_id%'
  ),
  'the existing Space policy remains active-Space plus active-membership only'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.spike_spaces'::regclass
      and conname = 'spike_spaces_account_identity_key'
      and contype = 'u'
      and pg_get_constraintdef(oid) = 'UNIQUE (account_id, id)'
  ),
  'the sole additive base change supplies the exact Account and Space parent key'
);

select ok(
  not (select relforcerowsecurity from pg_class where oid = 'public.spike_spaces'::regclass),
  'the base Space RLS mode is not altered by the detail slice'
);

select ok(
  to_regclass('public.spike_space_core_details') is not null,
  'the separate one-to-one Space core-detail relation exists'
);

select ok(
  to_regclass('public.spike_space_checklists') is not null,
  'the relational Space checklist relation exists'
);

select ok(
  to_regclass('public.spike_space_checklist_items') is not null,
  'the relational Space checklist-item relation exists'
);

select is(
  (
    select string_agg(
      column_name || ':' || data_type || ':' || is_nullable,
      ',' order by ordinal_position
    )
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'spike_space_core_details'
  ),
  'id:text:NO,account_id:text:NO,notes:text:YES,created_at:timestamp with time zone:NO,updated_at:timestamp with time zone:NO,created_at_ms:bigint:NO,updated_at_ms:bigint:NO',
  'Space core details have the exact lossless note and timestamp projection'
);

select is(
  (
    select string_agg(
      column_name || ':' || data_type || ':' || is_nullable,
      ',' order by ordinal_position
    )
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'spike_space_checklists'
  ),
  'id:text:NO,account_id:text:NO,space_id:text:NO,checklist_id:text:NO,name:text:NO,presentation_order:bigint:NO',
  'Space checklists separate provider identity from scoped domain identity'
);

select is(
  (
    select string_agg(
      column_name || ':' || data_type || ':' || is_nullable,
      ',' order by ordinal_position
    )
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'spike_space_checklist_items'
  ),
  'id:text:NO,account_id:text:NO,space_id:text:NO,checklist_id:text:NO,item_id:text:NO,item_text:text:NO,is_checked:boolean:NO,presentation_order:bigint:NO',
  'Space checklist items preserve scoped identity, exact text, checked state, and order'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.spike_space_core_details'::regclass
      and conname = 'spike_space_core_details_pkey'
      and contype = 'p'
  ),
  'one detail row is keyed by the stable Space identity'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.spike_space_checklists'::regclass
      and conname = 'spike_space_checklists_pkey'
      and contype = 'p'
  ),
  'each checklist has a distinct provider row identity'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.spike_space_checklist_items'::regclass
      and conname = 'spike_space_checklist_items_pkey'
      and contype = 'p'
  ),
  'each checklist item has a distinct provider row identity'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.spike_space_core_details'::regclass
      and conname = 'spike_space_core_details_space_scope_fkey'
      and contype = 'f'
      and pg_get_constraintdef(oid) like
        'FOREIGN KEY (account_id, id) REFERENCES spike_spaces(account_id, id) ON DELETE CASCADE%'
  ),
  'the detail parent is exact Account and Space scope'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.spike_space_checklists'::regclass
      and conname = 'spike_space_checklists_space_scope_fkey'
      and contype = 'f'
      and pg_get_constraintdef(oid) like
        'FOREIGN KEY (account_id, space_id) REFERENCES spike_spaces(account_id, id) ON DELETE CASCADE%'
  ),
  'every checklist has an exact same-Account Space parent'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.spike_space_checklist_items'::regclass
      and conname = 'spike_space_checklist_items_checklist_scope_fkey'
      and contype = 'f'
      and pg_get_constraintdef(oid) like
        'FOREIGN KEY (account_id, space_id, checklist_id) REFERENCES spike_space_checklists(account_id, space_id, checklist_id) ON DELETE CASCADE%'
  ),
  'every checklist item has an exact same-Account Space and checklist parent'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.spike_space_checklists'::regclass
      and conname = 'spike_space_checklists_domain_identity_key'
      and contype = 'u'
  ),
  'checklist domain identity is unique within one Space'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.spike_space_checklists'::regclass
      and conname = 'spike_space_checklists_presentation_order_key'
      and contype = 'u'
  ),
  'checklist presentation order is unique within one Space'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.spike_space_checklist_items'::regclass
      and conname = 'spike_space_checklist_items_domain_identity_key'
      and contype = 'u'
  ),
  'item domain identity is unique only within one checklist'
);

select ok(
  exists (
    select 1 from pg_constraint
    where conrelid = 'public.spike_space_checklist_items'::regclass
      and conname = 'spike_space_checklist_items_presentation_order_key'
      and contype = 'u'
  ),
  'item presentation order is unique within one checklist'
);

select ok(
  pg_get_indexdef('public.spike_space_core_details_scope_idx'::regclass)
    like '%(account_id, id)',
  'the exact detail scope lookup is indexed'
);

select ok(
  pg_get_indexdef('public.spike_space_checklists_scope_order_idx'::regclass)
    like '%(account_id, space_id, presentation_order, id)',
  'the exact Space checklist order lookup is indexed'
);

select ok(
  pg_get_indexdef('public.spike_space_checklist_items_scope_order_idx'::regclass)
    like '%(account_id, space_id, checklist_id, presentation_order, id)',
  'the exact checklist-item order lookup is indexed'
);

select ok(
  not exists (
    select 1
    from information_schema.columns
    where table_schema = 'public'
      and table_name in (
        'spike_space_core_details',
        'spike_space_checklists',
        'spike_space_checklist_items'
      )
      and (
        data_type in ('json', 'jsonb')
        or column_name in (
          'is_complete', 'completed_count', 'total_count',
          'progress', 'progress_percent', 'percentage'
        )
      )
  ),
  'no opaque hierarchy or stored derived progress authority exists'
);

select is(
  (
    select count(*)
    from pg_class
    where oid in (
      'public.spike_space_core_details'::regclass,
      'public.spike_space_checklists'::regclass,
      'public.spike_space_checklist_items'::regclass
    )
      and relrowsecurity
  ),
  3::bigint,
  'RLS is enabled on every new relation'
);

select is(
  (
    select count(*)
    from pg_class
    where oid in (
      'public.spike_space_core_details'::regclass,
      'public.spike_space_checklists'::regclass,
      'public.spike_space_checklist_items'::regclass
    )
      and relforcerowsecurity
  ),
  3::bigint,
  'RLS is forced on every new relation'
);

select ok(
  not has_table_privilege(
    'authenticated', 'public.spike_space_core_details',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ),
  'authenticated has no direct detail relation privilege'
);

select ok(
  not has_table_privilege(
    'authenticated', 'public.spike_space_checklists',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ),
  'authenticated has no direct checklist relation privilege'
);

select ok(
  not has_table_privilege(
    'authenticated', 'public.spike_space_checklist_items',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ),
  'authenticated has no direct checklist-item relation privilege'
);

select ok(
  not has_table_privilege(
    'anon', 'public.spike_space_core_details',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  )
  and not has_table_privilege(
    'anon', 'public.spike_space_checklists',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  )
  and not has_table_privilege(
    'anon', 'public.spike_space_checklist_items',
    'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ),
  'anonymous has no read or write privilege on any new relation'
);

select ok(
  not exists (
    select 1
    from pg_class as relation
    cross join lateral aclexplode(
      coalesce(relation.relacl, acldefault('r', relation.relowner))
    ) as privilege
    where relation.oid in (
      'public.spike_space_core_details'::regclass,
      'public.spike_space_checklists'::regclass,
      'public.spike_space_checklist_items'::regclass
    )
      and privilege.grantee = 0
      and privilege.privilege_type in (
        'SELECT', 'INSERT', 'UPDATE', 'DELETE',
        'TRUNCATE', 'REFERENCES', 'TRIGGER'
      )
  ),
  'PUBLIC has no direct read or write privilege on the new relations'
);

select is(
  (
    select count(*)
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'spike_space_core_details',
        'spike_space_checklists',
        'spike_space_checklist_items'
      )
  ),
  3::bigint,
  'each new relation has exactly one policy'
);

select is(
  (
    select count(*)
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'spike_space_core_details',
        'spike_space_checklists',
        'spike_space_checklist_items'
      )
      and cmd = 'SELECT'
      and roles = array['authenticated']::name[]
      and qual like '%has_active_membership%account_id%'
      and qual not like '%lifecycle%'
  ),
  3::bigint,
  'all new policies require active membership without filtering Space or Project lifecycle'
);

select ok(
  not exists (
    select 1
    from pg_policies
    where schemaname = 'public'
      and tablename in (
        'spike_space_core_details',
        'spike_space_checklists',
        'spike_space_checklist_items'
      )
      and cmd <> 'SELECT'
  ),
  'no client write policy exists'
);

select ok(
  not exists (
    select 1
    from information_schema.triggers
    where event_object_schema = 'public'
      and event_object_table in (
        'spike_space_core_details',
        'spike_space_checklists',
        'spike_space_checklist_items'
      )
  ),
  'no hidden trigger-based mutation surface exists'
);

select ok(
  not exists (
    select 1
    from pg_proc
    where pronamespace = 'public'::regnamespace
      and proname like 'spike%space%core%detail%'
  ),
  'no Space core-details RPC or handler exists'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values (
  '00000000-0000-0000-0000-000000000000',
  '10000000-0000-0000-0000-000000000007',
  'authenticated', 'authenticated', 'space-details-revoked@ledger-spike.invalid', '', now(),
  '{"provider":"email","providers":["email"]}', '{}', now(), now()
);

insert into public.spike_principals (id, auth_user_id)
values ('principal-space-details-revoked', '10000000-0000-0000-0000-000000000007');

insert into public.spike_account_memberships (
  account_id, principal_id, role, state, can_manage_clients,
  can_manage_projects, can_manage_project_budgets, financial_access
) values (
  'account-primary', 'principal-space-details-revoked', 'employee', 'removed',
  false, false, false, 'none'
);

insert into public.spike_clients (
  id, account_id, display_name, lifecycle, revision,
  created_at, updated_at, created_at_ms, updated_at_ms, created_by_principal_id
) values (
  'client-space-details-other', 'account-other', 'Other Detail Client', 'active', 1,
  '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
  1788609600000, 1788609600000, 'principal-other'
);

insert into public.spike_projects (
  id, account_id, client_id, display_name, lifecycle, revision,
  created_at, updated_at, created_at_ms, updated_at_ms,
  created_by_principal_id
) values
  (
    'project-space-details-active', 'account-primary', 'client-existing',
    'Active Space Details', 'active', 1,
    '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
    1788609600000, 1788609600000, 'principal-owner'
  ),
  (
    'project-space-details-archived', 'account-primary', 'client-existing',
    'Archived Space Details', 'archived', 2,
    '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
    1788609600000, 1788609600000, 'principal-owner'
  ),
  (
    'project-space-details-other', 'account-other', 'client-space-details-other',
    'Other Space Details', 'active', 1,
    '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
    1788609600000, 1788609600000, 'principal-other'
  );

-- The positional writes intentionally prove that the base still has seven columns.
insert into public.spike_spaces values
  ('space-details-main', 'account-primary', 'project',
   'project-space-details-active', 'Kitchen', 'active', 7),
  ('space-details-empty', 'account-primary', 'business_inventory',
   null, 'Empty Inventory', 'active', 8),
  ('space-details-empty-checklist', 'account-primary', 'business_inventory',
   null, 'Empty Checklist', 'active', 9),
  ('space-details-archived-project', 'account-primary', 'project',
   'project-space-details-archived', 'Archived Project Room', 'active', 10),
  ('space-details-archived', 'account-primary', 'project',
   'project-space-details-active', 'Archived Room', 'archived', 11),
  ('space-details-max-revision', 'account-primary', 'business_inventory',
   null, 'Maximum Revision', 'active', 9223372036854775807),
  ('space-details-other', 'account-other', 'project',
   'project-space-details-other', 'Other Room', 'active', 1),
  ('space-details-invalid-time-a', 'account-primary', 'business_inventory',
   null, 'Invalid Time A', 'active', 1),
  ('space-details-invalid-time-b', 'account-primary', 'business_inventory',
   null, 'Invalid Time B', 'active', 1),
  ('space-details-invalid-time-c', 'account-primary', 'business_inventory',
   null, 'Invalid Time C', 'active', 1),
  ('space-details-invalid-time-d', 'account-primary', 'business_inventory',
   null, 'Invalid Time D', 'active', 1),
  ('space-details-cross-account', 'account-primary', 'business_inventory',
   null, 'Cross Account', 'active', 1);

select is(
  (select revision from public.spike_spaces where id = 'space-details-max-revision'),
  9223372036854775807::bigint,
  'the full positive signed-bigint revision range remains representable'
);

select throws_ok(
  $$insert into public.spike_spaces values
    ('space-details-zero-revision', 'account-primary', 'business_inventory',
     null, 'Zero Revision', 'active', 0)$$,
  '23514', null,
  'zero revision evidence is rejected'
);

select throws_ok(
  $$insert into public.spike_spaces values
    ('space-details-overflow-revision', 'account-primary', 'business_inventory',
     null, 'Overflow Revision', 'active', 9223372036854775808)$$,
  '22003', null,
  'revision evidence above the signed-bigint boundary is rejected'
);

insert into public.spike_space_core_details (
  id, account_id, notes, created_at, updated_at, created_at_ms, updated_at_ms
) values
  (
    'space-details-main', 'account-primary', E'Café\nShelf  A',
    '2026-09-05T12:00:00.123Z', '2026-09-05T12:00:01.456Z',
    1788609600123, 1788609601456
  ),
  (
    'space-details-empty', 'account-primary', null,
    '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
    1788609600000, 1788609600000
  ),
  (
    'space-details-empty-checklist', 'account-primary', '',
    '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
    1788609600000, 1788609600000
  ),
  (
    'space-details-archived-project', 'account-primary', 'Still readable',
    '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
    1788609600000, 1788609600000
  ),
  (
    'space-details-archived', 'account-primary', 'Archived Space',
    '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
    1788609600000, 1788609600000
  ),
  (
    'space-details-max-revision', 'account-primary', null,
    '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
    1788609600000, 1788609600000
  ),
  (
    'space-details-other', 'account-other', 'Other Account',
    '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
    1788609600000, 1788609600000
  );

select is(
  (select notes from public.spike_space_core_details where id = 'space-details-main'),
  E'Café\nShelf  A',
  'accepted Unicode, newline, and interior spacing notes remain byte-exact'
);

select ok(
  (
    select created_at = '2026-09-05T12:00:00.123Z'::timestamptz
      and updated_at = '2026-09-05T12:00:01.456Z'::timestamptz
      and created_at_ms = 1788609600123
      and updated_at_ms = 1788609601456
    from public.spike_space_core_details
    where id = 'space-details-main'
  ),
  'exact finite timestamps and their millisecond evidence are preserved'
);

select throws_ok(
  $$insert into public.spike_space_core_details values
    ('space-details-cross-account', 'account-other', null,
     '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
     1788609600000, 1788609600000)$$,
  '23503', null,
  'a detail row cannot cross Account scope'
);

select throws_ok(
  $$insert into public.spike_space_core_details values
    ('space-details-invalid-time-a', 'account-primary', null,
     '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
     1788609600001, 1788609600000)$$,
  '23514', null,
  'a mismatched created-at millisecond value is rejected'
);

select throws_ok(
  $$insert into public.spike_space_core_details values
    ('space-details-invalid-time-b', 'account-primary', null,
     '2026-09-05T12:00:00.0001Z', '2026-09-05T12:00:00.001Z',
     1788609600000, 1788609600001)$$,
  '23514', null,
  'sub-millisecond timestamp evidence is rejected'
);

select lives_ok(
  $$insert into public.spike_space_core_details values
    ('space-details-invalid-time-c', 'account-primary', null,
     '2026-09-05T12:00:01Z', '2026-09-05T12:00:00Z',
     1788609601000, 1788609600000)$$,
  'exact record timestamps remain representable without inventing audit chronology'
);

delete from public.spike_space_core_details
where id = 'space-details-invalid-time-c';

select throws_ok(
  $$insert into public.spike_space_core_details values
    ('space-details-invalid-time-d', 'account-primary', null,
     'infinity', 'infinity', 0, 0)$$,
  '23514', null,
  'non-finite timestamp evidence is rejected'
);

insert into public.spike_space_checklists (
  id, account_id, space_id, checklist_id, name, presentation_order
) values
  (
    'checklist-row-main-a', 'account-primary', 'space-details-main',
    'checklist-a', E'Install\n List', 0
  ),
  (
    'checklist-row-main-b', 'account-primary', 'space-details-main',
    'checklist-b', 'Install  List', 4294967295
  ),
  (
    'checklist-row-empty', 'account-primary', 'space-details-empty-checklist',
    'checklist-empty', 'No Tasks Yet', 0
  );

insert into public.spike_space_checklist_items (
  id, account_id, space_id, checklist_id,
  item_id, item_text, is_checked, presentation_order
) values
  (
    'item-row-main-a', 'account-primary', 'space-details-main', 'checklist-a',
    'item-shared', E'Connect\n lamp', true, 0
  ),
  (
    'item-row-main-b', 'account-primary', 'space-details-main', 'checklist-b',
    'item-shared', 'Connect  lamp', false, 4294967295
  );

select is(
  (
    select string_agg(
      checklist_id || ':' || presentation_order::text,
      ',' order by presentation_order, id
    )
    from public.spike_space_checklists
    where account_id = 'account-primary' and space_id = 'space-details-main'
  ),
  'checklist-a:0,checklist-b:4294967295',
  'checklist order accepts and preserves both UInt32 boundaries'
);

select is(
  (
    select string_agg(
      checklist_id || ':' || item_id || ':' || is_checked::text || ':' || presentation_order::text,
      ',' order by checklist_id, presentation_order, id
    )
    from public.spike_space_checklist_items
    where account_id = 'account-primary' and space_id = 'space-details-main'
  ),
  'checklist-a:item-shared:true:0,checklist-b:item-shared:false:4294967295',
  'the same item ID is valid in different checklists with exact checked state and UInt32 order'
);

select is(
  (
    select count(*)
    from public.spike_space_checklists
    where account_id = 'account-primary' and space_id = 'space-details-empty'
  ),
  0::bigint,
  'a Space with zero checklists is valid'
);

select is(
  (
    select count(*)
    from public.spike_space_checklist_items
    where account_id = 'account-primary'
      and space_id = 'space-details-empty-checklist'
      and checklist_id = 'checklist-empty'
  ),
  0::bigint,
  'a checklist with zero items is valid'
);

select throws_ok(
  $$insert into public.spike_space_checklists values
    ('checklist-row-cross-account', 'account-other', 'space-details-main',
     'checklist-cross-account', 'Invalid', 2)$$,
  '23503', null,
  'a checklist cannot cross Account scope'
);

select throws_ok(
  $$insert into public.spike_space_checklists values
    ('checklist-row-domain-duplicate', 'account-primary', 'space-details-main',
     'checklist-a', 'Duplicate Identity', 2)$$,
  '23505', null,
  'a checklist domain identity cannot repeat within one Space'
);

select throws_ok(
  $$insert into public.spike_space_checklists values
    ('checklist-row-order-duplicate', 'account-primary', 'space-details-main',
     'checklist-c', 'Duplicate Order', 0)$$,
  '23505', null,
  'a checklist presentation order cannot repeat within one Space'
);

select throws_ok(
  $$insert into public.spike_space_checklists values
    ('checklist-row-negative-order', 'account-primary', 'space-details-empty',
     'checklist-negative', 'Invalid Order', -1)$$,
  '23514', null,
  'negative checklist order is rejected'
);

select throws_ok(
  $$insert into public.spike_space_checklists values
    ('checklist-row-overflow-order', 'account-primary', 'space-details-empty',
     'checklist-overflow', 'Invalid Order', 4294967296)$$,
  '23514', null,
  'checklist order above UInt32 maximum is rejected'
);

select throws_ok(
  $$insert into public.spike_space_checklists values
    ('invalid checklist row', 'account-primary', 'space-details-empty',
     'checklist-valid', 'Invalid Provider ID', 1)$$,
  '23514', null,
  'malformed checklist provider identity is rejected'
);

select throws_ok(
  $$insert into public.spike_space_checklists values
    ('checklist-row-invalid-domain', 'account-primary', 'space-details-empty',
     'invalid checklist id', 'Invalid Domain ID', 1)$$,
  '23514', null,
  'malformed checklist domain identity is rejected'
);

select throws_ok(
  $$insert into public.spike_space_checklist_items values
    ('item-row-cross-account', 'account-other', 'space-details-main', 'checklist-a',
     'item-cross-account', 'Invalid', false, 2)$$,
  '23503', null,
  'a checklist item cannot cross Account or Space scope'
);

select throws_ok(
  $$insert into public.spike_space_checklist_items values
    ('item-row-domain-duplicate', 'account-primary', 'space-details-main', 'checklist-a',
     'item-shared', 'Duplicate Identity', false, 1)$$,
  '23505', null,
  'an item domain identity cannot repeat within one checklist'
);

select throws_ok(
  $$insert into public.spike_space_checklist_items values
    ('item-row-order-duplicate', 'account-primary', 'space-details-main', 'checklist-a',
     'item-other', 'Duplicate Order', false, 0)$$,
  '23505', null,
  'an item presentation order cannot repeat within one checklist'
);

select throws_ok(
  $$insert into public.spike_space_checklist_items values
    ('item-row-negative-order', 'account-primary', 'space-details-empty-checklist',
     'checklist-empty', 'item-negative', 'Invalid Order', false, -1)$$,
  '23514', null,
  'negative item order is rejected'
);

select throws_ok(
  $$insert into public.spike_space_checklist_items values
    ('item-row-overflow-order', 'account-primary', 'space-details-empty-checklist',
     'checklist-empty', 'item-overflow', 'Invalid Order', false, 4294967296)$$,
  '23514', null,
  'item order above UInt32 maximum is rejected'
);

select throws_ok(
  $$insert into public.spike_space_checklist_items values
    ('invalid item row', 'account-primary', 'space-details-empty-checklist',
     'checklist-empty', 'item-valid', 'Invalid Provider ID', false, 1)$$,
  '23514', null,
  'malformed item provider identity is rejected'
);

select throws_ok(
  $$insert into public.spike_space_checklist_items values
    ('item-row-invalid-domain', 'account-primary', 'space-details-empty-checklist',
     'checklist-empty', 'invalid item id', 'Invalid Domain ID', false, 1)$$,
  '23514', null,
  'malformed item domain identity is rejected'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select throws_ok(
  $$select count(*) from public.spike_space_core_details$$,
  '42501', 'permission denied for table spike_space_core_details',
  'authenticated callers have no direct detail Data API surface'
);

select throws_ok(
  $$insert into public.spike_space_checklists values
    ('checklist-row-direct', 'account-primary', 'space-details-empty',
     'checklist-direct', 'Direct', 1)$$,
  '42501', 'permission denied for table spike_space_checklists',
  'authenticated callers cannot directly insert checklist rows'
);

select throws_ok(
  $$update public.spike_space_checklist_items
    set is_checked = false where id = 'item-row-main-a'$$,
  '42501', 'permission denied for table spike_space_checklist_items',
  'authenticated callers cannot directly update checklist-item rows'
);

select throws_ok(
  $$delete from public.spike_space_core_details where id = 'space-details-main'$$,
  '42501', 'permission denied for table spike_space_core_details',
  'authenticated callers cannot directly delete detail rows'
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
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select is(
  (
    select string_agg(id, ',' order by id)
    from public.spike_space_core_details
    where id like 'space-details-%'
  ),
  'space-details-archived,space-details-archived-project,space-details-empty,space-details-empty-checklist,space-details-main,space-details-max-revision',
  'an active member reads exact Account details including active and archived Spaces'
);

select is(
  (
    select count(*)
    from public.spike_spaces
    where id = 'space-details-archived-project'
  ),
  1::bigint,
  'an active Space remains readable beneath an archived Project'
);

select is(
  (
    select count(*)
    from public.spike_spaces
    where id = 'space-details-archived'
  ),
  0::bigint,
  'the existing destination policy still hides archived Spaces'
);

select is(
  (
    select count(*)
    from public.spike_space_checklists
    where account_id = 'account-primary'
  ),
  3::bigint,
  'the active member reads the complete Account-scoped checklist hierarchy'
);

select is(
  (
    select count(*)
    from public.spike_space_checklist_items
    where account_id = 'account-primary'
  ),
  2::bigint,
  'the active member reads the complete Account-scoped checklist-item hierarchy'
);

select is(
  (
    select count(*)
    from public.spike_space_core_details
    where account_id = 'account-other'
  ),
  0::bigint,
  'caller-supplied cross-Account scope cannot broaden detail visibility'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select is(
  (
    select count(*)
    from public.spike_space_core_details
    where id like 'space-details-%'
  ),
  6::bigint,
  'another active non-financial member reads the same non-accounting details'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
select is(
  (select string_agg(id, ',' order by id) from public.spike_space_core_details),
  'space-details-other',
  'an active member of another Account sees only that Account detail row'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000007","role":"authenticated"}',
  true
);
select is(
  (select count(*) from public.spike_space_core_details),
  0::bigint,
  'a revoked member cannot read Space detail rows'
);

select is(
  (select count(*) from public.spike_space_checklists),
  0::bigint,
  'a revoked member cannot read Space checklist rows'
);

select is(
  (select count(*) from public.spike_space_checklist_items),
  0::bigint,
  'a revoked member cannot read Space checklist-item rows'
);

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select throws_ok(
  $$select count(*) from public.spike_space_core_details$$,
  '42501', 'permission denied for table spike_space_core_details',
  'anonymous callers cannot enumerate Space details'
);

reset role;
revoke select on table
  public.spike_space_core_details,
  public.spike_space_checklists,
  public.spike_space_checklist_items
from authenticated;

select ok(
  not has_table_privilege('authenticated', 'public.spike_space_core_details', 'SELECT')
  and not has_table_privilege('authenticated', 'public.spike_space_checklists', 'SELECT')
  and not has_table_privilege('authenticated', 'public.spike_space_checklist_items', 'SELECT'),
  'temporary policy probes leave no client read grant in the intended final state'
);

select * from finish();

rollback;
