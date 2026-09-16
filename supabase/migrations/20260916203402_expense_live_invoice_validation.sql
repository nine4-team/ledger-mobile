-- Keep the existing receipt/replay contract; serialize live Invoice source edits.
create or replace function ledger_private.edit_expense(p_command text)
returns public.spike_operation_results language plpgsql security definer set search_path='' as $$
declare c jsonb:=p_command::jsonb; actor text; account text; operation text; fingerprint text;
  result public.spike_operation_results; source ledger_private.expenses; client text;
  received timestamptz:=clock_timestamp(); failure text; entry jsonb; attachments jsonb;
  invoice_id text; current_invoice text;
begin
  if current_setting('transaction_isolation')<>'read committed' then
    raise sqlstate '25001' using message='Expense writes require READ COMMITTED';
  end if;
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
    select m.invoice_id into invoice_id from ledger_private.live_invoice_memberships m
      where m.account_id=account and m.source_kind='expense' and m.source_id=c->>'expenseId' and m.released_at is null;
    if invoice_id is not null then
      perform 1 from ledger_private.live_invoices h where h.account_id=account and h.id=invoice_id
        and h.project_id=c->>'projectId' for update;
      if not found then raise exception 'expense_integrity_conflict'; end if;
    end if;
    select * into source from ledger_private.expenses where account_id=account and id=c->>'expenseId'
      and project_id=c->>'projectId' for update;
    if not found then raise exception 'expense_unavailable'; end if;
    select m.invoice_id into current_invoice from ledger_private.live_invoice_memberships m
      where m.account_id=account and m.source_kind='expense' and m.source_id=c->>'expenseId' and m.released_at is null;
    if current_invoice is distinct from invoice_id then raise exception 'expense_revision_conflict'; end if;
    if exists(select 1 from ledger_private.collected_invoice_lines where account_id=account
      and source_kind='expense' and source_id=source.id) then raise exception 'expense_collected'; end if;
    if invoice_id is not null and not exists(select 1 from ledger_private.live_invoices h
      where h.account_id=account and h.id=invoice_id and h.status in ('created','sent')) then
      raise exception 'expense_integrity_conflict'; end if;
    if source.revision<>(c->>'expectedRevision')::bigint then raise exception 'expense_revision_conflict'; end if;
    if source.currency<>c->>'currency' then raise exception 'expense_integrity_conflict'; end if;
    perform 1 from public.spike_budget_categories where account_id=account and id=c->>'categoryId'
      and lifecycle='active' and kind='general' for share;
    if not found then raise exception 'expense_category_unavailable'; end if;
    select coalesce(jsonb_agg(attachment_id order by position),'[]'::jsonb) into attachments
      from ledger_private.expense_receipt_attachments where account_id=account and expense_id=source.id;
    if jsonb_array_length(c->'receiptAttachmentIds')<jsonb_array_length(attachments)
      or exists(select 1 from jsonb_array_elements(attachments) with ordinality a(value,n)
        where value is distinct from (c->'receiptAttachmentIds')->((n-1)::integer)) then
      raise exception 'expense_receipt_change_unavailable';
    end if;
    if exists(select 1 from jsonb_array_elements(c->'receiptAttachmentIds') where jsonb_typeof(value)<>'string') then
      raise exception 'expense_receipt_invalid';
    end if;
    if exists(select 1 from jsonb_array_elements_text(c->'receiptAttachmentIds') with ordinality a(id,n)
      where n>jsonb_array_length(attachments) and not exists (
        select 1 from ledger_private.expense_attachment_uploads u
        join public.item_image_objects o on o.account_id=u.account_id and o.id=u.id
          and o.content_sha256=u.content_sha256 and o.byte_count=u.byte_count
          and o.media_type=u.media_type and o.storage_path=u.storage_path
        where u.id=a.id and u.account_id=account and u.project_id=source.project_id
          and u.expense_id=source.id and u.principal_id=actor
      )) then raise exception 'expense_receipt_invalid'; end if;
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
    insert into ledger_private.expense_receipt_attachments(account_id,expense_id,attachment_id,position)
      select account,source.id,id,(n-1)::integer
      from jsonb_array_elements_text(c->'receiptAttachmentIds') with ordinality a(id,n)
      where n>jsonb_array_length(attachments);
    if invoice_id is not null then
      perform ledger_private.read_live_invoice(account,c->>'projectId',invoice_id);
    end if;
  exception
    when raise_exception then failure:=SQLERRM;
    when integrity_constraint_violation or numeric_value_out_of_range or datetime_field_overflow or invalid_datetime_format
      or object_not_in_prerequisite_state then failure:='expense_integrity_conflict';
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
revoke all on function ledger_private.edit_expense(text) from public,anon,service_role;
grant execute on function ledger_private.edit_expense(text) to authenticated;
