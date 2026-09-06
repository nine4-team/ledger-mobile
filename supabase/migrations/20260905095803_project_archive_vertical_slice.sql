alter table public.spike_operation_results
  drop constraint spike_operation_results_command_type_check;

alter table public.spike_operation_results
  add column request_sha256 text;

alter table public.spike_operation_results
  add constraint spike_operation_results_command_type_check
  check (command_type in ('create_client', 'create_project', 'archive_project'));

alter table public.spike_operation_results
  add constraint spike_operation_results_request_sha256_check
  check (
    (command_type = 'archive_project' and request_sha256 ~ '^[0-9a-f]{64}$')
    or
    (command_type <> 'archive_project' and request_sha256 is null)
  );

alter table public.spike_operation_results
  add constraint spike_operation_results_archive_namespace_check
  check (
    (
      command_type = 'archive_project'
      and operation_id ~ '^project-archive-[0-9a-f]{64}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and octet_length(operation_id) = 117
      and substring(operation_id from 17 for 64) = pg_catalog.encode(
        extensions.digest(pg_catalog.convert_to(account_id, 'UTF8'), 'sha256'),
        'hex'
      )
    )
    or
    (
      command_type <> 'archive_project'
      and operation_id !~ '^project-archive-'
    )
  );

create function ledger_private.enforce_spike_operation_namespace()
returns trigger
language plpgsql
set search_path = ''
as $$
begin
  if (
    new.command_type = 'archive_project'
    and (
      new.operation_id !~ '^project-archive-[0-9a-f]{64}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or octet_length(new.operation_id) <> 117
      or substring(new.operation_id from 17 for 64) is distinct from
        pg_catalog.encode(
          extensions.digest(
            pg_catalog.convert_to(new.account_id, 'UTF8'),
            'sha256'
          ),
          'hex'
        )
    )
  ) or (
    new.command_type <> 'archive_project'
    and new.operation_id ~ '^project-archive-'
  ) then
    raise exception using
      errcode = '22023',
      message = 'project archive request identity invalid';
  end if;
  return new;
end
$$;

revoke all on function ledger_private.enforce_spike_operation_namespace()
from public, anon, authenticated, service_role;

create trigger spike_operation_results_archive_namespace
before insert on public.spike_operation_results
for each row execute function ledger_private.enforce_spike_operation_namespace();

create function ledger_private.spike_archive_project(
  p_operation_id text,
  p_account_id text,
  p_actor_principal_id text,
  p_contract_version text,
  p_project_captured_at timestamptz,
  p_project_id text,
  p_expected_revision text,
  p_fingerprint text,
  p_envelope_json text
)
returns public.spike_operation_results
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_received_at timestamptz := date_trunc('milliseconds', clock_timestamp());
  v_received_at_ms bigint;
  v_completed_at timestamptz;
  v_completed_at_ms bigint;
  v_client_created_at_ms bigint;
  v_expected_revision_numeric numeric;
  v_expected_revision_bigint bigint;
  v_account_sha256 text;
  v_canonical_envelope text;
  v_envelope_sha256 text;
  v_request_material text;
  v_request_sha256 text;
  v_error_code text;
  v_existing public.spike_operation_results%rowtype;
  v_project public.spike_projects%rowtype;
  v_result public.spike_operation_results%rowtype;
