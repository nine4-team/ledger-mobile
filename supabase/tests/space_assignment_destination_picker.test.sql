begin;
select plan(34);

select ok(
  to_regclass('public.spike_spaces') is not null,
  'the isolated Space destination relation exists'
);

select is(
  (
    select string_agg(
      column_name || ':' || data_type || ':' || is_nullable,
      ',' order by ordinal_position
    )
    from information_schema.columns
    where table_schema = 'public'
      and table_name = 'spike_spaces'
      and column_name in (
        'id', 'account_id', 'scope_kind', 'project_id',
        'display_name', 'lifecycle', 'revision'
      )
  ),
  'id:text:NO,account_id:text:NO,scope_kind:text:NO,project_id:text:YES,display_name:text:NO,lifecycle:text:NO,revision:bigint:NO',
  'the relation exposes the required typed destination projection'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.spike_spaces'::regclass
      and conname = 'spike_spaces_pkey'
      and contype = 'p'
  ),
  'stable Space identity is the primary key'
);

select ok(
  exists (
    select 1
    from pg_constraint
    where conrelid = 'public.spike_spaces'::regclass
      and conname = 'spike_spaces_project_scope_fkey'
      and contype = 'f'
      and pg_get_constraintdef(oid) like
        'FOREIGN KEY (account_id, project_id) REFERENCES spike_projects(account_id, id)%'
  ),
  'Project scope has an exact same-Account composite relationship'
);

select ok(
  (select relrowsecurity from pg_class where oid = 'public.spike_spaces'::regclass),
  'row-level security is enabled'
);

select ok(
  has_table_privilege('authenticated', 'public.spike_spaces', 'SELECT'),
  'authenticated has the required SELECT grant'
);

select ok(
  not has_table_privilege(
    'authenticated',
    'public.spike_spaces',
    'INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER'
  ),
  'authenticated has no direct write or schema-adjacent table privilege'
);

select ok(
  not has_table_privilege('anon', 'public.spike_spaces', 'SELECT,INSERT,UPDATE,DELETE'),
  'anon has no Space destination table privilege'
);

select ok(
  not exists (
    select 1
    from pg_class as relation
    cross join lateral aclexplode(
      coalesce(relation.relacl, acldefault('r', relation.relowner))
    ) as privilege
    where relation.oid = 'public.spike_spaces'::regclass
      and privilege.grantee = 0
      and privilege.privilege_type in ('SELECT', 'INSERT', 'UPDATE', 'DELETE')
  ),
  'PUBLIC has no direct read or write privilege'
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
  'the sole read policy requires active lifecycle and active Account membership'
);

select is(
  (select count(*) from pg_policies where schemaname = 'public' and tablename = 'spike_spaces'),
  1::bigint,
  'no write policy or alternate read policy exists'
);

select ok(
  pg_get_indexdef('public.spike_spaces_assignment_destination_order_idx'::regclass)
    like '%(account_id, scope_kind, project_id, lifecycle, lower(display_name) COLLATE "C", display_name COLLATE "C", id)',
  'the exact scope and canonical-order lookup index exists'
);

select ok(
  pg_get_indexdef('public.spike_spaces_project_id_idx'::regclass)
    like '%(project_id, account_id) WHERE (project_id IS NOT NULL)',
  'the conditional Project relationship has a deterministic lookup index'
);

select ok(
  pg_get_indexdef('public.spike_spaces_project_scope_fk_idx'::regclass)
    like '%(account_id, project_id)',
  'the same-Account Project foreign key has a covering index'
);

insert into auth.users (
  instance_id, id, aud, role, email, encrypted_password, email_confirmed_at,
  raw_app_meta_data, raw_user_meta_data, created_at, updated_at
) values
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000004',
    'authenticated', 'authenticated', 'space-admin@ledger-spike.invalid', '', now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000005',
    'authenticated', 'authenticated', 'space-revoked@ledger-spike.invalid', '', now(),
    '{"provider":"email","providers":["email"]}', '{}', now(), now()
  );

insert into public.spike_principals (id, auth_user_id) values
  ('principal-space-admin', '10000000-0000-0000-0000-000000000004'),
  ('principal-space-revoked', '10000000-0000-0000-0000-000000000005');

insert into public.spike_account_memberships (
  account_id, principal_id, role, state, can_manage_clients,
  can_manage_projects, can_manage_project_budgets, financial_access
) values
  ('account-primary', 'principal-space-admin', 'admin', 'active', false, false, false, 'none'),
  ('account-primary', 'principal-space-revoked', 'employee', 'removed', false, false, false, 'none');

insert into public.spike_clients (
  id, account_id, display_name, lifecycle, revision, created_at, updated_at,
  created_at_ms, updated_at_ms, created_by_principal_id
) values (
  'client-space-other', 'account-other', 'Other Space Client', 'active', 1,
  '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
  1788609600000, 1788609600000, 'principal-other'
);

insert into public.spike_projects (
  id, account_id, client_id, display_name, lifecycle, revision,
  created_at, updated_at, created_at_ms, updated_at_ms,
  created_by_principal_id
) values
  (
    'project-space-primary', 'account-primary', 'client-existing',
    'Primary Space Project', 'active', 1,
    '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
    1788609600000, 1788609600000, 'principal-owner'
  ),
  (
    'project-space-other', 'account-other', 'client-space-other',
    'Other Space Project', 'active', 1,
    '2026-09-05T12:00:00Z', '2026-09-05T12:00:00Z',
    1788609600000, 1788609600000, 'principal-other'
  );

