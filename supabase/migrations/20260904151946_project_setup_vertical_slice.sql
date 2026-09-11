alter table public.spike_account_memberships
  add column can_manage_projects boolean not null default false;

alter table public.spike_account_memberships
  add column can_manage_project_budgets boolean not null default false;

alter table public.spike_account_memberships
  add column financial_access text not null default 'none'
    check (financial_access in ('full', 'limited', 'none'));

update public.spike_account_memberships
set can_manage_projects = true,
    can_manage_project_budgets = true,
    financial_access = 'full'
where role in ('owner', 'admin') and state = 'active';

alter table public.spike_operation_results
  drop constraint spike_operation_results_command_type_check;

alter table public.spike_operation_results
  add constraint spike_operation_results_command_type_check
  check (command_type in ('create_client', 'create_project'));

create table public.spike_budget_categories (
  id text primary key
    check (
      id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
      and octet_length(id) <= 128
    ),
  account_id text not null references public.spike_accounts(id) on delete cascade,
  display_name text not null check (btrim(display_name) <> ''),
  kind text not null check (kind in ('general', 'itemized', 'fee')),
  lifecycle text not null default 'active' check (lifecycle in ('active', 'archived')),
  is_system boolean not null default false,
  excludes_from_overall_budget boolean not null default false,
  visibility_class text not null default 'ordinary'
    check (visibility_class in ('ordinary', 'company_financial')),
  presentation_order bigint not null check (presentation_order between 0 and 4294967295),
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default statement_timestamp(),
  updated_at timestamptz not null default statement_timestamp(),
  created_at_ms bigint not null,
  updated_at_ms bigint not null,
  unique (account_id, id),
  unique (account_id, presentation_order),
  check (created_at <= updated_at),
  check (created_at_ms <= updated_at_ms)
);

create unique index spike_budget_categories_account_name_idx
  on public.spike_budget_categories (account_id, lower(display_name));

create index spike_budget_categories_account_lifecycle_order_idx
  on public.spike_budget_categories (
    account_id,
    lifecycle,
    is_system,
    presentation_order,
    id
  );

create table public.spike_projects (
  id text primary key
    check (
      id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
      and octet_length(id) <= 128
    ),
  account_id text not null references public.spike_accounts(id) on delete cascade,
  client_id text not null,
  display_name text not null check (btrim(display_name) <> ''),
  description text,
  lifecycle text not null default 'active' check (lifecycle in ('active', 'archived')),
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  created_at_ms bigint not null,
  updated_at_ms bigint not null,
  created_by_principal_id text not null references public.spike_principals(id),
  unique (account_id, id),
  foreign key (account_id, client_id)
    references public.spike_clients(account_id, id),
  check (description is null or description <> ''),
  check (created_at <= updated_at),
  check (created_at_ms <= updated_at_ms)
);

create index spike_projects_account_lifecycle_name_idx
  on public.spike_projects (account_id, lifecycle, lower(display_name), id);

create index spike_projects_account_client_idx
  on public.spike_projects (account_id, client_id, lifecycle, id);

create index spike_projects_created_by_principal_idx
  on public.spike_projects (created_by_principal_id);

create table public.spike_project_category_allocations (
  id text primary key default gen_random_uuid()::text,
  account_id text not null,
  project_id text not null,
  category_id text not null,
  allocation_minor_units bigint,
  allocation_currency text,
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null,
  updated_at timestamptz not null,
  created_at_ms bigint not null,
  updated_at_ms bigint not null,
  created_by_principal_id text not null references public.spike_principals(id),
  unique (project_id, category_id),
  foreign key (account_id, project_id)
    references public.spike_projects(account_id, id) on delete cascade,
  foreign key (account_id, category_id)
    references public.spike_budget_categories(account_id, id),
  check (
    (allocation_minor_units is null and allocation_currency is null)
    or
    (
      allocation_minor_units is not null
      and allocation_minor_units >= 0
      and allocation_currency ~ '^[A-Z]{3}$'
    )
  ),
  check (created_at <= updated_at),
  check (created_at_ms <= updated_at_ms)
);

create index spike_project_category_allocations_account_project_idx
  on public.spike_project_category_allocations (account_id, project_id, category_id);

create index spike_project_category_allocations_category_idx
  on public.spike_project_category_allocations (account_id, category_id, project_id);

