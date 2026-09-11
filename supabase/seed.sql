insert into auth.users (
  instance_id,
  id,
  aud,
  role,
  email,
  encrypted_password,
  email_confirmed_at,
  raw_app_meta_data,
  raw_user_meta_data,
  created_at,
  updated_at
) values
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000001',
    'authenticated',
    'authenticated',
    'owner@ledger-spike.invalid',
    '',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{}',
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000002',
    'authenticated',
    'authenticated',
    'restricted@ledger-spike.invalid',
    '',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{}',
    now(),
    now()
  ),
  (
    '00000000-0000-0000-0000-000000000000',
    '10000000-0000-0000-0000-000000000003',
    'authenticated',
    'authenticated',
    'other@ledger-spike.invalid',
    '',
    now(),
    '{"provider":"email","providers":["email"]}',
    '{}',
    now(),
    now()
  )
on conflict (id) do nothing;

insert into public.spike_principals (id, auth_user_id) values
  ('principal-owner', '10000000-0000-0000-0000-000000000001'),
  ('principal-restricted', '10000000-0000-0000-0000-000000000002'),
  ('principal-other', '10000000-0000-0000-0000-000000000003');

insert into public.spike_accounts (id, display_name) values
  ('account-primary', 'Synthetic Primary Account'),
  ('account-other', 'Synthetic Other Account');

insert into public.spike_account_memberships (
  account_id,
  principal_id,
  role,
  state,
  can_manage_clients,
  can_manage_projects,
  can_manage_project_budgets,
  financial_access
) values
  ('account-primary', 'principal-owner', 'owner', 'active', true, true, true, 'full'),
  ('account-primary', 'principal-restricted', 'employee', 'active', false, false, false, 'none'),
  ('account-other', 'principal-other', 'owner', 'active', true, true, true, 'full');

insert into public.spike_clients (
  id, account_id, display_name, lifecycle, revision, created_at, updated_at,
  created_at_ms, updated_at_ms, created_by_principal_id
) values (
  'client-existing', 'account-primary', 'Existing Client', 'active', 1,
  '2026-09-04T12:00:00Z', '2026-09-04T12:00:00Z',
  1788523200000, 1788523200000, 'principal-owner'
);

insert into public.spike_budget_categories (
  id, account_id, display_name, kind, lifecycle, is_system,
  excludes_from_overall_budget, visibility_class, presentation_order,
  revision, created_at_ms, updated_at_ms
) values
  (
    'category-furnishings', 'account-primary', 'Furnishings', 'itemized',
    'active', false, false, 'ordinary', 10, 1, 1788523200000, 1788523200000
  ),
  (
    'category-design-fee', 'account-primary', 'Design Fee', 'fee',
    'active', false, true, 'company_financial', 20, 1,
    1788523200000, 1788523200000
  ),
  (
    'category-system', 'account-primary', 'System', 'general',
    'active', true, false, 'ordinary', 30, 1, 1788523200000, 1788523200000
  );