insert into public.spike_spaces (
  id, account_id, scope_kind, project_id, display_name, lifecycle, revision
) values
  ('space-kitchen', 'account-primary', 'project', 'project-space-primary', 'Kitchen', 'active', 7),
  ('space-loft-uppercase', 'account-primary', 'project', 'project-space-primary', 'Loft', 'active', 8),
  ('space-loft-a', 'account-primary', 'project', 'project-space-primary', 'loft', 'active', 9),
  ('space-loft-z', 'account-primary', 'project', 'project-space-primary', 'loft', 'active', 10),
  ('space-inventory', 'account-primary', 'business_inventory', null, 'Café 棚', 'active', 41),
  ('space-archived', 'account-primary', 'project', 'project-space-primary', 'Archived', 'archived', 42),
  ('space-other-project', 'account-other', 'project', 'project-space-other', 'Other Project', 'active', 2),
  ('space-other-inventory', 'account-other', 'business_inventory', null, 'Other Inventory', 'active', 3);

select is(
  (select display_name from public.spike_spaces where id = 'space-inventory'),
  'Café 棚',
  'normalized representable display text is preserved byte-for-byte'
);

select throws_ok(
  $$insert into public.spike_spaces values
    ('space-project-null', 'account-primary', 'project', null, 'Invalid', 'active', 1)$$,
  '23514', null,
  'Project scope requires a Project ID'
);

select throws_ok(
  $$insert into public.spike_spaces values
    ('space-inventory-project', 'account-primary', 'business_inventory',
     'project-space-primary', 'Invalid', 'active', 1)$$,
  '23514', null,
  'Business Inventory scope forbids a synthetic Project ID'
);

select throws_ok(
  $$insert into public.spike_spaces values
    ('space-cross-account-project', 'account-other', 'project',
     'project-space-primary', 'Invalid', 'active', 1)$$,
  '23503', null,
  'a Project relationship cannot cross Account scope'
);

select throws_ok(
  $$insert into public.spike_spaces values
    ('space-bad-lifecycle', 'account-primary', 'business_inventory', null,
     'Invalid', 'deleted', 1)$$,
  '23514', null,
  'unknown lifecycle state is rejected'
);

select throws_ok(
  $$insert into public.spike_spaces values
    ('space-zero-revision', 'account-primary', 'business_inventory', null,
     'Invalid', 'active', 0)$$,
  '23514', null,
  'revision must be positive'
);

select throws_ok(
  $$insert into public.spike_spaces values
    ('space-uncanonical-name', 'account-primary', 'business_inventory', null,
     ' Leading', 'active', 1)$$,
  '23514', null,
  'noncanonical exterior display whitespace is rejected'
);

select throws_ok(
  $$insert into public.spike_spaces values
    ('invalid space id', 'account-primary', 'business_inventory', null,
     'Invalid', 'active', 1)$$,
  '23514', null,
  'unstable Space identity is rejected'
);

set local role authenticated;
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);

select is(
  (
    select string_agg(
      id,
      ',' order by lower(display_name) collate "C", display_name collate "C", id
    )
    from public.spike_spaces
    where account_id = 'account-primary'
      and scope_kind = 'project'
      and project_id = 'project-space-primary'
  ),
  'space-kitchen,space-loft-uppercase,space-loft-a,space-loft-z',
  'an active owner reads exact active Project destinations in deterministic order'
);

select is(
  (select count(*) from public.spike_spaces where account_id = 'account-primary'),
  5::bigint,
  'the owner sees active Project and Business Inventory rows but not archived rows'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000004","role":"authenticated"}',
  true
);
select is(
  (select count(*) from public.spike_spaces where account_id = 'account-primary'),
  5::bigint,
  'an active admin reads the non-financial Space directory without mutation capability'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000002","role":"authenticated"}',
  true
);
select is(
  (select count(*) from public.spike_spaces where account_id = 'account-primary'),
  5::bigint,
  'an active employee reads the same non-financial Space directory'
);
select is(
  (select count(*) from public.spike_spaces where id = 'space-archived'),
  0::bigint,
  'archived Space rows are non-enumerable for every active member role'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000003","role":"authenticated"}',
  true
);
select is(
  (select string_agg(id, ',' order by id) from public.spike_spaces),
  'space-other-inventory,space-other-project',
  'an active member sees only their own Account Space rows'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000005","role":"authenticated"}',
  true
);
select is(
  (select count(*) from public.spike_spaces),
  0::bigint,
  'a revoked member cannot enumerate Space rows'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',
  true
);
select is(
  (select count(*) from public.spike_spaces where account_id = 'account-other'),
  0::bigint,
  'caller-supplied cross-Account scope cannot broaden server visibility'
);

select throws_ok(
  $$insert into public.spike_spaces values
    ('space-direct', 'account-primary', 'business_inventory', null, 'Direct', 'active', 1)$$,
  '42501', 'permission denied for table spike_spaces',
  'authenticated cannot directly insert a Space'
);
select throws_ok(
  $$update public.spike_spaces set display_name = 'Changed' where id = 'space-kitchen'$$,
  '42501', 'permission denied for table spike_spaces',
  'authenticated cannot directly update a Space'
);
select throws_ok(
  $$delete from public.spike_spaces where id = 'space-kitchen'$$,
  '42501', 'permission denied for table spike_spaces',
  'authenticated cannot directly delete a Space'
);

set local role anon;
select set_config('request.jwt.claims', '{"role":"anon"}', true);
select throws_ok(
  $$select count(*) from public.spike_spaces$$,
  '42501', 'permission denied for table spike_spaces',
  'anonymous callers cannot enumerate Spaces'
);

select * from finish();
rollback;
