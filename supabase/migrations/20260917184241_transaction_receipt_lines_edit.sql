-- Internal until native/MCP/offline integration is verified. No direct writes.
alter table public.spike_operation_results drop constraint spike_operation_results_command_type_check;
alter table public.spike_operation_results add constraint spike_operation_results_command_type_check check
 (command_type in ('create_client','create_project','archive_project','archive_client','revise_space_checklists','manage_categories','sell_inventory_items','create_expense','edit_expense','create_invoice','create_fee_installment','revise_created_invoice','return_uninvoiced_items','edit_uncollected_item_price','edit_item_details','return_paid_items','assign_items_to_space','clear_item_space_assignments','edit_transaction_details','edit_transaction_receipt_lines'));

create function ledger_private.edit_transaction_receipt_lines(p_command text)
returns public.spike_operation_results language plpgsql security definer set search_path='' as $$
declare
  c jsonb:=p_command::jsonb; account text:=c->>'accountId'; actor text:=c->>'actorPrincipalId';
  operation text:=c->>'operationId'; received timestamptz:=clock_timestamp();
  payment public.spike_transactions; category public.spike_budget_categories;
  result public.spike_operation_results; digest text; failure text;
  required text[]:=array['operationId','accountId','actorPrincipalId','contractVersion','createdAtMs',
    'transactionId','scopeKind','projectId','clientId','currency','expectedLines','lines'];
begin
  if current_setting('transaction_isolation')<>'read committed' then
    raise sqlstate '25001' using message='Receipt edits require READ COMMITTED';
  end if;
  if (select auth.uid()) is null or actor is distinct from ledger_private.current_principal_id() then
    raise sqlstate '42501' using message='Authenticated actor required';
  end if;
  perform 1 from public.spike_account_memberships where account_id=account and principal_id=actor
    and state='active' for share;
  if not found then raise sqlstate '42501' using message='Receipt edit access required'; end if;
  if octet_length(p_command)>4194304 or jsonb_typeof(c) is distinct from 'object'
    or not(c ?& required) or c-required<>'{}'
    or c->>'contractVersion' is distinct from 'transaction-receipt-lines-edit-v1'
    or exists(select 1 from jsonb_each(c-array['expectedLines','lines','projectId','clientId']) where jsonb_typeof(value)<>'string')
    or exists(select 1 from jsonb_each_text(c-array['expectedLines','lines','projectId','clientId','contractVersion','createdAtMs','scopeKind','currency'])
      where value !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(value)>128)
    or c->>'createdAtMs' !~ '^(0|[1-9][0-9]*)$' or (c->>'createdAtMs')::numeric>=1000000000000000
    or c->>'currency' !~ '^[A-Z]{3}$'
    or c->>'scopeKind' not in ('project','business_inventory')
    or (c->>'scopeKind'='business_inventory' and (c->'projectId'<>'null' or c->'clientId'<>'null'))
    or (c->>'scopeKind'='project' and (jsonb_typeof(c->'projectId')<>'string' or jsonb_typeof(c->'clientId')<>'string'))
    or exists(select 1 from jsonb_each_text(c) where key in ('projectId','clientId') and value is not null
      and (value !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(value)>128))
    or not ledger_private.valid_non_item_receipt_lines(c->'expectedLines')
    or not ledger_private.valid_non_item_receipt_lines(c->'lines') then
    raise sqlstate '22023' using message='Invalid receipt edit command';
  end if;
  digest:=encode(extensions.digest(convert_to(p_command,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(operation,0));
  select * into payment from public.spike_transactions where account_id=account and id=c->>'transactionId' for update;
  if not found or payment.origin<>'vendor_payment'
    or row(payment.scope_kind,payment.project_id,payment.client_id,payment.currency)
       is distinct from row(c->>'scopeKind',c->>'projectId',c->>'clientId',c->>'currency') then
    raise sqlstate '42501' using message='Receipt edit unavailable';
  end if;
  select * into category from public.spike_budget_categories where account_id=account and id=payment.category_id for share;
  if not found or not ledger_private.can_view_budget_category(account,category.visibility_class) then
    raise sqlstate '42501' using message='Receipt edit unavailable';
  end if;
  select * into result from public.spike_operation_results where operation_id=operation;
  if found then
    if row(result.account_id,result.actor_principal_id,result.command_type,result.command_fingerprint)
      is distinct from row(account,actor,'edit_transaction_receipt_lines',digest) then
      raise sqlstate '23505' using message='Operation identity conflict';
    end if;
    return result;
  end if;
  begin
    -- Absent optional quantity and explicit null carry identical meaning.
    -- Array order, stable IDs and all actual source values remain significant.
    if exists(select 1
      from jsonb_array_elements(payment.non_item_receipt_lines) with ordinality p(value,position)
      full join jsonb_array_elements(c->'expectedLines') with ordinality e(value,position) using(position)
      where p.value-'quantity' is distinct from e.value-'quantity'
        or (p.value->>'quantity')::bigint is distinct from (e.value->>'quantity')::bigint) then
      raise exception 'transaction_receipt_edit_stale';
    end if;
    update public.spike_transactions set non_item_receipt_lines=c->'lines'
      where account_id=account and id=payment.id;
  exception when raise_exception then failure:=SQLERRM;
    when integrity_constraint_violation or numeric_value_out_of_range then failure:='transaction_receipt_edit_integrity_conflict';
  end;
  insert into public.spike_operation_results(operation_id,account_id,actor_principal_id,command_type,contract_version,
    command_fingerprint,envelope_sha256,subject_id,phase,result_code,error_code,client_created_at,server_received_at,
    completed_at,client_created_at_ms,server_received_at_ms,completed_at_ms)
  values(operation,account,actor,'edit_transaction_receipt_lines','transaction-receipt-lines-edit-v1',digest,digest,payment.id,
    case when failure is null then 'applied' else 'rejected' end,
    case when failure is null then 'transaction_receipt_lines_updated' end,failure,
    to_timestamp((c->>'createdAtMs')::numeric/1000),received,received,(c->>'createdAtMs')::bigint,
    floor(extract(epoch from received)*1000)::bigint,floor(extract(epoch from received)*1000)::bigint)
    returning * into result;
  return result;
end;
$$;
revoke all on function ledger_private.edit_transaction_receipt_lines(text) from public,anon,authenticated,service_role;
