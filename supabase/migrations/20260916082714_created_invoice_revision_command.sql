alter table public.spike_operation_results drop constraint spike_operation_results_command_type_check;
alter table public.spike_operation_results add constraint spike_operation_results_command_type_check check
 (command_type in ('create_client','create_project','archive_project','archive_client','revise_space_checklists','manage_categories','sell_inventory_items','create_expense','edit_expense','create_invoice','create_fee_installment','revise_created_invoice'));

-- One validator/lock path for initial and revised membership. Only scoped
-- private entry points execute this helper; callers cannot choose its mode.
create function ledger_private.apply_live_invoice(p_command text,p_revision boolean)
returns public.spike_operation_results language plpgsql security invoker set search_path='' as $$
declare c jsonb:=p_command::jsonb; actor text; account text; operation text; fingerprint text;
  result public.spike_operation_results; received timestamptz:=clock_timestamp(); failure text;
  source jsonb; source_revision bigint; source_amount bigint; source_currency text;
  total numeric:=0; currency text; client text; header ledger_private.live_invoices; next_revision bigint:=1;
  command_kind text:=case when p_revision then 'revise_created_invoice' else 'create_invoice' end;
  contract text:=case when p_revision then 'invoice-revise-created-v1' else 'invoice-create-v1' end;
  required text[]:=array['operationId','accountId','actorPrincipalId','projectId','clientId','invoiceId','contractVersion','createdAtMs','name','notes','sources'];
