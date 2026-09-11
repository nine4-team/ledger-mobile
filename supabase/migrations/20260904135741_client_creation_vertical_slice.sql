create extension if not exists pgcrypto with schema extensions;

create schema if not exists ledger_private;
revoke all on schema ledger_private from public, anon, authenticated;

create table public.spike_principals (
  id text primary key
    check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'),
  auth_user_id uuid not null unique references auth.users(id) on delete cascade,
  created_at timestamptz not null default statement_timestamp()
);

create table public.spike_accounts (
  id text primary key
    check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'),
  display_name text not null check (btrim(display_name) <> ''),
  created_at timestamptz not null default statement_timestamp()
);

create table public.spike_account_memberships (
  account_id text not null references public.spike_accounts(id) on delete cascade,
  principal_id text not null references public.spike_principals(id) on delete cascade,
  role text not null check (role in ('owner', 'admin', 'employee')),
  state text not null check (state in ('active', 'removed')),
  can_manage_clients boolean not null default false,
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  primary key (account_id, principal_id),
  check (created_at <= updated_at)
);

create index spike_account_memberships_principal_active_idx
  on public.spike_account_memberships (principal_id, account_id)
  where state = 'active';

create index spike_account_memberships_principal_idx
  on public.spike_account_memberships (principal_id, account_id);

create table public.spike_clients (
  id text primary key
    check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'),
  account_id text not null references public.spike_accounts(id) on delete cascade,
  display_name text not null check (btrim(display_name) <> ''),
  lifecycle text not null default 'active' check (lifecycle in ('active', 'archived')),
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  created_at_ms bigint not null,
  updated_at_ms bigint not null,
  created_by_principal_id text not null references public.spike_principals(id),
  check (created_at <= updated_at),
  check (created_at_ms <= updated_at_ms),
  unique (account_id, id)
);

create index spike_clients_account_lifecycle_name_idx
  on public.spike_clients (account_id, lifecycle, lower(display_name), id);

create index spike_clients_created_by_principal_idx
  on public.spike_clients (created_by_principal_id);

