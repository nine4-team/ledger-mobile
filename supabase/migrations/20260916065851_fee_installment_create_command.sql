alter table public.spike_operation_results drop constraint spike_operation_results_command_type_check;
alter table public.spike_operation_results add constraint spike_operation_results_command_type_check check
 (command_type in ('create_client','create_project','archive_project','archive_client','revise_space_checklists','manage_categories','sell_inventory_items','create_expense','edit_expense','create_invoice','create_fee_installment'));

create function ledger_private.create_fee_installment(p_command text)
returns public.spike_operation_results language plpgsql security definer set search_path='' as $$
declare c jsonb:=p_command::jsonb; actor text; account text; operation text; fingerprint text;
  result public.spike_operation_results; received timestamptz:=clock_timestamp(); failure text;
  client text; cap bigint; cap_currency text; allocated numeric; amount bigint; ordering integer;
begin
  actor:=c->>'actorPrincipalId'; account:=c->>'accountId'; operation:=c->>'operationId';
  if (select auth.uid()) is null or actor is distinct from ledger_private.current_principal_id() then
    raise sqlstate '42501' using message='Authenticated actor required';
  end if;
  perform 1 from public.spike_account_memberships where account_id=account and principal_id=actor
    and state='active' and financial_access='full' for share;
  if not found then raise sqlstate '42501' using message='Fee access required'; end if;
  if current_setting('transaction_isolation')<>'read committed' then
    raise sqlstate '25001' using message='Fee writes require READ COMMITTED';
  end if;
  if jsonb_typeof(c) is distinct from 'object' or c->>'contractVersion' is distinct from 'fee-installment-create-v1'
    or not(c ?& array['operationId','accountId','actorPrincipalId','projectId','installmentId','categoryId','contractVersion','createdAtMs','label','amountMinorUnits','currency','sortOrder'])
    or c-array['operationId','accountId','actorPrincipalId','projectId','installmentId','categoryId','contractVersion','createdAtMs','label','amountMinorUnits','currency','sortOrder']<>'{}'::jsonb
    or exists(select 1 from jsonb_each(c) where jsonb_typeof(value)<>'string')
    or operation !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(operation)>128
    or c->>'createdAtMs' !~ '^(0|[1-9][0-9]*)$' or (c->>'createdAtMs')::numeric>=1000000000000000 then
    raise sqlstate '22023' using message='Invalid Fee creation command';
  end if;
  fingerprint:=encode(extensions.digest(convert_to(p_command,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(operation,0));
  select * into result from public.spike_operation_results where operation_id=operation;
  if found then
    if row(result.account_id,result.actor_principal_id,result.command_type,result.command_fingerprint)
      is distinct from row(account,actor,'create_fee_installment'::text,fingerprint) then
      raise sqlstate '23505' using message='Operation identity conflict';
    end if;
    return result;
  end if;
  begin
    if c->>'amountMinorUnits' !~ '^[1-9][0-9]*$' or c->>'currency' !~ '^[A-Z]{3}$'
      or c->>'label' !~ '[^[:space:]]'
      or (c->>'sortOrder'<>'' and c->>'sortOrder' !~ '^(0|-?[1-9][0-9]*)$') then
      raise exception 'fee_invalid_draft';
    end if;
    amount:=(c->>'amountMinorUnits')::bigint;
    ordering:=nullif(c->>'sortOrder','')::integer;
    select client_id into client from public.spike_projects where account_id=account and id=c->>'projectId'
      and lifecycle='active' for share;
    if not found then raise exception 'fee_project_unavailable'; end if;
    perform 1 from public.spike_clients where account_id=account and id=client and lifecycle='active' for share;
    if not found then raise exception 'fee_project_unavailable'; end if;
    -- Lock a stable existing row even when the Project has no allocation row.
    -- This serializes creators and category edits without locking source rows
    -- in the opposite order from Invoice collection. Re-read totals after waiting.
    perform 1 from public.spike_budget_categories where account_id=account and id=c->>'categoryId'
      and lifecycle='active' and kind='fee' for update;
    if not found then raise exception 'fee_category_unavailable'; end if;
    select allocation_minor_units,allocation_currency into cap,cap_currency
      from public.spike_project_category_allocations where account_id=account
        and project_id=c->>'projectId' and category_id=c->>'categoryId' for share;
    if cap is not null and cap_currency<>c->>'currency' then raise exception 'fee_currency_mismatch'; end if;
    if exists(select 1 from ledger_private.fee_installments where account_id=account
      and project_id=c->>'projectId' and category_id=c->>'categoryId' and currency<>c->>'currency') then
      raise exception 'fee_currency_mismatch';
    end if;
    -- Collected installments still consume the configured Fee total.
    select coalesce(sum(amount_minor_units),0) into allocated from ledger_private.fee_installments
      where account_id=account and project_id=c->>'projectId' and category_id=c->>'categoryId';
    if allocated+amount>9223372036854775807 then raise exception 'fee_total_overflow'; end if;
    if cap is not null and allocated+amount>cap then raise exception 'fee_total_exceeded'; end if;
    insert into ledger_private.fee_installments(id,account_id,project_id,category_id,label,amount_minor_units,
      currency,sort_order,created_at,created_by_principal_id)
    values(c->>'installmentId',account,c->>'projectId',c->>'categoryId',c->>'label',amount,c->>'currency',ordering,received,actor);
  exception
    when raise_exception then failure:=SQLERRM;
    when integrity_constraint_violation or numeric_value_out_of_range then failure:='fee_integrity_conflict';
  end;
  insert into public.spike_operation_results(operation_id,account_id,actor_principal_id,command_type,contract_version,
    command_fingerprint,envelope_sha256,subject_id,phase,result_code,error_code,client_created_at,server_received_at,
    completed_at,client_created_at_ms,server_received_at_ms,completed_at_ms)
  values(operation,account,actor,'create_fee_installment','fee-installment-create-v1',fingerprint,fingerprint,c->>'installmentId',
    case when failure is null then 'applied' else 'rejected' end,
    case when failure is null then 'fee_installment_created' end,failure,to_timestamp((c->>'createdAtMs')::bigint/1000.0),received,received,
    (c->>'createdAtMs')::bigint,floor(extract(epoch from received)*1000)::bigint,floor(extract(epoch from received)*1000)::bigint)
  returning * into result;
  return result;
end;
$$;
revoke all on function ledger_private.create_fee_installment(text) from public,anon,authenticated,service_role;
-- Private until scoped endpoint, offline queue and replay consumers are verified.
