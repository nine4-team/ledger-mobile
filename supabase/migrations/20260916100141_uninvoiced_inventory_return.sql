-- One return fact links the retained charge to its successor Inventory placement.
-- No monetary copy, negative demand, Invoice or payment is created.
create table ledger_private.uninvoiced_item_returns (
  id text primary key check(id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id)<=128),
  account_id text not null,
  charge_id text not null,
  inventory_placement_id text not null,
  item_id text not null,
  unique(account_id,charge_id),
  unique(account_id,inventory_placement_id),
  foreign key(account_id,charge_id) references ledger_private.item_charge_occurrences(account_id,id),
  foreign key(account_id,inventory_placement_id,item_id) references public.spike_item_placements(account_id,id,item_id)
);
alter table ledger_private.uninvoiced_item_returns enable row level security;
revoke all on ledger_private.uninvoiced_item_returns from public,anon,authenticated,service_role;
create function ledger_private.guard_uninvoiced_item_return() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  raise sqlstate '55000' using message='Item return provenance is immutable';
end;
$$;
revoke all on function ledger_private.guard_uninvoiced_item_return() from public,anon,authenticated,service_role;
create trigger uninvoiced_return_history before update or delete on ledger_private.uninvoiced_item_returns
for each row execute function ledger_private.guard_uninvoiced_item_return();
create trigger uninvoiced_return_no_truncate before truncate on ledger_private.uninvoiced_item_returns
for each statement execute function ledger_private.guard_uninvoiced_item_return();

alter table public.spike_operation_results drop constraint spike_operation_results_command_type_check;
alter table public.spike_operation_results add constraint spike_operation_results_command_type_check check
 (command_type in ('create_client','create_project','archive_project','archive_client','revise_space_checklists','manage_categories','sell_inventory_items','create_expense','edit_expense','create_invoice','create_fee_installment','revise_created_invoice','return_uninvoiced_items'));

create function ledger_private.return_uninvoiced_items(p_command text)
returns public.spike_operation_results language plpgsql security definer set search_path='' as $$
declare c jsonb:=p_command::jsonb; actor text; account text; operation text; fingerprint text;
  entry jsonb; result public.spike_operation_results; failure text; client text;
  charge ledger_private.item_charge_occurrences; placement public.spike_item_placements;
  received timestamptz;
