alter table public.spike_operation_results drop constraint spike_operation_results_command_type_check;
alter table public.spike_operation_results add constraint spike_operation_results_command_type_check check
 (command_type in ('create_client','create_project','archive_project','archive_client','revise_space_checklists','manage_categories','sell_inventory_items','create_expense','edit_expense'));

create function ledger_private.edit_expense(p_command text)
returns public.spike_operation_results language plpgsql security definer set search_path='' as $$
declare c jsonb:=p_command::jsonb; actor text; account text; operation text; fingerprint text;
  result public.spike_operation_results; source ledger_private.expenses; client text;
  received timestamptz:=clock_timestamp(); failure text; entry jsonb; attachments jsonb;
begin
  actor:=c->>'actorPrincipalId'; account:=c->>'accountId'; operation:=c->>'operationId';
  if (select auth.uid()) is null or actor is distinct from ledger_private.current_principal_id() then
    raise sqlstate '42501' using message='Authenticated actor required';
  end if;
  perform 1 from public.spike_account_memberships where account_id=account and principal_id=actor
    and state='active' and financial_access='full' for share;
  if not found then raise sqlstate '42501' using message='Expense access required'; end if;
  if jsonb_typeof(c) is distinct from 'object' or c->>'contractVersion' is distinct from 'expense-edit-v1'
    or not(c ?& array['operationId','accountId','actorPrincipalId','projectId','expenseId','contractVersion','createdAtMs','vendor','date','amountMinorUnits','currency','categoryId','notes','receiptLines','receiptAttachmentIds','expectedRevision'])
    or c-array['operationId','accountId','actorPrincipalId','projectId','expenseId','contractVersion','createdAtMs','vendor','date','amountMinorUnits','currency','categoryId','notes','receiptLines','receiptAttachmentIds','expectedRevision']<>'{}'::jsonb
    or exists(select 1 from jsonb_each(c-array['receiptLines','receiptAttachmentIds']) where jsonb_typeof(value)<>'string')
    or operation !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(operation)>128
    or c->>'createdAtMs' !~ '^(0|[1-9][0-9]*)$' or (c->>'createdAtMs')::numeric>=1000000000000000
    or c->>'expectedRevision' !~ '^[1-9][0-9]*$' or (c->>'expectedRevision')::numeric>=9223372036854775807
    or c->>'amountMinorUnits' !~ '^(0|-?[1-9][0-9]*)$'
    or c->>'date' !~ '^[0-9]{4}-[0-9]{2}-[0-9]{2}$'
    or jsonb_typeof(c->'receiptLines') is distinct from 'array'
    or jsonb_typeof(c->'receiptAttachmentIds') is distinct from 'array' then
    raise sqlstate '22023' using message='Invalid Expense edit command';
  end if;
  fingerprint:=encode(extensions.digest(convert_to(p_command,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(operation,0));
  select * into result from public.spike_operation_results where operation_id=operation;
  if found then
    if row(result.account_id,result.actor_principal_id,result.command_type,result.command_fingerprint)
      is distinct from row(account,actor,'edit_expense'::text,fingerprint) then
      raise sqlstate '23505' using message='Operation identity conflict';
    end if;
    return result;
  end if;
  begin
    select client_id into client from public.spike_projects where account_id=account and id=c->>'projectId' and lifecycle='active' for share;
    if not found then raise exception 'expense_project_unavailable'; end if;
    perform 1 from public.spike_clients where account_id=account and id=client and lifecycle='active' for share;
    if not found then raise exception 'expense_project_unavailable'; end if;
    select * into source from ledger_private.expenses where account_id=account and id=c->>'expenseId'
      and project_id=c->>'projectId' for update;
    if not found then raise exception 'expense_unavailable'; end if;
    if exists(select 1 from ledger_private.collected_invoice_lines where account_id=account
      and source_kind='expense' and source_id=source.id) then raise exception 'expense_collected'; end if;
    if source.revision<>(c->>'expectedRevision')::bigint then raise exception 'expense_revision_conflict'; end if;
    if source.currency<>c->>'currency' then raise exception 'expense_integrity_conflict'; end if;
    perform 1 from public.spike_budget_categories where account_id=account and id=c->>'categoryId'
      and lifecycle='active' and kind='general' for share;
    if not found then raise exception 'expense_category_unavailable'; end if;
    select coalesce(jsonb_agg(attachment_id order by position),'[]'::jsonb) into attachments
      from ledger_private.expense_receipt_attachments where account_id=account and expense_id=source.id;
    -- Media changes need the verified upload/retention path, not a naked ID replacement.
    if attachments is distinct from c->'receiptAttachmentIds' then raise exception 'expense_receipt_change_unavailable'; end if;
    for entry in select value from jsonb_array_elements(c->'receiptLines') loop
      if jsonb_typeof(entry) is distinct from 'object'
        or not(entry ?& array['id','description','magnitudeMinorUnits','currency','effect','quantity'])
        or entry-array['id','description','magnitudeMinorUnits','currency','effect','quantity']<>'{}'::jsonb
        or exists(select 1 from jsonb_each(entry-'quantity') where jsonb_typeof(value)<>'string')
        or jsonb_typeof(entry->'quantity') not in ('string','null')
        or entry->>'magnitudeMinorUnits' !~ '^[1-9][0-9]*$'
        or (entry->>'quantity' is not null and entry->>'quantity' !~ '^(0|-?[1-9][0-9]*)$') then
        raise exception 'expense_receipt_invalid';
      end if;
    end loop;
    update ledger_private.expenses set vendor=c->>'vendor',expense_date=(c->>'date')::date,
      final_amount_minor_units=(c->>'amountMinorUnits')::bigint,category_id=c->>'categoryId',notes=c->>'notes',revision=revision+1
      where id=source.id;
    delete from ledger_private.expense_receipt_lines where account_id=account and expense_id=source.id;
    insert into ledger_private.expense_receipt_lines(account_id,expense_id,id,position,description,magnitude_minor_units,currency,effect,quantity)
      select account,source.id,value->>'id',(ordinality-1)::integer,value->>'description',
        (value->>'magnitudeMinorUnits')::bigint,value->>'currency',value->>'effect',(value->>'quantity')::bigint
      from jsonb_array_elements(c->'receiptLines') with ordinality;
  exception
    when raise_exception then failure:=SQLERRM;
    when integrity_constraint_violation or numeric_value_out_of_range or datetime_field_overflow or invalid_datetime_format then
      failure:='expense_integrity_conflict';
  end;
  insert into public.spike_operation_results(operation_id,account_id,actor_principal_id,command_type,contract_version,
    command_fingerprint,envelope_sha256,subject_id,phase,result_code,error_code,client_created_at,server_received_at,
    completed_at,client_created_at_ms,server_received_at_ms,completed_at_ms)
  values(operation,account,actor,'edit_expense','expense-edit-v1',fingerprint,fingerprint,c->>'expenseId',
    case when failure is null then 'applied' else 'rejected' end,
    case when failure is null then 'expense_edited' end,failure,to_timestamp((c->>'createdAtMs')::bigint/1000.0),received,received,
    (c->>'createdAtMs')::bigint,floor(extract(epoch from received)*1000)::bigint,floor(extract(epoch from received)*1000)::bigint)
  returning * into result;
  return result;
end;
$$;
-- Keep unexposed until command/security/replay checks and callers are complete.
revoke all on function ledger_private.edit_expense(text) from public,anon,authenticated,service_role;