create table public.spike_operation_results (
  operation_id text primary key
    check (operation_id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'),
  account_id text not null references public.spike_accounts(id) on delete cascade,
  actor_principal_id text not null references public.spike_principals(id),
  command_type text not null check (command_type = 'create_client'),
  contract_version text not null,
  command_fingerprint text not null check (command_fingerprint ~ '^[0-9a-f]{64}$'),
  envelope_sha256 text not null check (envelope_sha256 ~ '^[0-9a-f]{64}$'),
  subject_id text not null,
  phase text not null check (phase in ('applied', 'rejected')),
  result_code text,
  error_code text,
  client_created_at timestamptz not null,
  server_received_at timestamptz not null,
  completed_at timestamptz not null,
  client_created_at_ms bigint not null,
  server_received_at_ms bigint not null,
  completed_at_ms bigint not null,
  check (server_received_at <= completed_at),
  check (server_received_at_ms <= completed_at_ms),
  check (
    (phase = 'applied' and result_code is not null and error_code is null)
    or
    (phase = 'rejected' and result_code is null and error_code is not null)
  )
);

create index spike_operation_results_account_updated_idx
  on public.spike_operation_results (account_id, completed_at desc, operation_id);

create index spike_operation_results_actor_principal_idx
  on public.spike_operation_results (actor_principal_id);

alter table public.spike_principals enable row level security;
alter table public.spike_accounts enable row level security;
alter table public.spike_account_memberships enable row level security;
alter table public.spike_clients enable row level security;
alter table public.spike_operation_results enable row level security;

revoke all on table
  public.spike_principals,
  public.spike_accounts,
  public.spike_account_memberships,
  public.spike_clients,
  public.spike_operation_results
from public, anon, authenticated;

grant select on table
  public.spike_principals,
  public.spike_accounts,
  public.spike_account_memberships,
  public.spike_clients,
  public.spike_operation_results
to authenticated;

create function ledger_private.current_principal_id()
returns text
language sql
stable
security definer
set search_path = ''
as $$
  select principal.id
  from public.spike_principals as principal
  where principal.auth_user_id = (select auth.uid())
$$;

create function ledger_private.has_active_membership(
  requested_account_id text,
  require_client_management boolean default false
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (
    select 1
    from public.spike_account_memberships as membership
    join public.spike_principals as principal
      on principal.id = membership.principal_id
    where principal.auth_user_id = (select auth.uid())
      and membership.account_id = requested_account_id
      and membership.state = 'active'
      and (
        not require_client_management
        or membership.can_manage_clients
      )
  )
$$;

revoke all on function ledger_private.current_principal_id() from public;
revoke all on function ledger_private.has_active_membership(text, boolean) from public;
grant usage on schema ledger_private to authenticated;
grant execute on function ledger_private.current_principal_id() to authenticated;
grant execute on function ledger_private.has_active_membership(text, boolean) to authenticated;

create policy spike_principals_select_self
on public.spike_principals
for select
to authenticated
using (auth_user_id = (select auth.uid()));

create policy spike_accounts_select_active_member
on public.spike_accounts
for select
to authenticated
using ((select ledger_private.has_active_membership(id)));

create policy spike_memberships_select_self
on public.spike_account_memberships
for select
to authenticated
using (
  principal_id = (select ledger_private.current_principal_id())
  and (select ledger_private.has_active_membership(account_id))
);

create policy spike_clients_select_active_member
on public.spike_clients
for select
to authenticated
using ((select ledger_private.has_active_membership(account_id)));

create policy spike_operation_results_select_active_member
on public.spike_operation_results
for select
to authenticated
using ((select ledger_private.has_active_membership(account_id)));

create function ledger_private.refuse_operation_result_mutation()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  raise exception using
    errcode = '55000',
    message = 'spike operation results are immutable';
end
$$;

revoke all on function ledger_private.refuse_operation_result_mutation() from public;

create trigger spike_operation_results_immutable
before update or delete on public.spike_operation_results
for each row execute function ledger_private.refuse_operation_result_mutation();

create function ledger_private.spike_create_client(
  p_operation_id text,
  p_account_id text,
  p_actor_principal_id text,
  p_contract_version text,
  p_client_created_at timestamptz,
  p_client_id text,
  p_display_name text,
  p_fingerprint text,
  p_envelope_json text
)
returns public.spike_operation_results
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_now timestamptz := date_trunc('milliseconds', clock_timestamp());
  v_now_ms bigint;
  v_envelope jsonb;
  v_envelope_client_created_at_ms bigint;
  v_envelope_sha256 text;
  v_existing public.spike_operation_results%rowtype;
  v_result public.spike_operation_results%rowtype;
  v_error_code text;
begin
  v_now_ms := floor(extract(epoch from v_now) * 1000)::bigint;
  if (select auth.uid()) is null then
    raise exception using errcode = '28000', message = 'authentication required';
  end if;

  if p_actor_principal_id is distinct from (
    select ledger_private.current_principal_id()
  ) then
    raise exception using errcode = '42501', message = 'actor is not the authenticated principal';
  end if;

  if not ledger_private.has_active_membership(p_account_id, true) then
    raise exception using errcode = '42501', message = 'active client-management membership required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_operation_id, 0)
  );

  select result.*
  into v_existing
  from public.spike_operation_results as result
  where result.operation_id = p_operation_id;

  if found then
    if v_existing.account_id is distinct from p_account_id
      or v_existing.actor_principal_id is distinct from p_actor_principal_id
      or v_existing.contract_version is distinct from p_contract_version
      or v_existing.command_fingerprint is distinct from p_fingerprint
      or v_existing.subject_id is distinct from p_client_id
    then
      raise exception using
        errcode = '23505',
        message = 'operation id is already bound to a different command';
    end if;
    return v_existing;
  end if;

  begin
    v_envelope := p_envelope_json::jsonb;
  exception when others then
    v_error_code := 'client_creation_command_encoding_invalid';
  end;

  v_envelope_sha256 := pg_catalog.encode(
    extensions.digest(pg_catalog.convert_to(p_envelope_json, 'UTF8'), 'sha256'),
    'hex'
  );

  if v_error_code is null and p_contract_version <> 'client-create-v1' then
    v_error_code := 'contract_unsupported';
  elsif v_error_code is null and (
    p_operation_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or p_account_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or p_actor_principal_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or p_client_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or p_fingerprint !~ '^[0-9a-f]{64}$'
    or not pg_catalog.isfinite(p_client_created_at)
    or btrim(p_display_name) = ''
  ) then
    v_error_code := 'client_creation_payload_invalid';
  elsif v_error_code is null and v_envelope_sha256 <> p_fingerprint then
    v_error_code := 'client_creation_fingerprint_mismatch';
  end if;

  if v_error_code is null then
    begin
      if pg_catalog.jsonb_typeof(v_envelope -> 'clientCreatedAt') <> 'number'
        or v_envelope ->> 'clientCreatedAt' !~ '^-?[0-9]+$'
      then
        v_error_code := 'client_creation_envelope_mismatch';
      else
        v_envelope_client_created_at_ms :=
          (v_envelope ->> 'clientCreatedAt')::bigint;
      end if;
    exception when numeric_value_out_of_range then
      v_error_code := 'client_creation_envelope_mismatch';
    end;
  end if;

  if v_error_code is null and (
    v_envelope ->> 'operationId' is distinct from p_operation_id
    or v_envelope ->> 'accountId' is distinct from p_account_id
    or v_envelope ->> 'actorPrincipalId' is distinct from p_actor_principal_id
    or v_envelope ->> 'contractVersion' is distinct from p_contract_version
    or v_envelope_client_created_at_ms is distinct from
      floor(extract(epoch from p_client_created_at) * 1000)::bigint
    or v_envelope #>> '{payload,clientId}' is distinct from p_client_id
    or v_envelope #>> '{payload,displayName}' is distinct from p_display_name
    or v_envelope -> 'preconditions' is distinct from '[]'::jsonb
  ) then
    v_error_code := 'client_creation_envelope_mismatch';
  end if;

  if v_error_code is null and exists (
    select 1 from public.spike_clients where id = p_client_id
  ) then
    v_error_code := 'client_creation_identity_conflict';
  end if;

  if v_error_code is null then
    insert into public.spike_clients (
      id,
      account_id,
      display_name,
      lifecycle,
      revision,
      created_at,
      updated_at,
      created_at_ms,
      updated_at_ms,
      created_by_principal_id
    ) values (
      p_client_id,
      p_account_id,
      p_display_name,
      'active',
      1,
      v_now,
      v_now,
      v_now_ms,
      v_now_ms,
      p_actor_principal_id
    );
  end if;

  insert into public.spike_operation_results (
    operation_id,
    account_id,
    actor_principal_id,
    command_type,
    contract_version,
    command_fingerprint,
    envelope_sha256,
    subject_id,
    phase,
    result_code,
    error_code,
    client_created_at,
    server_received_at,
    completed_at,
    client_created_at_ms,
    server_received_at_ms,
    completed_at_ms
  ) values (
    p_operation_id,
    p_account_id,
    p_actor_principal_id,
    'create_client',
    p_contract_version,
    p_fingerprint,
    v_envelope_sha256,
    p_client_id,
    case when v_error_code is null then 'applied' else 'rejected' end,
    case when v_error_code is null then 'client_created' end,
    v_error_code,
    p_client_created_at,
    v_now,
    v_now,
    floor(extract(epoch from p_client_created_at) * 1000)::bigint,
    v_now_ms,
    v_now_ms
  )
  returning * into v_result;

  return v_result;
end
$$;

revoke all on function ledger_private.spike_create_client(
  text, text, text, text, timestamptz, text, text, text, text
) from public;
grant execute on function ledger_private.spike_create_client(
  text, text, text, text, timestamptz, text, text, text, text
) to authenticated;

create function public.spike_create_client(
  p_operation_id text,
  p_account_id text,
  p_actor_principal_id text,
  p_contract_version text,
  p_client_created_at timestamptz,
  p_client_id text,
  p_display_name text,
  p_fingerprint text,
  p_envelope_json text
)
returns public.spike_operation_results
language sql
security invoker
set search_path = ''
as $$
  select ledger_private.spike_create_client(
    p_operation_id,
    p_account_id,
    p_actor_principal_id,
    p_contract_version,
    p_client_created_at,
    p_client_id,
    p_display_name,
    p_fingerprint,
    p_envelope_json
  )
$$;

revoke all on function public.spike_create_client(
  text, text, text, text, timestamptz, text, text, text, text
) from public, anon;
grant execute on function public.spike_create_client(
  text, text, text, text, timestamptz, text, text, text, text
) to authenticated;
