alter table public.spike_operation_results
  drop constraint spike_operation_results_command_type_check;

alter table public.spike_operation_results
  drop constraint spike_operation_results_request_sha256_check;

alter table public.spike_operation_results
  drop constraint spike_operation_results_archive_namespace_check;

alter table public.spike_operation_results
  add constraint spike_operation_results_command_type_check
  check (
    command_type in (
      'create_client',
      'create_project',
      'archive_project',
      'archive_client',
      'revise_space_checklists'
    )
  );

alter table public.spike_operation_results
  add constraint spike_operation_results_request_sha256_check
  check (
    (
      command_type in (
        'archive_project',
        'archive_client',
        'revise_space_checklists'
      )
      and request_sha256 ~ '^[0-9a-f]{64}$'
    )
    or (
      command_type not in (
        'archive_project',
        'archive_client',
        'revise_space_checklists'
      )
      and request_sha256 is null
    )
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
    or (
      command_type = 'archive_client'
      and operation_id ~ '^client-archive-[0-9a-f]{64}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and octet_length(operation_id) = 116
      and substring(operation_id from 16 for 64) = pg_catalog.encode(
        extensions.digest(pg_catalog.convert_to(account_id, 'UTF8'), 'sha256'),
        'hex'
      )
    )
    or (
      command_type = 'revise_space_checklists'
      and operation_id ~ '^space-checklist-revision-[0-9a-f]{64}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      and octet_length(operation_id) = 126
      and substring(operation_id from 26 for 64) = pg_catalog.encode(
        extensions.digest(pg_catalog.convert_to(account_id, 'UTF8'), 'sha256'),
        'hex'
      )
    )
    or (
      command_type not in (
        'archive_project',
        'archive_client',
        'revise_space_checklists'
      )
      and operation_id !~ '^(project|client)-archive-'
      and operation_id !~ '^space-checklist-revision-'
    )
  );

drop trigger spike_operation_results_archive_namespace
on public.spike_operation_results;

drop function ledger_private.enforce_spike_operation_namespace();

create function ledger_private.enforce_spike_operation_namespace()
returns trigger
language plpgsql
set search_path = ''
as $$
declare
  v_account_sha256 text := pg_catalog.encode(
    extensions.digest(pg_catalog.convert_to(new.account_id, 'UTF8'), 'sha256'),
    'hex'
  );
begin
  if new.operation_id ~ '^project-archive-' and (
    new.command_type <> 'archive_project'
    or new.operation_id !~ '^project-archive-[0-9a-f]{64}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or octet_length(new.operation_id) <> 117
    or substring(new.operation_id from 17 for 64) is distinct from v_account_sha256
  ) then
    raise exception using
      errcode = '22023',
      message = 'project archive request identity invalid';
  end if;

  if new.operation_id ~ '^client-archive-' and (
    new.command_type <> 'archive_client'
    or new.operation_id !~ '^client-archive-[0-9a-f]{64}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or octet_length(new.operation_id) <> 116
    or substring(new.operation_id from 16 for 64) is distinct from v_account_sha256
  ) then
    raise exception using
      errcode = '22023',
      message = 'client archive request identity invalid';
  end if;

  if new.operation_id ~ '^space-checklist-revision-' and (
    new.command_type <> 'revise_space_checklists'
    or new.operation_id !~ '^space-checklist-revision-[0-9a-f]{64}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or octet_length(new.operation_id) <> 126
    or substring(new.operation_id from 26 for 64) is distinct from v_account_sha256
  ) then
    raise exception using
      errcode = '22023',
      message = 'Space checklist revision request identity invalid';
  end if;

  if (
    new.command_type = 'archive_project'
    and (
      new.operation_id !~ '^project-archive-[0-9a-f]{64}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or octet_length(new.operation_id) <> 117
      or substring(new.operation_id from 17 for 64) is distinct from v_account_sha256
    )
  ) or (
    new.command_type = 'archive_client'
    and (
      new.operation_id !~ '^client-archive-[0-9a-f]{64}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or octet_length(new.operation_id) <> 116
      or substring(new.operation_id from 16 for 64) is distinct from v_account_sha256
    )
  ) or (
    new.command_type = 'revise_space_checklists'
    and (
      new.operation_id !~ '^space-checklist-revision-[0-9a-f]{64}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
      or octet_length(new.operation_id) <> 126
      or substring(new.operation_id from 26 for 64) is distinct from v_account_sha256
    )
  ) then
    raise exception using
      errcode = '22023',
      message = 'operation request identity invalid';
  end if;

  return new;
end
$$;

revoke all on function ledger_private.enforce_spike_operation_namespace()
from public, anon, authenticated, service_role;

