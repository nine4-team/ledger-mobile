-- Internal handler only until transport, races and photo-marker integration pass.
alter table public.spike_operation_results drop constraint spike_operation_results_command_type_check;
alter table public.spike_operation_results add constraint spike_operation_results_command_type_check check
 (command_type in ('create_client','create_project','archive_project','archive_client','revise_space_checklists','manage_categories','sell_inventory_items','create_expense','edit_expense','create_invoice','create_fee_installment','revise_created_invoice','return_uninvoiced_items','edit_uncollected_item_price','edit_item_details','return_paid_items','assign_items_to_space','clear_item_space_assignments'));

create function ledger_private.set_item_spaces(p_command text)
returns public.spike_operation_results language plpgsql security definer set search_path='' as $$
declare c jsonb:=p_command::jsonb; selected jsonb; actor text:=c->>'actorPrincipalId';
  account text:=c->>'accountId'; operation text:=c->>'operationId'; destination text:=c->>'destinationSpaceId';
  command_type text; digest text; result public.spike_operation_results; failure text;
  received timestamptz:=clock_timestamp(); placement public.spike_item_placements; destination_row public.spike_spaces;
  version bigint; required text[]:=array['operationId','accountId','actorPrincipalId','contractVersion','createdAtMs',
    'scopeKind','projectId','destinationSpaceId','expectedSpaceRevision','items'];