alter table public.spike_budget_categories enable row level security;
alter table public.spike_projects enable row level security;
alter table public.spike_project_category_allocations enable row level security;

revoke all on table
  public.spike_budget_categories,
  public.spike_projects,
  public.spike_project_category_allocations
from public, anon, authenticated;

grant select on table
  public.spike_budget_categories,
  public.spike_projects,
  public.spike_project_category_allocations
to authenticated;

create policy spike_budget_categories_select_active_member
on public.spike_budget_categories
for select
to authenticated
using ((select ledger_private.has_active_membership(account_id)));

create policy spike_projects_select_active_member
on public.spike_projects
for select
to authenticated
using ((select ledger_private.has_active_membership(account_id)));

create policy spike_project_category_allocations_select_active_member
on public.spike_project_category_allocations
for select
to authenticated
using ((select ledger_private.has_active_membership(account_id)));

create function ledger_private.can_manage_projects(requested_account_id text)
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
      and membership.can_manage_projects
  )
$$;

create function ledger_private.can_manage_project_budgets(
  requested_account_id text
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
      and membership.can_manage_project_budgets
  )
$$;

create function ledger_private.can_view_budget_category(
  requested_account_id text,
  requested_visibility_class text
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
        requested_visibility_class = 'ordinary'
        or membership.financial_access = 'full'
      )
  )
$$;

create function ledger_private.jsonb_has_exact_keys(
  value jsonb,
  expected_keys text[]
)
returns boolean
language sql
immutable
set search_path = ''
as $$
  select pg_catalog.jsonb_typeof(value) = 'object'
    and (
      select pg_catalog.array_agg(key order by key)
      from pg_catalog.jsonb_object_keys(value) as key
    ) is not distinct from (
      select pg_catalog.array_agg(key order by key)
      from pg_catalog.unnest(expected_keys) as key
    )
$$;

revoke all on function ledger_private.can_manage_projects(text) from public;
revoke all on function ledger_private.can_manage_project_budgets(text) from public;
revoke all on function ledger_private.can_view_budget_category(text, text) from public;
revoke all on function ledger_private.jsonb_has_exact_keys(jsonb, text[]) from public;
grant execute on function ledger_private.can_manage_projects(text) to authenticated;
grant execute on function ledger_private.can_manage_project_budgets(text) to authenticated;
grant execute on function ledger_private.can_view_budget_category(text, text) to authenticated;

drop policy spike_budget_categories_select_active_member
  on public.spike_budget_categories;
create policy spike_budget_categories_select_visible_member
on public.spike_budget_categories
for select
to authenticated
using (
  (select ledger_private.has_active_membership(account_id))
  and (select ledger_private.can_view_budget_category(account_id, visibility_class))
);

drop policy spike_project_category_allocations_select_active_member
  on public.spike_project_category_allocations;
create policy spike_project_category_allocations_select_visible_member
on public.spike_project_category_allocations
for select
to authenticated
using (
  (select ledger_private.has_active_membership(account_id))
  and exists (
    select 1
    from public.spike_budget_categories as category
    where category.account_id = spike_project_category_allocations.account_id
      and category.id = spike_project_category_allocations.category_id
      and ledger_private.can_view_budget_category(
        category.account_id,
        category.visibility_class
      )
  )
);

