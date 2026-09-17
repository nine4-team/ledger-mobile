-- Internal handler first. Public execution follows authorization/race checks.
alter table public.spike_operation_results drop constraint spike_operation_results_command_type_check;
alter table public.spike_operation_results add constraint spike_operation_results_command_type_check check
 (command_type in ('create_client','create_project','archive_project','archive_client','revise_space_checklists','manage_categories','sell_inventory_items','create_expense','edit_expense','create_invoice','create_fee_installment','revise_created_invoice','return_uninvoiced_items','edit_uncollected_item_price','edit_item_details'));

create function ledger_private.edit_item_details(p_command text)
returns public.spike_operation_results language plpgsql security definer set search_path='' as $$
declare
  c jsonb:=p_command::jsonb; changes jsonb:=c->'changes'; selected jsonb;
  account text:=c->>'accountId'; actor text:=c->>'actorPrincipalId'; operation text:=c->>'operationId';
  digest text; result public.spike_operation_results; failure text;
  received timestamptz:=clock_timestamp(); item public.spike_items; subject text;
  required text[]:=array['operationId','accountId','actorPrincipalId','contractVersion','createdAtMs','items','changes'];
begin
  if current_setting('transaction_isolation')<>'read committed' then
    raise sqlstate '25001' using message='Item edits require READ COMMITTED';
  end if;
  if (select auth.uid()) is null or actor is distinct from ledger_private.current_principal_id() then
    raise sqlstate '42501' using message='Authenticated actor required';
  end if;
  perform 1 from public.spike_account_memberships where account_id=account and principal_id=actor
    and state='active' for share;
  if not found then raise sqlstate '42501' using message='Item edit access required'; end if;
  if jsonb_typeof(c) is distinct from 'object' or not(c ?& required) or c-required<>'{}'
    or c->>'contractVersion' is distinct from 'item-details-edit-v1'
    or exists(select 1 from jsonb_each(c-array['items','changes']) where jsonb_typeof(value)<>'string')
    or exists(select 1 from jsonb_each_text(c-array['items','changes','contractVersion','createdAtMs'])
      where value !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(value)>128)
    or c->>'createdAtMs' !~ '^(0|[1-9][0-9]*)$' or (c->>'createdAtMs')::numeric>=1000000000000000
    or jsonb_typeof(c->'items') is distinct from 'array' or jsonb_array_length(c->'items')=0
    or jsonb_typeof(changes) is distinct from 'object' or changes='{}'
    or changes-array['name','sku','notes','status','bookmark']<>'{}' then
    raise sqlstate '22023' using message='Invalid Item edit command';
  end if;
  if exists(select 1 from jsonb_each(changes) where
    (key in ('name','sku','notes') and jsonb_typeof(value) not in ('string','null'))
    or (key='bookmark' and jsonb_typeof(value)<>'boolean')
    or (key='status' and value not in ('null','"to purchase"','"purchased"','"to return"','"returned"')))
    or (jsonb_array_length(c->'items')>1 and changes-'status'<>'{}') then
    raise sqlstate '22023' using message='Invalid Item field changes';
  end if;
  for selected in select value from jsonb_array_elements(c->'items') loop
    if jsonb_typeof(selected) is distinct from 'object' or not(selected ?& array['itemId','expectedRevision'])
      or selected-array['itemId','expectedRevision']<>'{}'
      or exists(select 1 from jsonb_each(selected) where jsonb_typeof(value)<>'string')
      or selected->>'itemId' !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(selected->>'itemId')>128
      or selected->>'expectedRevision' !~ '^[1-9][0-9]*$'
      or (selected->>'expectedRevision')::numeric>=9223372036854775807 then
      raise sqlstate '22023' using message='Invalid Item selection';
    end if;
  end loop;
  if (select count(distinct value->>'itemId') from jsonb_array_elements(c->'items'))<>jsonb_array_length(c->'items') then
    raise sqlstate '22023' using message='Duplicate Item selection';
  end if;
  subject:=c->'items'->0->>'itemId';
  digest:=encode(extensions.digest(convert_to(p_command,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(operation,0));
  select * into result from public.spike_operation_results where operation_id=operation;
  if found then
    if row(result.account_id,result.actor_principal_id,result.command_type,result.command_fingerprint)
      is distinct from row(account,actor,'edit_item_details',digest) then
      raise sqlstate '23505' using message='Operation identity conflict';
    end if;
    return result;
  end if;
  begin
    -- Stable order prevents overlapping bulk selections from reversing locks.
    for selected in select value from jsonb_array_elements(c->'items') order by value->>'itemId' loop
      select * into item from public.spike_items where account_id=account and id=selected->>'itemId' for update;
      if not found then raise exception 'item_edit_unavailable'; end if;
      if item.revision<>(selected->>'expectedRevision')::bigint then raise exception 'item_edit_stale'; end if;
      -- No accounting tables are updated, including when a workflow label is cleared.
      update public.spike_items set
        name=case when changes?'name' then changes->>'name' else item.name end,
        sku=case when changes?'sku' then changes->>'sku' else item.sku end,
        notes=case when changes?'notes' then changes->>'notes' else item.notes end,
        workflow_status=case when changes?'status' then changes->>'status' else item.workflow_status end,
        bookmark=case when changes?'bookmark' then (changes->>'bookmark')::boolean else item.bookmark end,
        revision=revision+1 where account_id=account and id=item.id;
    end loop;
  exception when raise_exception then failure:=SQLERRM;
    when integrity_constraint_violation or numeric_value_out_of_range then failure:='item_edit_integrity_conflict';
  end;
  insert into public.spike_operation_results(operation_id,account_id,actor_principal_id,command_type,contract_version,
    command_fingerprint,envelope_sha256,subject_id,phase,result_code,error_code,client_created_at,server_received_at,
    completed_at,client_created_at_ms,server_received_at_ms,completed_at_ms)
  values(operation,account,actor,'edit_item_details','item-details-edit-v1',digest,digest,subject,
    case when failure is null then 'applied' else 'rejected' end,
    case when failure is null then 'item_details_updated' end,failure,
    to_timestamp((c->>'createdAtMs')::numeric/1000),received,received,(c->>'createdAtMs')::bigint,
    floor(extract(epoch from received)*1000)::bigint,floor(extract(epoch from received)*1000)::bigint)
  returning * into result;
  return result;
end;
$$;
revoke all on function ledger_private.edit_item_details(text) from public,anon,authenticated,service_role;