create trigger spike_operation_results_archive_namespace
before insert on public.spike_operation_results
for each row execute function ledger_private.enforce_spike_operation_namespace();

create function ledger_private.canonical_space_checklist_collection(
  p_collection jsonb
)
returns text
language plpgsql
stable
set search_path = ''
as $$
declare
  v_checklist jsonb;
  v_item jsonb;
  v_checklist_id text;
  v_checklist_name text;
  v_checklist_order_text text;
  v_checklist_order bigint;
  v_item_id text;
  v_item_text text;
  v_item_order_text text;
  v_item_order bigint;
  v_previous_checklist_order bigint := -1;
  v_previous_item_order bigint;
  v_checklist_ids text[] := array[]::text[];
  v_item_ids text[];
  v_result text := '{"checklists":[';
  v_checklist_separator text := '';
  v_item_separator text;
begin
  if p_collection is null
    or pg_catalog.jsonb_typeof(p_collection) <> 'object'
    or not (p_collection ? 'checklists')
    or (
      select count(*)
      from pg_catalog.jsonb_object_keys(p_collection)
    ) <> 1
    or pg_catalog.jsonb_typeof(p_collection -> 'checklists') <> 'array'
  then
    return null;
  end if;

  for v_checklist in
    select entry.value
    from pg_catalog.jsonb_array_elements(p_collection -> 'checklists')
      with ordinality as entry(value, position)
    order by entry.position
  loop
    if pg_catalog.jsonb_typeof(v_checklist) <> 'object'
      or not (v_checklist ?& array['id', 'items', 'name', 'presentationOrder'])
      or (
        select count(*)
        from pg_catalog.jsonb_object_keys(v_checklist)
      ) <> 4
      or pg_catalog.jsonb_typeof(v_checklist -> 'id') <> 'string'
      or pg_catalog.jsonb_typeof(v_checklist -> 'items') <> 'array'
      or pg_catalog.jsonb_typeof(v_checklist -> 'name') <> 'string'
      or pg_catalog.jsonb_typeof(v_checklist -> 'presentationOrder') <> 'number'
    then
      return null;
    end if;

    v_checklist_id := v_checklist ->> 'id';
    v_checklist_name := v_checklist ->> 'name';
    v_checklist_order_text := v_checklist ->> 'presentationOrder';

    if v_checklist_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
      or octet_length(v_checklist_id) > 128
      or v_checklist_id = any(v_checklist_ids)
      or v_checklist_name = ''
      or v_checklist_name ~ '^[[:space:]]'
      or v_checklist_name ~ '[[:space:]]$'
      or v_checklist_order_text !~ '^(0|[1-9][0-9]*)$'
      or v_checklist_order_text::numeric > 4294967295::numeric
    then
      return null;
    end if;

    v_checklist_order := v_checklist_order_text::bigint;
    if v_checklist_order <= v_previous_checklist_order then
      return null;
    end if;
    v_previous_checklist_order := v_checklist_order;
    v_checklist_ids := array_append(v_checklist_ids, v_checklist_id);
    v_item_ids := array[]::text[];
    v_previous_item_order := -1;
    v_item_separator := '';

    v_result := v_result || v_checklist_separator
      || '{"id":' || pg_catalog.to_json(v_checklist_id)::text
      || ',"items":[';

    for v_item in
      select entry.value
      from pg_catalog.jsonb_array_elements(v_checklist -> 'items')
        with ordinality as entry(value, position)
      order by entry.position
    loop
      if pg_catalog.jsonb_typeof(v_item) <> 'object'
        or not (v_item ?& array['id', 'isChecked', 'presentationOrder', 'text'])
        or (
          select count(*)
          from pg_catalog.jsonb_object_keys(v_item)
        ) <> 4
        or pg_catalog.jsonb_typeof(v_item -> 'id') <> 'string'
        or pg_catalog.jsonb_typeof(v_item -> 'isChecked') <> 'boolean'
        or pg_catalog.jsonb_typeof(v_item -> 'presentationOrder') <> 'number'
        or pg_catalog.jsonb_typeof(v_item -> 'text') <> 'string'
      then
        return null;
      end if;

      v_item_id := v_item ->> 'id';
      v_item_text := v_item ->> 'text';
      v_item_order_text := v_item ->> 'presentationOrder';

      if v_item_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
        or octet_length(v_item_id) > 128
        or v_item_id = any(v_item_ids)
        or v_item_text = ''
        or v_item_text ~ '^[[:space:]]'
        or v_item_text ~ '[[:space:]]$'
        or v_item_order_text !~ '^(0|[1-9][0-9]*)$'
        or v_item_order_text::numeric > 4294967295::numeric
      then
        return null;
      end if;

      v_item_order := v_item_order_text::bigint;
      if v_item_order <= v_previous_item_order then
        return null;
      end if;
      v_previous_item_order := v_item_order;
      v_item_ids := array_append(v_item_ids, v_item_id);

      v_result := v_result || v_item_separator
        || '{"id":' || pg_catalog.to_json(v_item_id)::text
        || ',"isChecked":' || (v_item ->> 'isChecked')
        || ',"presentationOrder":' || v_item_order_text
        || ',"text":' || pg_catalog.to_json(v_item_text)::text
        || '}';
      v_item_separator := ',';
    end loop;

    v_result := v_result
      || '],"name":' || pg_catalog.to_json(v_checklist_name)::text
      || ',"presentationOrder":' || v_checklist_order_text
      || '}';
    v_checklist_separator := ',';
  end loop;

  return v_result || ']}';