create function ledger_private.spike_create_project(
  p_operation_id text,
  p_account_id text,
  p_actor_principal_id text,
  p_contract_version text,
  p_project_created_at timestamptz,
  p_project_id text,
  p_client_selection_kind text,
  p_client_id text,
  p_new_client_display_name text,
  p_project_display_name text,
  p_description text,
  p_category_allocations jsonb,
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
  v_envelope_project_created_at_ms bigint;
  v_envelope_sha256 text;
  v_existing public.spike_operation_results%rowtype;
  v_result public.spike_operation_results%rowtype;
  v_error_code text;
  v_allocation jsonb;
  v_previous_category_id text;
  v_category_id text;
  v_minor_units bigint;
  v_currency text;
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

  if not ledger_private.can_manage_projects(p_account_id) then
    raise exception using errcode = '42501', message = 'active project-management membership required';
  end if;

  if pg_catalog.jsonb_typeof(p_category_allocations) = 'array'
    and pg_catalog.jsonb_array_length(p_category_allocations) > 0
    and not ledger_private.can_manage_project_budgets(p_account_id)
  then
    raise exception using
      errcode = '42501',
      message = 'active project-budget management capability required';
  end if;

  if p_client_selection_kind = 'new'
    and not ledger_private.has_active_membership(p_account_id, true)
  then
    raise exception using errcode = '42501', message = 'active client-management membership required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(p_operation_id, 0)
  );
  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended('project:' || coalesce(p_project_id, ''), 0)
  );
  if p_client_selection_kind = 'new' then
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended('client:' || coalesce(p_client_id, ''), 0)
    );
  end if;

  select result.*
  into v_existing
  from public.spike_operation_results as result
  where result.operation_id = p_operation_id;

  if found then
    if v_existing.account_id is distinct from p_account_id
      or v_existing.actor_principal_id is distinct from p_actor_principal_id
      or v_existing.contract_version is distinct from p_contract_version
      or v_existing.command_fingerprint is distinct from p_fingerprint
      or v_existing.subject_id is distinct from p_project_id
      or v_existing.command_type is distinct from 'create_project'
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
    v_error_code := 'project_setup_command_encoding_invalid';
  end;

  v_envelope_sha256 := pg_catalog.encode(
    extensions.digest(pg_catalog.convert_to(p_envelope_json, 'UTF8'), 'sha256'),
    'hex'
  );

  if v_error_code is null and p_contract_version <> 'project-create-v1' then
    v_error_code := 'contract_unsupported';
  elsif v_error_code is null and (
    p_operation_id is null
    or p_account_id is null
    or p_actor_principal_id is null
    or p_project_id is null
    or p_client_id is null
    or p_client_selection_kind is null
    or p_project_display_name is null
    or p_fingerprint is null
    or p_project_created_at is null
    or p_category_allocations is null
    or p_operation_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or octet_length(p_operation_id) > 128
    or p_account_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or octet_length(p_account_id) > 128
    or p_actor_principal_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or octet_length(p_actor_principal_id) > 128
    or p_project_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or octet_length(p_project_id) > 128
    or p_client_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or octet_length(p_client_id) > 128
    or p_client_selection_kind not in ('existing', 'new')
    or (p_client_selection_kind = 'existing' and p_new_client_display_name is not null)
    or (
      p_client_selection_kind = 'new'
      and (p_new_client_display_name is null or btrim(p_new_client_display_name) = '')
    )
    or p_project_display_name ~ '^[[:space:]]*$'
    or (
      p_description is not null
      and (
        p_description = ''
        or p_description <> btrim(p_description)
      )
    )
    or p_fingerprint !~ '^[0-9a-f]{64}$'
    or not pg_catalog.isfinite(p_project_created_at)
    or pg_catalog.jsonb_typeof(p_category_allocations) is distinct from 'array'
  ) then
    v_error_code := 'project_setup_payload_invalid';
  elsif v_error_code is null and v_envelope_sha256 <> p_fingerprint then
    v_error_code := 'project_setup_fingerprint_mismatch';
  end if;

  if v_error_code is null and not ledger_private.jsonb_has_exact_keys(
    v_envelope,
    array[
      'accountId', 'actorPrincipalId', 'clientCreatedAt', 'contractVersion',
      'operationId', 'payload', 'preconditions'
    ]
  ) then
    v_error_code := 'project_setup_envelope_mismatch';
  end if;

  if v_error_code is null and (
    pg_catalog.jsonb_typeof(v_envelope -> 'clientCreatedAt') <> 'number'
    or v_envelope ->> 'clientCreatedAt' !~ '^-?[0-9]+$'
  ) then
    v_error_code := 'project_setup_envelope_mismatch';
  elsif v_error_code is null then
    begin
      v_envelope_project_created_at_ms :=
        (v_envelope ->> 'clientCreatedAt')::bigint;
    exception when numeric_value_out_of_range then
      v_error_code := 'project_setup_envelope_mismatch';
    end;
  end if;

  if v_error_code is null and not ledger_private.jsonb_has_exact_keys(
    v_envelope -> 'payload',
    case when p_description is null
      then array['categoryAllocations', 'clientSelection', 'displayName', 'projectId']
      else array['categoryAllocations', 'clientSelection', 'description', 'displayName', 'projectId']
    end
  ) then
    v_error_code := 'project_setup_envelope_mismatch';
  end if;

  if v_error_code is null and not ledger_private.jsonb_has_exact_keys(
    v_envelope #> '{payload,clientSelection}',
    case when p_client_selection_kind = 'existing'
      then array['clientId', 'kind']
      else array['clientId', 'displayName', 'kind']
    end
  ) then
    v_error_code := 'project_setup_envelope_mismatch';
  end if;

  if v_error_code is null and (
    v_envelope ->> 'operationId' is distinct from p_operation_id
    or v_envelope ->> 'accountId' is distinct from p_account_id
    or v_envelope ->> 'actorPrincipalId' is distinct from p_actor_principal_id
    or v_envelope ->> 'contractVersion' is distinct from p_contract_version
    or v_envelope_project_created_at_ms is distinct from
      floor(extract(epoch from p_project_created_at) * 1000)::bigint
    or v_envelope #>> '{payload,projectId}' is distinct from p_project_id
    or v_envelope #>> '{payload,clientSelection,kind}'
      is distinct from p_client_selection_kind
    or v_envelope #>> '{payload,clientSelection,clientId}' is distinct from p_client_id
    or v_envelope #>> '{payload,clientSelection,displayName}'
      is distinct from p_new_client_display_name
    or v_envelope #>> '{payload,displayName}' is distinct from p_project_display_name
    or v_envelope #>> '{payload,description}' is distinct from p_description
    or v_envelope #> '{payload,categoryAllocations}' is distinct from p_category_allocations
    or v_envelope -> 'preconditions' is distinct from '[]'::jsonb
  ) then
    v_error_code := 'project_setup_envelope_mismatch';
  end if;

  if v_error_code is null then
    for v_allocation in
      select value
      from pg_catalog.jsonb_array_elements(p_category_allocations)
        as allocations(value)
    loop
      if not ledger_private.jsonb_has_exact_keys(
        v_allocation,
        case when v_allocation ? 'allocation'
          then array['allocation', 'categoryId']
          else array['categoryId']
        end
      ) then
        v_error_code := 'project_setup_category_allocation_invalid';
        exit;
      end if;

      v_category_id := v_allocation ->> 'categoryId';
      if v_category_id is null
        or v_category_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
        or octet_length(v_category_id) > 128
        or (
          v_previous_category_id is not null
          and v_category_id collate "C" <= v_previous_category_id collate "C"
        )
      then
        v_error_code := 'project_setup_category_allocation_invalid';
        exit;
      end if;

      if v_allocation ? 'allocation' then
        if not ledger_private.jsonb_has_exact_keys(
          v_allocation -> 'allocation',
          array['currency', 'minorUnits']
        )
          or pg_catalog.jsonb_typeof(v_allocation #> '{allocation,minorUnits}') <> 'number'
          or v_allocation #>> '{allocation,minorUnits}' !~ '^-?[0-9]+$'
        then
          v_error_code := 'project_setup_category_allocation_invalid';
          exit;
        end if;

        begin
          v_minor_units := (v_allocation #>> '{allocation,minorUnits}')::bigint;
        exception when numeric_value_out_of_range then
          v_error_code := 'project_setup_category_allocation_invalid';
          exit;
        end;
        v_currency := v_allocation #>> '{allocation,currency}';
        if v_minor_units < 0 or v_currency !~ '^[A-Z]{3}$' then
          v_error_code := 'project_setup_category_allocation_invalid';
          exit;
        end if;
      else
        v_minor_units := null;
        v_currency := null;
      end if;

      if not exists (
        select 1
        from public.spike_budget_categories as category
        where category.account_id = p_account_id
          and category.id = v_category_id
          and category.lifecycle = 'active'
          and not category.is_system
          and ledger_private.can_view_budget_category(
            category.account_id,
            category.visibility_class
          )
      ) then
        v_error_code := 'project_setup_category_not_selectable';
        exit;
      end if;
      v_previous_category_id := v_category_id;
    end loop;
  end if;

  if v_error_code is null and exists (
    select 1 from public.spike_projects where id = p_project_id
  ) then
    v_error_code := 'project_setup_identity_conflict';
  end if;

  if v_error_code is null and p_client_selection_kind = 'existing' and not exists (
    select 1
    from public.spike_clients as client
    where client.id = p_client_id
      and client.account_id = p_account_id
      and client.lifecycle = 'active'
  ) then
    v_error_code := 'project_setup_client_not_selectable';
  end if;

  if v_error_code is null and p_client_selection_kind = 'new' and exists (
    select 1 from public.spike_clients where id = p_client_id
  ) then
    v_error_code := 'project_setup_new_client_identity_conflict';
  end if;

  if v_error_code is null then
    begin
      if p_client_selection_kind = 'new' then
        insert into public.spike_clients (
      id, account_id, display_name, lifecycle, revision, created_at, updated_at,
      created_at_ms, updated_at_ms, created_by_principal_id
    ) values (
      p_client_id, p_account_id, p_new_client_display_name, 'active', 1,
      v_now, v_now, v_now_ms, v_now_ms, p_actor_principal_id
        );
      end if;

      insert into public.spike_projects (
      id, account_id, client_id, display_name, description, lifecycle, revision,
      created_at, updated_at, created_at_ms, updated_at_ms,
      created_by_principal_id
    ) values (
      p_project_id, p_account_id, p_client_id, p_project_display_name,
      p_description, 'active', 1, v_now, v_now, v_now_ms, v_now_ms,
      p_actor_principal_id
    );

      for v_allocation in
        select value
        from pg_catalog.jsonb_array_elements(p_category_allocations)
      loop
        v_category_id := v_allocation ->> 'categoryId';
        if v_allocation ? 'allocation' then
          v_minor_units := (v_allocation #>> '{allocation,minorUnits}')::bigint;
          v_currency := v_allocation #>> '{allocation,currency}';
        else
          v_minor_units := null;
          v_currency := null;
        end if;
        insert into public.spike_project_category_allocations (
          account_id, project_id, category_id, allocation_minor_units,
          allocation_currency, revision, created_at, updated_at, created_at_ms,
          updated_at_ms, created_by_principal_id
        ) values (
          p_account_id, p_project_id, v_category_id, v_minor_units, v_currency, 1,
          v_now, v_now, v_now_ms, v_now_ms, p_actor_principal_id
        );
      end loop;
    exception when unique_violation then
      v_error_code := 'project_setup_identity_conflict';
    end;
  end if;

  insert into public.spike_operation_results (
    operation_id, account_id, actor_principal_id, command_type,
    contract_version, command_fingerprint, envelope_sha256, subject_id, phase,
    result_code, error_code, client_created_at, server_received_at,
    completed_at, client_created_at_ms, server_received_at_ms, completed_at_ms
  ) values (
    p_operation_id, p_account_id, p_actor_principal_id, 'create_project',
    p_contract_version, p_fingerprint, v_envelope_sha256, p_project_id,
    case when v_error_code is null then 'applied' else 'rejected' end,
    case when v_error_code is null then 'project_created' end,
    v_error_code, p_project_created_at, v_now, v_now,
    floor(extract(epoch from p_project_created_at) * 1000)::bigint,
    v_now_ms, v_now_ms
  )
  returning * into v_result;

  return v_result;
end
$$;

revoke all on function ledger_private.spike_create_project(
  text, text, text, text, timestamptz, text, text, text, text, text, text,
  jsonb, text, text
) from public;
grant execute on function ledger_private.spike_create_project(
  text, text, text, text, timestamptz, text, text, text, text, text, text,
  jsonb, text, text
) to authenticated;

create function public.spike_create_project(
  p_operation_id text,
  p_account_id text,
  p_actor_principal_id text,
  p_contract_version text,
  p_project_created_at timestamptz,
  p_project_id text,
  p_client_selection_kind text,
  p_client_id text,
  p_new_client_display_name text,
  p_project_display_name text,
  p_description text,
  p_category_allocations jsonb,
  p_fingerprint text,
  p_envelope_json text
)
returns public.spike_operation_results
language sql
security invoker
set search_path = ''
as $$
  select ledger_private.spike_create_project(
    p_operation_id, p_account_id, p_actor_principal_id, p_contract_version,
    p_project_created_at, p_project_id, p_client_selection_kind, p_client_id,
    p_new_client_display_name, p_project_display_name, p_description,
    p_category_allocations, p_fingerprint, p_envelope_json
  )
$$;

revoke all on function public.spike_create_project(
  text, text, text, text, timestamptz, text, text, text, text, text, text,
  jsonb, text, text
) from public, anon;

grant execute on function public.spike_create_project(
  text, text, text, text, timestamptz, text, text, text, text, text, text,
  jsonb, text, text
) to authenticated;