begin
  if current_setting('transaction_isolation')<>'read committed' then
    raise sqlstate '25001' using message='Space changes require READ COMMITTED';
  end if;
  if (select auth.uid()) is null or actor is distinct from ledger_private.current_principal_id() then
    raise sqlstate '42501' using message='Authenticated actor required';
  end if;
  perform 1 from public.spike_account_memberships where account_id=account and principal_id=actor and state='active' for share;
  if not found then raise sqlstate '42501' using message='Active Account membership required'; end if;
  if octet_length(p_command)>4194304 or jsonb_typeof(c) is distinct from 'object'
    or not(c ?& required) or c-required<>'{}'
    or c->>'contractVersion' is distinct from 'item-space-v1'
    or c->>'scopeKind' not in ('project','business_inventory')
    or jsonb_typeof(c->'scopeKind') is distinct from 'string'
    or exists(select 1 from jsonb_each(c-array['projectId','destinationSpaceId','expectedSpaceRevision','items']) where jsonb_typeof(value)<>'string')
    or exists(select 1 from jsonb_each_text(c-array['projectId','destinationSpaceId','expectedSpaceRevision','items','createdAtMs','contractVersion','scopeKind'])
      where value !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(value)>128)
    or c->>'createdAtMs' !~ '^(0|[1-9][0-9]*)$' or (c->>'createdAtMs')::numeric>=1000000000000000
    or jsonb_typeof(c->'items') is distinct from 'array' or jsonb_array_length(c->'items')=0 then
    raise sqlstate '22023' using message='Invalid Space command';
  end if;
  if (c->>'scopeKind'='project' and (jsonb_typeof(c->'projectId') is distinct from 'string'
        or c->>'projectId' !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(c->>'projectId')>128))
    or (c->>'scopeKind'='business_inventory' and c->'projectId'<>'null') then
    raise sqlstate '22023' using message='Invalid placement scope';
  end if;
  if destination is null then
    if c->'destinationSpaceId'<>'null' or c->'expectedSpaceRevision'<>'null' then
      raise sqlstate '22023' using message='Clear has no destination revision';
    end if;
    command_type:='clear_item_space_assignments';
  else
    if jsonb_typeof(c->'destinationSpaceId')<>'string' or destination !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
      or octet_length(destination)>128 or jsonb_typeof(c->'expectedSpaceRevision') is distinct from 'string'
      or c->>'expectedSpaceRevision' !~ '^[1-9][0-9]*$' or (c->>'expectedSpaceRevision')::numeric>=9223372036854775807 then
      raise sqlstate '22023' using message='Invalid destination revision';
    end if;
    command_type:='assign_items_to_space';
  end if;
  for selected in select value from jsonb_array_elements(c->'items') loop
    if jsonb_typeof(selected) is distinct from 'object' or not(selected ?& array['itemId','expectedRevision','currentSpaceId'])
      or selected-array['itemId','expectedRevision','currentSpaceId']<>'{}'
      or jsonb_typeof(selected->'itemId') is distinct from 'string'
      or selected->>'itemId' !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(selected->>'itemId')>128
      or jsonb_typeof(selected->'expectedRevision') is distinct from 'string'
      or selected->>'expectedRevision' !~ '^[1-9][0-9]*$' or (selected->>'expectedRevision')::numeric>=9223372036854775807
      or (destination is null and (jsonb_typeof(selected->'currentSpaceId') is distinct from 'string'
        or selected->>'currentSpaceId' !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(selected->>'currentSpaceId')>128))
      or (destination is not null and selected->'currentSpaceId'<>'null') then
      raise sqlstate '22023' using message='Invalid Item placement selection';
    end if;
  end loop;
  if (select count(distinct value->>'itemId') from jsonb_array_elements(c->'items'))<>jsonb_array_length(c->'items') then
    raise sqlstate '22023' using message='Duplicate Item selection';
  end if;
  digest:=encode(extensions.digest(convert_to(p_command,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(operation,0));
  select * into result from public.spike_operation_results where operation_id=operation;
  if found then
    if row(result.account_id,result.actor_principal_id,result.command_type,result.command_fingerprint)
      is distinct from row(account,actor,command_type,digest) then
      raise sqlstate '23505' using message='Operation identity conflict';
    end if;
    return result;
  end if;
  begin
    if c->>'scopeKind'='project' then
      perform 1 from public.spike_projects where account_id=account and id=c->>'projectId' and lifecycle='active' for share;
      if not found then raise exception 'space_scope_unavailable'; end if;
    end if;
    -- Match movement writers: stable physical Item locks before placement edits.
    for selected in select value from jsonb_array_elements(c->'items') order by value->>'itemId' collate "C" loop
      perform 1 from public.spike_items where account_id=account and id=selected->>'itemId' for update;
      if not found then raise exception 'space_item_unavailable'; end if;
    end loop;
    -- Lock all old and new Spaces in one order before the count trigger runs.
    perform 1 from public.spike_spaces s where s.account_id=account and
      (s.id=destination or s.id in (select p.space_id from public.spike_item_placements p
        where p.account_id=account and p.ended_at is null and p.item_id in
          (select value->>'itemId' from jsonb_array_elements(c->'items'))))
      order by s.id collate "C" for update;
    if destination is not null then
      select * into destination_row from public.spike_spaces where account_id=account and id=destination;
      if not found or destination_row.lifecycle<>'active' or destination_row.scope_kind<>c->>'scopeKind'
        or destination_row.project_id is distinct from c->>'projectId' then raise exception 'space_destination_unavailable'; end if;
      if destination_row.revision<>(c->>'expectedSpaceRevision')::bigint then raise exception 'space_destination_stale'; end if;
    end if;
    for selected in select value from jsonb_array_elements(c->'items') order by value->>'itemId' collate "C" loop
      select * into placement from public.spike_item_placements where account_id=account and item_id=selected->>'itemId' and ended_at is null for update;
      if not found or placement.scope_kind<>c->>'scopeKind' or placement.project_id is distinct from c->>'projectId' then
        raise exception 'space_item_scope_changed';
      end if;
      select revision into version from public.item_placement_versions where account_id=account and id=placement.item_id;
      if version is distinct from (selected->>'expectedRevision')::bigint
        or (destination is null and placement.space_id is distinct from selected->>'currentSpaceId') then
        raise exception 'space_item_stale';
      end if;
      if placement.space_id is distinct from destination then
        update public.spike_item_placements set space_id=destination where id=placement.id;
      end if;
    end loop;
  exception when raise_exception then failure:=SQLERRM;
    when integrity_constraint_violation or numeric_value_out_of_range then failure:='space_assignment_integrity_conflict';
  end;
  insert into public.spike_operation_results(operation_id,account_id,actor_principal_id,command_type,contract_version,
    command_fingerprint,envelope_sha256,subject_id,phase,result_code,error_code,client_created_at,server_received_at,
    completed_at,client_created_at_ms,server_received_at_ms,completed_at_ms)
  values(operation,account,actor,command_type,'item-space-v1',digest,digest,coalesce(destination,c->'items'->0->>'itemId'),
    case when failure is null then 'applied' else 'rejected' end,case when failure is null then 'item_spaces_updated' end,failure,
    to_timestamp((c->>'createdAtMs')::numeric/1000),received,received,(c->>'createdAtMs')::bigint,
    floor(extract(epoch from received)*1000)::bigint,floor(extract(epoch from received)*1000)::bigint)
    returning * into result;
  return result;
end;
$$;
revoke all on function ledger_private.set_item_spaces(text) from public,anon,authenticated,service_role;