exception
  when numeric_value_out_of_range then
    return null;
end
$$;

revoke all on function ledger_private.canonical_space_checklist_collection(jsonb)
from public, anon, authenticated, service_role;

create function ledger_private.spike_revise_space_checklists(
  p_operation_id text,
  p_account_id text,
  p_actor_principal_id text,
  p_contract_version text,
  p_space_captured_at timestamptz,
  p_space_id text,
  p_expected_revision text,
  p_collection jsonb,
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
  v_collection_canonical text;
  v_request_collection text;
  v_canonical_envelope text;
  v_envelope_sha256 text;
  v_request_material text;
  v_request_sha256 text;
  v_error_code text;
  v_existing public.spike_operation_results%rowtype;
  v_space public.spike_spaces%rowtype;
  v_space_detail public.spike_space_core_details%rowtype;
  v_result public.spike_operation_results%rowtype;
  v_checklist jsonb;
  v_item jsonb;
  v_checklist_id text;
begin
  -- Authorization precedes request/result/Space inspection so this privileged
  -- function cannot become an Account, operation, or Space existence oracle.
  if (select auth.uid()) is null then
    raise exception using
      errcode = '28000',
      message = 'authentication required';
  end if;

  if p_actor_principal_id is distinct from (
    select ledger_private.current_principal_id()
  ) then
    raise exception using
      errcode = '42501',
      message = 'actor is not the authenticated principal';
  end if;

  if not ledger_private.has_active_membership(p_account_id) then
    raise exception using
      errcode = '42501',
      message = 'active Account membership required';
  end if;

  v_received_at_ms := floor(extract(epoch from v_received_at) * 1000)::bigint;
  v_account_sha256 := pg_catalog.encode(
    extensions.digest(pg_catalog.convert_to(p_account_id, 'UTF8'), 'sha256'),
    'hex'
  );

  if p_operation_id is null
    or p_operation_id !~ '^space-checklist-revision-[0-9a-f]{64}-[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    or octet_length(p_operation_id) <> 126
    or substring(p_operation_id from 26 for 64) is distinct from v_account_sha256
    or p_contract_version is null
    or p_contract_version !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or octet_length(p_contract_version) > 128
    or p_space_captured_at is null
    or not pg_catalog.isfinite(p_space_captured_at)
    or p_space_captured_at <> date_trunc('milliseconds', p_space_captured_at)
    or p_space_id is null
    or p_space_id !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    or octet_length(p_space_id) > 128
    or p_fingerprint is null
    or p_fingerprint !~ '^[0-9a-f]{64}$'
    or p_envelope_json is null
  then
    raise exception using
      errcode = '22023',
      message = 'Space checklist revision request identity invalid';
  end if;

  v_client_created_at_ms :=
    floor(extract(epoch from p_space_captured_at) * 1000)::bigint;
  v_collection_canonical :=
    ledger_private.canonical_space_checklist_collection(p_collection);
  v_request_collection := coalesce(v_collection_canonical, p_collection::text, 'null');

  v_request_material := 'space-checklist-revision-request-v1|'
    || 'v' || octet_length(p_operation_id)::text || ':' || p_operation_id
    || 'v' || octet_length(p_account_id)::text || ':' || p_account_id
    || 'v' || octet_length(p_actor_principal_id)::text || ':' || p_actor_principal_id
    || 'v' || octet_length(p_contract_version)::text || ':' || p_contract_version
    || 'v' || octet_length(v_client_created_at_ms::text)::text || ':'
      || v_client_created_at_ms::text
    || 'v' || octet_length(p_space_id)::text || ':' || p_space_id
    || case when p_expected_revision is null
      then 'n'
      else 'v' || octet_length(p_expected_revision)::text || ':' || p_expected_revision
    end
    || 'v' || octet_length(v_request_collection)::text || ':' || v_request_collection
    || 'v' || octet_length(p_fingerprint)::text || ':' || p_fingerprint
    || 'v' || octet_length(p_envelope_json)::text || ':' || p_envelope_json;
  v_request_sha256 := pg_catalog.encode(
    extensions.digest(pg_catalog.convert_to(v_request_material, 'UTF8'), 'sha256'),
    'hex'
  );

  begin
    perform p_envelope_json::jsonb;
  exception
    when others then
      v_error_code := 'space_checklist_revision_command_encoding_invalid';
  end;

  v_envelope_sha256 := pg_catalog.encode(
    extensions.digest(pg_catalog.convert_to(p_envelope_json, 'UTF8'), 'sha256'),
    'hex'
  );

  if v_error_code is null
    and p_contract_version is distinct from 'space-checklist-revision-v1'
  then
    v_error_code := 'contract_unsupported';
  elsif v_error_code is null and (
    p_expected_revision is null
    or p_expected_revision !~ '^(0|[1-9][0-9]*)$'
    or octet_length(p_expected_revision) > 20
    or v_collection_canonical is null
  ) then
    v_error_code := 'space_checklist_revision_payload_invalid';
  end if;

  if v_error_code is null then
    v_expected_revision_numeric := p_expected_revision::numeric;
    if v_expected_revision_numeric > 18446744073709551615::numeric then
      v_error_code := 'space_checklist_revision_payload_invalid';
    end if;
  end if;

  if v_error_code is null
    and v_envelope_sha256 is distinct from p_fingerprint
  then
    v_error_code := 'space_checklist_revision_fingerprint_mismatch';
  end if;

  if v_error_code is null then
    v_canonical_envelope := pg_catalog.format(
      '{"accountId":%s,"actorPrincipalId":%s,"clientCreatedAt":%s,"contractVersion":%s,"operationId":%s,"payload":{"collection":%s,"spaceId":%s},"preconditions":[{"expectedRevision":{"revision":%s,"subject":{"id":%s,"kind":"space"}}}]}',
      pg_catalog.to_json(p_account_id)::text,
      pg_catalog.to_json(p_actor_principal_id)::text,
      v_client_created_at_ms,
      pg_catalog.to_json(p_contract_version)::text,
      pg_catalog.to_json(p_operation_id)::text,
      v_collection_canonical,
      pg_catalog.to_json(p_space_id)::text,
      p_expected_revision,
      pg_catalog.to_json(p_space_id)::text
    );

    if p_envelope_json is distinct from v_canonical_envelope then
      v_error_code := 'space_checklist_revision_envelope_mismatch';
    end if;
  end if;

  -- Serialize every use of an OperationID before consulting immutable results.
  -- New commands then lock one exact Space before checking its revision.
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
      or v_existing.command_type is distinct from 'revise_space_checklists'
      or v_existing.contract_version is distinct from p_contract_version
      or v_existing.command_fingerprint is distinct from p_fingerprint
      or v_existing.envelope_sha256 is distinct from v_envelope_sha256
      or v_existing.request_sha256 is distinct from v_request_sha256
      or v_existing.subject_id is distinct from p_space_id
    then
      raise exception using
        errcode = '23505',
        message = 'operation id is already bound to a different command';
    end if;
    return v_existing;
  end if;

  if v_error_code is null then
    select space.*
    into v_space
    from public.spike_spaces as space
    where space.account_id = p_account_id
      and space.id = p_space_id
    for update;

    if not found
      or v_space.lifecycle is distinct from 'active'
      or v_expected_revision_numeric > 9223372036854775807::numeric
      or v_space.revision::numeric is distinct from v_expected_revision_numeric
      or v_space.revision = 9223372036854775807::bigint
    then
      v_error_code := 'space_checklist_revision_conflict';
    else
      select detail.*
      into v_space_detail
      from public.spike_space_core_details as detail
      where detail.account_id = p_account_id
        and detail.id = p_space_id
      for update;

      if not found then
        v_error_code := 'space_checklist_revision_conflict';
      end if;
    end if;
  end if;

  if v_error_code is null then
    v_expected_revision_bigint := v_expected_revision_numeric::bigint;
    v_completed_at := greatest(
      date_trunc('milliseconds', clock_timestamp()),
      v_space_detail.updated_at + interval '1 millisecond'
    );
    v_completed_at_ms :=
      floor(extract(epoch from v_completed_at) * 1000)::bigint;

    delete from public.spike_space_checklists as checklist
    where checklist.account_id = p_account_id
      and checklist.space_id = p_space_id;

    for v_checklist in
      select entry.value
      from pg_catalog.jsonb_array_elements(p_collection -> 'checklists')
        with ordinality as entry(value, position)
      order by entry.position
    loop
      v_checklist_id := v_checklist ->> 'id';

      insert into public.spike_space_checklists (
        id,
        account_id,
        space_id,
        checklist_id,
        name,
        presentation_order
      ) values (
        'space-checklist-' || pg_catalog.encode(
          extensions.digest(
            pg_catalog.convert_to(
              'space-checklist-row-v1|'
              || p_account_id || '|' || p_space_id || '|' || v_checklist_id,
              'UTF8'
            ),
            'sha256'
          ),
          'hex'
        ),
        p_account_id,
        p_space_id,
        v_checklist_id,
        v_checklist ->> 'name',
        (v_checklist ->> 'presentationOrder')::bigint
      );

      for v_item in
        select entry.value
        from pg_catalog.jsonb_array_elements(v_checklist -> 'items')
          with ordinality as entry(value, position)
        order by entry.position
      loop
        insert into public.spike_space_checklist_items (
          id,
          account_id,
          space_id,
          checklist_id,
          item_id,
          item_text,
          is_checked,
          presentation_order
        ) values (
          'space-checklist-item-' || pg_catalog.encode(
            extensions.digest(
              pg_catalog.convert_to(
                'space-checklist-item-row-v1|'
                || p_account_id || '|' || p_space_id || '|'
                || v_checklist_id || '|' || (v_item ->> 'id'),
                'UTF8'
              ),
              'sha256'
            ),
            'hex'
          ),
          p_account_id,
          p_space_id,
          v_checklist_id,
          v_item ->> 'id',
          v_item ->> 'text',
          (v_item ->> 'isChecked')::boolean,
          (v_item ->> 'presentationOrder')::bigint
        );
      end loop;
    end loop;

    update public.spike_spaces as space
    set revision = v_expected_revision_bigint + 1
    where space.account_id = p_account_id
      and space.id = p_space_id;

    update public.spike_space_core_details as detail
    set updated_at = v_completed_at,
        updated_at_ms = v_completed_at_ms
    where detail.account_id = p_account_id
      and detail.id = p_space_id;
  end if;

  if v_completed_at is null then
    v_completed_at := date_trunc('milliseconds', clock_timestamp());
    v_completed_at_ms :=
      floor(extract(epoch from v_completed_at) * 1000)::bigint;
  end if;

  insert into public.spike_operation_results (
    operation_id,
    account_id,
    actor_principal_id,
    command_type,
    contract_version,
    command_fingerprint,
    envelope_sha256,
    request_sha256,
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
    'revise_space_checklists',
    p_contract_version,
    p_fingerprint,
    v_envelope_sha256,
    v_request_sha256,
    p_space_id,
    case when v_error_code is null then 'applied' else 'rejected' end,
    case when v_error_code is null then 'space_checklists_revised' end,
    v_error_code,
    p_space_captured_at,
    v_received_at,
    v_completed_at,
    v_client_created_at_ms,
    v_received_at_ms,
    v_completed_at_ms
  )
  returning * into v_result;

  return v_result;
end
$$;

revoke all on function ledger_private.spike_revise_space_checklists(
  text, text, text, text, timestamptz, text, text, jsonb, text, text
) from public, anon, authenticated, service_role;

grant execute on function ledger_private.spike_revise_space_checklists(
  text, text, text, text, timestamptz, text, text, jsonb, text, text
) to authenticated;

create function public.spike_revise_space_checklists(
  p_operation_id text,
  p_account_id text,
  p_actor_principal_id text,
  p_contract_version text,
  p_space_captured_at timestamptz,
  p_space_id text,
  p_expected_revision text,
  p_collection jsonb,
  p_fingerprint text,
  p_envelope_json text
)
returns public.spike_operation_results
language sql
security invoker
set search_path = ''
as $$
  select ledger_private.spike_revise_space_checklists(
    p_operation_id,
    p_account_id,
    p_actor_principal_id,
    p_contract_version,
    p_space_captured_at,
    p_space_id,
    p_expected_revision,
    p_collection,
    p_fingerprint,
    p_envelope_json
  )
$$;

revoke all on function public.spike_revise_space_checklists(
  text, text, text, text, timestamptz, text, text, jsonb, text, text
) from public, anon, authenticated, service_role;

grant execute on function public.spike_revise_space_checklists(
  text, text, text, text, timestamptz, text, text, jsonb, text, text
) to authenticated;