begin
  if current_setting('transaction_isolation')<>'read committed' then
    raise sqlstate '25001' using message='Return requires READ COMMITTED';
  end if;
  actor:=c->>'actorPrincipalId'; account:=c->>'accountId'; operation:=c->>'operationId';
  if (select auth.uid()) is null or actor is distinct from ledger_private.current_principal_id() then
    raise sqlstate '42501' using message='Authenticated actor required';
  end if;
  perform 1 from public.spike_account_memberships where account_id=account and principal_id=actor
    and state='active' for share;
  if not found then raise sqlstate '42501' using message='Active Account membership required'; end if;
  if jsonb_typeof(c) is distinct from 'object' or c->>'contractVersion' is distinct from 'return-uninvoiced-items-v1'
    or not(c ?& array['operationId','accountId','actorPrincipalId','projectId','contractVersion','createdAtMs','items'])
    or c-array['operationId','accountId','actorPrincipalId','projectId','contractVersion','createdAtMs','items']<>'{}'::jsonb
    or exists(select 1 from jsonb_each(c-'items') where jsonb_typeof(value)<>'string')
    or operation !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(operation)>128
    or c->>'createdAtMs' !~ '^(0|[1-9][0-9]*)$' or (c->>'createdAtMs')::numeric>=1000000000000000
    or jsonb_typeof(c->'items') is distinct from 'array' or jsonb_array_length(c->'items') not between 1 and 500 then
    raise sqlstate '22023' using message='Invalid uninvoiced return command';
  end if;
  fingerprint:=encode(extensions.digest(convert_to(p_command,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(operation,0));
  select * into result from public.spike_operation_results where operation_id=operation;
  if found then
    if row(result.account_id,result.actor_principal_id,result.command_type,result.command_fingerprint)
      is distinct from row(account,actor,'return_uninvoiced_items'::text,fingerprint) then
      raise sqlstate '23505' using message='Operation identity conflict';
    end if;
    return result;
  end if;
  begin
    select client_id into client from public.spike_projects where account_id=account and id=c->>'projectId'
      and lifecycle='active' for share;
    if not found then raise exception 'return_project_unavailable'; end if;
    perform 1 from public.spike_clients where account_id=account and id=client and lifecycle='active' for share;
    if not found then raise exception 'return_project_unavailable'; end if;
    for entry in select value from jsonb_array_elements(c->'items') order by value->>'itemId' collate "C" loop
      if jsonb_typeof(entry) is distinct from 'object'
        or not(entry ?& array['itemId','placementId','chargeId','expectedChargeRevision','inventoryPlacementId','returnOccurrenceId'])
        or entry-array['itemId','placementId','chargeId','expectedChargeRevision','inventoryPlacementId','returnOccurrenceId']<>'{}'::jsonb
        or exists(select 1 from jsonb_each(entry) where jsonb_typeof(value)<>'string')
        or exists(select 1 from jsonb_each_text(entry-'expectedChargeRevision')
          where value !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(value)>128)
        or entry->>'expectedChargeRevision' !~ '^[1-9][0-9]*$'
        or (entry->>'expectedChargeRevision')::numeric>=9223372036854775807 then raise exception 'return_item_invalid'; end if;
      perform 1 from public.spike_items where account_id=account and id=entry->>'itemId' for update;
      if not found then raise exception 'return_item_unavailable'; end if;
    end loop;
    if exists(select 1 from jsonb_array_elements(c->'items') group by value->>'itemId' having count(*)>1) then
      raise exception 'return_duplicate_item';
    end if;
    -- Same source-lock order as Invoice creation/revision, before any mutation.
    for entry in select value from jsonb_array_elements(c->'items') order by value->>'chargeId' loop
      perform ledger_private.lock_item_charge_source(account,entry->>'chargeId');
    end loop;
    received:=clock_timestamp();
    for entry in select value from jsonb_array_elements(c->'items') order by value->>'itemId' collate "C" loop
      select * into placement from public.spike_item_placements where account_id=account
        and id=entry->>'placementId' and item_id=entry->>'itemId' and project_id=c->>'projectId'
        and scope_kind='project' and ended_at is null for update;
      if not found or placement.started_at>=received then raise exception 'return_placement_stale'; end if;
      select * into charge from ledger_private.item_charge_occurrences where account_id=account
        and id=entry->>'chargeId' and item_id=placement.item_id and placement_id=placement.id
        and project_id=placement.project_id and withdrawn_at is null for update;
      if not found or charge.revision::text<>entry->>'expectedChargeRevision' then raise exception 'return_charge_stale'; end if;
      if not ledger_private.can_view_budget_category(account,(select visibility_class from public.spike_budget_categories
        where account_id=account and id=charge.category_id)) then raise exception 'return_charge_unavailable'; end if;
      if exists(select 1 from ledger_private.live_invoice_memberships where account_id=account
        and source_kind='item' and source_id=charge.id and released_at is null) then raise exception 'return_charge_invoiced'; end if;
      if exists(select 1 from ledger_private.collected_invoice_lines where account_id=account
        and source_kind='item' and source_id=charge.id) then raise exception 'return_charge_collected'; end if;
      if placement.start_evidence<>'recorded_move' or not exists(select 1 from public.spike_item_placements
        where account_id=account and item_id=placement.item_id and scope_kind='business_inventory'
          and ended_at=placement.started_at) then raise exception 'return_origin_unproven'; end if;
      update ledger_private.item_charge_occurrences set withdrawn_at=received,withdrawn_by_principal_id=actor,
        revision=revision+1 where account_id=account and id=charge.id;
      update public.spike_item_placements set ended_at=received,ended_by_principal_id=actor where id=placement.id;
      insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id)
        values(entry->>'inventoryPlacementId',account,placement.item_id,'business_inventory',received,actor);
      insert into ledger_private.uninvoiced_item_returns(id,account_id,charge_id,inventory_placement_id,item_id)
        values(entry->>'returnOccurrenceId',account,charge.id,entry->>'inventoryPlacementId',placement.item_id);
    end loop;
  exception
    when raise_exception then failure:=SQLERRM;
    when integrity_constraint_violation or numeric_value_out_of_range then failure:='return_integrity_conflict';
  end;
  received:=coalesce(received,clock_timestamp());
  insert into public.spike_operation_results(operation_id,account_id,actor_principal_id,command_type,contract_version,
    command_fingerprint,envelope_sha256,subject_id,phase,result_code,error_code,client_created_at,server_received_at,
    completed_at,client_created_at_ms,server_received_at_ms,completed_at_ms)
  values(operation,account,actor,'return_uninvoiced_items','return-uninvoiced-items-v1',fingerprint,fingerprint,c->>'projectId',
    case when failure is null then 'applied' else 'rejected' end,
    case when failure is null then 'uninvoiced_items_returned' end,failure,
    to_timestamp((c->>'createdAtMs')::bigint/1000.0),received,received,(c->>'createdAtMs')::bigint,
    floor(extract(epoch from received)*1000)::bigint,floor(extract(epoch from received)*1000)::bigint)
  returning * into result;
  return result;
end;
$$;
revoke all on function ledger_private.return_uninvoiced_items(text) from public,anon,authenticated,service_role;
