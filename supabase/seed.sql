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
  can_manage_clients
) values
  ('account-primary', 'principal-owner', 'owner', 'active', true),
  ('account-primary', 'principal-restricted', 'employee', 'active', false),
  ('account-other', 'principal-other', 'owner', 'active', true);