begin
  -- Authorization deliberately precedes command, result, and Project inspection
  -- so this privileged handler cannot become an existence oracle.
  if (select auth.uid()) is null then
    raise exception using errcode = '28000', message = 'authentication required';
  end if;

  if p_actor_principal_id is distinct from (
    select ledger_private.current_principal_id()
  ) then
    raise exception using
      errcode = '42501',
      message = 'actor is not the authenticated principal';
  end if;

  if not ledger_private.can_manage_projects(p_account_id) then
    raise exception using
      errcode = '42501',
      message = 'active project-management membership required';
  end if;

  v_received_at_ms := floor(extract(epoch from v_received_at) * 1000)::bigint;
  v_account_sha256 := pg_catalog.encode(
    extensions.digest(pg_catalog.convert_to(p_account_id, 'UTF8'), 'sha256'),
    'hex'
  );

  -- These fields must be recordable without substituting or sanitizing caller
  -- identity. Fail them as one bounded transport error, not a raw table error.
  if p_operation_id is null
    or p_operation_id !~ '^project-archive-[0-9a-f]{64}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or octet_length(p_operation_id) <> 117
    or substring(p_operation_id from 17 for 64) is distinct from v_account_sha256
    or p_contract_version is null
    or p_contract_version !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or octet_length(p_contract_version) > 128
    or p_project_captured_at is null
    or not pg_catalog.isfinite(p_project_captured_at)
    or p_project_captured_at <> date_trunc('milliseconds', p_project_captured_at)
    or p_project_id is null
    or p_project_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or octet_length(p_project_id) > 128
    or p_fingerprint is null
    or p_fingerprint !~ '^[0-9a-f]{64}$'
    or p_envelope_json is null
  then
    raise exception using
      errcode = '22023',
      message = 'project archive request identity invalid';
  end if;

  v_client_created_at_ms :=
    floor(extract(epoch from p_project_captured_at) * 1000)::bigint;

  -- request_sha256 v1 binds all nine typed RPC arguments in fixed order.
  -- A value is `v<UTF-8 byte count>:<bytes>`; NULL is `n`. Timestamp identity
  -- is the normalized signed decimal Unix epoch-millisecond value.
  v_request_material := 'project-archive-request-v1|'
    || 'v' || octet_length(p_operation_id)::text || ':' || p_operation_id
    || 'v' || octet_length(p_account_id)::text || ':' || p_account_id
    || 'v' || octet_length(p_actor_principal_id)::text || ':' || p_actor_principal_id
    || 'v' || octet_length(p_contract_version)::text || ':' || p_contract_version
    || 'v' || octet_length(v_client_created_at_ms::text)::text || ':'
      || v_client_created_at_ms::text
    || 'v' || octet_length(p_project_id)::text || ':' || p_project_id
    || case when p_expected_revision is null
      then 'n'
      else 'v' || octet_length(p_expected_revision)::text || ':' || p_expected_revision
    end
    || 'v' || octet_length(p_fingerprint)::text || ':' || p_fingerprint
    || 'v' || octet_length(p_envelope_json)::text || ':' || p_envelope_json;
  v_request_sha256 := pg_catalog.encode(
    extensions.digest(pg_catalog.convert_to(v_request_material, 'UTF8'), 'sha256'),
    'hex'
  );

  begin
    perform p_envelope_json::jsonb;
  exception when others then
    v_error_code := 'project_archive_command_encoding_invalid';
  end;

  if p_envelope_json is not null then
    v_envelope_sha256 := pg_catalog.encode(
      extensions.digest(pg_catalog.convert_to(p_envelope_json, 'UTF8'), 'sha256'),
      'hex'
    );
  end if;

  if v_error_code is null and p_contract_version is distinct from 'project-archive-v1' then
    v_error_code := 'contract_unsupported';
  elsif v_error_code is null and (
    p_account_id is null
    or p_actor_principal_id is null
    or p_expected_revision is null
    or p_account_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or octet_length(p_account_id) > 128
    or p_actor_principal_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or octet_length(p_actor_principal_id) > 128
    or p_expected_revision !~ '^(0|[1-9][0-9]*)$'
    or octet_length(p_expected_revision) > 20
  ) then
    v_error_code := 'project_archive_payload_invalid';
  end if;

  if v_error_code is null then
    v_expected_revision_numeric := p_expected_revision::numeric;
    if v_expected_revision_numeric > 18446744073709551615::numeric then
      v_error_code := 'project_archive_payload_invalid';
    end if;
  end if;

  if v_error_code is null and v_envelope_sha256 is distinct from p_fingerprint then
    v_error_code := 'project_archive_fingerprint_mismatch';
  end if;

  if v_error_code is null then
    v_canonical_envelope := pg_catalog.format(
      '{"accountId":%s,"actorPrincipalId":%s,"clientCreatedAt":%s,"contractVersion":%s,"operationId":%s,"payload":{"projectId":%s},"preconditions":[{"expectedRevision":{"revision":%s,"subject":{"id":%s,"kind":"project"}}}]}',
      pg_catalog.to_json(p_account_id)::text,
      pg_catalog.to_json(p_actor_principal_id)::text,
      v_client_created_at_ms,
      pg_catalog.to_json(p_contract_version)::text,
      pg_catalog.to_json(p_operation_id)::text,
      pg_catalog.to_json(p_project_id)::text,
      p_expected_revision,
      pg_catalog.to_json(p_project_id)::text
    );

    if p_envelope_json is distinct from v_canonical_envelope then
      v_error_code := 'project_archive_envelope_mismatch';
    end if;
  end if;

  -- Serialize every use of an OperationID before consulting immutable results.
  -- The Project row is then locked in the same result-then-Project order.
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
      or v_existing.command_type is distinct from 'archive_project'
      or v_existing.contract_version is distinct from p_contract_version
      or v_existing.command_fingerprint is distinct from p_fingerprint
      or v_existing.envelope_sha256 is distinct from v_envelope_sha256
      or v_existing.request_sha256 is distinct from v_request_sha256
      or v_existing.subject_id is distinct from p_project_id
    then
      raise exception using
        errcode = '23505',
        message = 'operation id is already bound to a different command';
    end if;
    return v_existing;
  end if;

  if v_error_code is null then
    select project.*
    into v_project
    from public.spike_projects as project
    where project.account_id = p_account_id
      and project.id = p_project_id
    for update;

    if not found
      or v_project.lifecycle is distinct from 'active'
      or v_expected_revision_numeric > 9223372036854775807::numeric
      or v_project.revision::numeric is distinct from v_expected_revision_numeric
      or v_project.revision = 9223372036854775807::bigint
    then
      v_error_code := 'project_archive_revision_conflict';
    else
      v_expected_revision_bigint := v_expected_revision_numeric::bigint;
      v_completed_at_ms := greatest(
        floor(extract(epoch from clock_timestamp()) * 1000)::bigint,
        v_project.updated_at_ms + 1
      );
      v_completed_at := greatest(
        date_trunc('milliseconds', clock_timestamp()),
        v_project.updated_at + interval '1 millisecond'
      );

      update public.spike_projects as project
      set lifecycle = 'archived',
          revision = v_expected_revision_bigint + 1,
          updated_at = v_completed_at,
          updated_at_ms = v_completed_at_ms
      where project.account_id = p_account_id
        and project.id = p_project_id;
    end if;
  end if;

  if v_completed_at is null then
    v_completed_at := date_trunc('milliseconds', clock_timestamp());
    v_completed_at_ms := floor(extract(epoch from v_completed_at) * 1000)::bigint;
  end if;

  insert into public.spike_operation_results (
    operation_id, account_id, actor_principal_id, command_type,
    contract_version, command_fingerprint, envelope_sha256, request_sha256,
    subject_id, phase, result_code, error_code, client_created_at, server_received_at,
    completed_at, client_created_at_ms, server_received_at_ms, completed_at_ms
  ) values (
    p_operation_id, p_account_id, p_actor_principal_id, 'archive_project',
    p_contract_version, p_fingerprint, v_envelope_sha256, v_request_sha256,
    p_project_id,
    case when v_error_code is null then 'applied' else 'rejected' end,
    case when v_error_code is null then 'project_archived' end,
    v_error_code, p_project_captured_at, v_received_at, v_completed_at,
    v_client_created_at_ms, v_received_at_ms, v_completed_at_ms
  )
  returning * into v_result;

  return v_result;
end
$$;

revoke all on function ledger_private.spike_archive_project(
  text, text, text, text, timestamptz, text, text, text, text
) from public, anon, service_role;

grant execute on function ledger_private.spike_archive_project(
  text, text, text, text, timestamptz, text, text, text, text
) to authenticated;

create function public.spike_archive_project(
  p_operation_id text,
  p_account_id text,
  p_actor_principal_id text,
  p_contract_version text,
  p_project_captured_at timestamptz,
  p_project_id text,
  p_expected_revision text,
  p_fingerprint text,
  p_envelope_json text
)
returns public.spike_operation_results
language sql
security invoker
set search_path = ''
as $$
  select ledger_private.spike_archive_project(
    p_operation_id, p_account_id, p_actor_principal_id, p_contract_version,
    p_project_captured_at, p_project_id, p_expected_revision, p_fingerprint,
    p_envelope_json
  )
$$;

revoke all on function public.spike_archive_project(
  text, text, text, text, timestamptz, text, text, text, text
) from public, anon, service_role;

grant execute on function public.spike_archive_project(
  text, text, text, text, timestamptz, text, text, text, text
) to authenticated;