begin
  actor:=c->>'actorPrincipalId'; account:=c->>'accountId'; operation:=c->>'operationId';
  if (select auth.uid()) is null or actor is distinct from ledger_private.current_principal_id() then
    raise sqlstate '42501' using message='Authenticated actor required';
  end if;
  perform 1 from public.spike_account_memberships where account_id=account and principal_id=actor
    and state='active' and financial_access='full' for share;
  if not found then raise sqlstate '42501' using message='Invoice access required'; end if;
  if current_setting('transaction_isolation')<>'read committed' then
    raise sqlstate '25001' using message='Invoice writes require READ COMMITTED';
  end if;
  if p_revision then required:=required||array['expectedRevision']; end if;
  if jsonb_typeof(c) is distinct from 'object' or c->>'contractVersion' is distinct from contract
    or not(c ?& required) or c-required<>'{}'::jsonb
    or exists(select 1 from jsonb_each(c-'sources') where jsonb_typeof(value)<>'string')
    or operation !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(operation)>128
    or c->>'createdAtMs' !~ '^(0|[1-9][0-9]*)$' or (c->>'createdAtMs')::numeric>=1000000000000000
    or jsonb_typeof(c->'sources') is distinct from 'array' then
    raise sqlstate '22023' using message='Invalid Invoice creation command';
  end if;
  if p_revision and (c->>'expectedRevision' !~ '^[1-9][0-9]*$'
    or (c->>'expectedRevision')::numeric>=9223372036854775807) then
    raise sqlstate '22023' using message='Invalid Invoice revision';
  end if;
  fingerprint:=encode(extensions.digest(convert_to(p_command,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(operation,0));
  select * into result from public.spike_operation_results where operation_id=operation;
  if found then
    if row(result.account_id,result.actor_principal_id,result.command_type,result.command_fingerprint)
      is distinct from row(account,actor,command_kind,fingerprint) then
      raise sqlstate '23505' using message='Operation identity conflict';
    end if;
    return result;
  end if;
  begin
    select client_id into client from public.spike_projects where account_id=account and id=c->>'projectId'
      and lifecycle='active' for share;
    if not found or client is distinct from c->>'clientId' then raise exception 'invoice_project_unavailable'; end if;
    perform 1 from public.spike_clients where account_id=account and id=client and lifecycle='active' for share;
    if not found then raise exception 'invoice_project_unavailable'; end if;
    if p_revision then
      select * into header from ledger_private.live_invoices where account_id=account and id=c->>'invoiceId'
        and project_id=c->>'projectId' for update;
      if not found then raise exception 'invoice_unavailable'; end if;
      if header.status<>'created' or exists(select 1 from ledger_private.collected_invoices
        where account_id=account and id=header.id) then raise exception 'invoice_not_editable'; end if;
      if header.revision<>(c->>'expectedRevision')::bigint then raise exception 'invoice_revision_conflict'; end if;
      next_revision:=header.revision+1;
    end if;
    if jsonb_array_length(c->'sources')=0 then raise exception 'invoice_empty_selection'; end if;
    if exists(select 1 from jsonb_array_elements(c->'sources') s group by s->>'kind',s->>'sourceId' having count(*)>1)
      then raise exception 'invoice_duplicate_source'; end if;
    for source in select value from jsonb_array_elements(c->'sources') order by value->>'kind',value->>'sourceId' loop
      if jsonb_typeof(source) is distinct from 'object'
        or not(source ?& array['kind','sourceId','expectedRevision','amountMinorUnits','currency'])
        or source-array['kind','sourceId','expectedRevision','amountMinorUnits','currency']<>'{}'::jsonb
        or exists(select 1 from jsonb_each(source) where jsonb_typeof(value)<>'string')
        or source->>'kind' not in ('item','expense','fee_installment')
        or source->>'expectedRevision' !~ '^[1-9][0-9]*$'
        or source->>'amountMinorUnits' !~ '^(0|-?[1-9][0-9]*)$' then raise exception 'invoice_source_invalid'; end if;
      if source->>'kind'='item' then
        perform ledger_private.lock_item_charge_source(account,source->>'sourceId');
        select revision,amount_minor_units,i.currency into source_revision,source_amount,source_currency
          from ledger_private.item_charge_occurrences i where account_id=account and id=source->>'sourceId'
            and project_id=c->>'projectId' and withdrawn_at is null;
      elsif source->>'kind'='expense' then
        select revision,final_amount_minor_units,e.currency into source_revision,source_amount,source_currency
          from ledger_private.expenses e where account_id=account and id=source->>'sourceId'
            and project_id=c->>'projectId' for update;
      else
        select revision,amount_minor_units,f.currency into source_revision,source_amount,source_currency
          from ledger_private.fee_installments f where account_id=account and id=source->>'sourceId'
            and project_id=c->>'projectId' for update;
      end if;
      if not found then raise exception 'invoice_source_unavailable'; end if;
      if row(source_revision,source_amount,source_currency) is distinct from
        row((source->>'expectedRevision')::bigint,(source->>'amountMinorUnits')::bigint,source->>'currency') then
        raise exception 'invoice_source_changed';
      end if;
      if exists(select 1 from ledger_private.collected_invoice_lines where account_id=account
          and source_kind=source->>'kind' and source_id=source->>'sourceId') then raise exception 'invoice_source_collected'; end if;
      if exists(select 1 from ledger_private.live_invoice_memberships where account_id=account
          and source_kind=source->>'kind' and source_id=source->>'sourceId' and released_at is null
          and (not p_revision or invoice_id<>header.id)) then raise exception 'invoice_source_reserved'; end if;
      if currency is not null and currency<>source_currency then raise exception 'invoice_currency_mismatch'; end if;
      currency:=source_currency; total:=total+source_amount;
    end loop;
    if total < -9223372036854775808 or total > 9223372036854775807 then raise exception 'invoice_total_overflow'; end if;
    if p_revision then
      update ledger_private.live_invoice_memberships set released_at=received
        where account_id=account and invoice_id=header.id and released_at is null;
      update ledger_private.live_invoices set name=c->>'name',notes=c->>'notes',revision=next_revision
        where account_id=account and id=header.id;
    else
      insert into ledger_private.live_invoices(id,account_id,project_id,name,notes,created_at,created_by_principal_id)
        values(c->>'invoiceId',account,c->>'projectId',c->>'name',c->>'notes',received,actor);
    end if;
    insert into ledger_private.live_invoice_memberships(account_id,invoice_id,source_kind,source_id,position,joined_at_revision)
      select account,c->>'invoiceId',value->>'kind',value->>'sourceId',(ordinality-1)::integer,next_revision
      from jsonb_array_elements(c->'sources') with ordinality;
  exception
    when raise_exception then failure:=SQLERRM;
    when integrity_constraint_violation or numeric_value_out_of_range then failure:='invoice_integrity_conflict';
  end;
  insert into public.spike_operation_results(operation_id,account_id,actor_principal_id,command_type,contract_version,
    command_fingerprint,envelope_sha256,subject_id,phase,result_code,error_code,client_created_at,server_received_at,
    completed_at,client_created_at_ms,server_received_at_ms,completed_at_ms)
  values(operation,account,actor,command_kind,contract,fingerprint,fingerprint,c->>'invoiceId',
    case when failure is null then 'applied' else 'rejected' end,
    case when failure is null then case when p_revision then 'invoice_revised' else 'invoice_created' end end,
    failure,to_timestamp((c->>'createdAtMs')::bigint/1000.0),received,received,
    (c->>'createdAtMs')::bigint,floor(extract(epoch from received)*1000)::bigint,floor(extract(epoch from received)*1000)::bigint)
  returning * into result;
  return result;
end;
$$;
revoke all on function ledger_private.apply_live_invoice(text,boolean) from public,anon,authenticated,service_role;
create or replace function ledger_private.create_live_invoice(p_command text)
returns public.spike_operation_results language sql security definer set search_path='' as $$
  select ledger_private.apply_live_invoice(p_command,false)
$$;
create function ledger_private.revise_created_invoice(p_command text)
returns public.spike_operation_results language sql security definer set search_path='' as $$
  select ledger_private.apply_live_invoice(p_command,true)
$$;
revoke all on function ledger_private.revise_created_invoice(text) from public,anon,authenticated,service_role;
