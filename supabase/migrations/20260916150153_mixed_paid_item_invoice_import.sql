-- Extend the same atomic operator writer; retain its exact retry payload.
create or replace function ledger_private.import_invoice_sources(p_invoice jsonb,p_sources jsonb,p_payment jsonb,
  p_source_account text,p_source_invoice text,p_invoice_bytes bytea) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare
  request jsonb:=jsonb_build_object('invoice',p_invoice,'expenses',p_sources,'payment',p_payment);
  evidence ledger_private.imported_expense_invoice_sources;
  payment public.spike_transactions;
  payment_source ledger_private.imported_transaction_sources;
  entry jsonb; line jsonb; expense ledger_private.expenses; fee ledger_private.fee_installments;
begin
  select * into payment from public.spike_transactions where id=p_invoice->>'purchase_id' for update;
  select * into payment_source from ledger_private.imported_transaction_sources where transaction_id=payment.id;
  if payment.id is null or payment_source.transaction_id is null
    or payment.origin<>'firebase_client_payment' or payment.type<>'purchase'
    or row(payment.account_id,payment.project_id,payment.client_id,payment.currency,payment.amount_minor_units::text)
      is distinct from row(p_invoice->>'account_id',p_invoice->>'project_id',p_invoice->>'client_id',p_invoice->>'currency',p_invoice->>'total_minor_units')
    or p_payment is distinct from jsonb_build_object('p_id',payment.id,'p_account_id',payment.account_id,
      'p_project_id',payment.project_id,'p_client_id',payment.client_id,'p_amount',payment.amount_minor_units::text,
      'p_currency',payment.currency,'p_source_account',payment_source.source_account_id,
      'p_source_document',payment_source.source_document_id,'p_source_bytes','\x'||encode(payment_source.source_bytes,'hex'))
    or p_source_account is distinct from payment_source.source_account_id then
    raise exception using errcode='22000',message='Invoice import requires its exact stored payment evidence';
  end if;
  select * into evidence from ledger_private.imported_expense_invoice_sources where invoice_id=p_invoice->>'invoice_id';
  if found then
    if row(evidence.source_account_id,evidence.source_invoice_id,evidence.invoice_bytes,evidence.import_payload)
      is distinct from row(p_source_account,p_source_invoice,p_invoice_bytes,request) then
      raise exception using errcode='22000',message='Invoice import conflicts with retained evidence';
    end if;
    return ledger_private.store_collected_invoice(p_invoice);
  end if;
  if jsonb_typeof(p_sources) is distinct from 'array' or jsonb_typeof(p_invoice->'lines') is distinct from 'array'
    or jsonb_array_length(p_sources)=0 or jsonb_array_length(p_sources)<>jsonb_array_length(p_invoice->'lines') then
    raise exception using errcode='22023',message='Invoice import requires all mapped sources';
  end if;
  for entry,line in select e.value,l.value from jsonb_array_elements(p_sources) with ordinality e
    join jsonb_array_elements(p_invoice->'lines') with ordinality l using(ordinality) loop
    if jsonb_typeof(entry) is distinct from 'object' or not(entry ?& array['source_document_id','source_bytes'])
      or jsonb_typeof(entry->'source_document_id') is distinct from 'string'
      or jsonb_typeof(entry->'source_bytes') is distinct from 'string'
      or octet_length(entry->>'source_document_id') not between 1 and 1500
      or entry->>'source_document_id' in ('.','..') or position('/' in (entry->>'source_document_id'))<>0
      or entry->>'source_bytes' !~ '^\\x([0-9a-f]{2})+$'
      or octet_length((entry->>'source_bytes')::bytea)>4194304 then
      raise exception using errcode='22023',message='Invoice source evidence invalid';
    end if;
    if line->>'source_kind'='item' then
      if entry-array['source_document_id','source_line_id','source_bytes','line_source_bytes']<>'{}'::jsonb
        or jsonb_typeof(entry->'source_line_id') is distinct from 'string'
        or jsonb_typeof(entry->'line_source_bytes') is distinct from 'string'
        or entry->>'line_source_bytes' !~ '^\\x([0-9a-f]{2})+$'
        or octet_length((entry->>'line_source_bytes')::bytea)>4194304
        or (line->>'signed_amount_minor_units')::bigint<=0
        or line->>'source_revision' is distinct from '1'
        or not exists(select 1 from public.spike_items i
          where i.id=line->>'item_id' and i.account_id=p_invoice->>'account_id')
        or (line->>'source_snapshot_json')::jsonb is distinct from jsonb_build_object('item',jsonb_build_object(
          'itemId',line->>'item_id','occurrenceId',line->>'source_id','price',jsonb_build_object(
            'basis',jsonb_build_object('importedInvoiceAmount','{}'::jsonb),
            'amount',jsonb_build_object('minorUnits',(line->>'signed_amount_minor_units')::bigint,'currency',p_invoice->>'currency')))) then
        raise exception using errcode='22023',message='Item must match its exact frozen source';
      end if;
      -- No physical mutation: only immutable paid-line evidence is imported.
    elsif line->>'source_kind'='expense' then
      if jsonb_typeof(entry->'record') is distinct from 'object' then
        raise exception using errcode='22023',message='Invoice source evidence invalid';
      end if;
      expense:=jsonb_populate_record(null::ledger_private.expenses,entry->'record');
      if entry-array['record','source_document_id','source_bytes','receipt_attachment_ids']<>'{}'::jsonb
        or (entry->'record')-array(select jsonb_object_keys(to_jsonb(expense)))<>'{}'::jsonb
        or line->>'item_id' is not null
        or row(expense.id,expense.account_id,expense.project_id,expense.currency,expense.final_amount_minor_units::text,expense.revision::text)
          is distinct from row(line->>'source_id',p_invoice->>'account_id',p_invoice->>'project_id',p_invoice->>'currency',
            line->>'signed_amount_minor_units',line->>'source_revision')
        or (line->>'source_snapshot_json')::jsonb is distinct from
          jsonb_build_object('expense',jsonb_build_object('expenseId',expense.id)) then
        raise exception using errcode='22023',message='Expense must match its exact frozen source';
      end if;
      insert into ledger_private.expenses select expense.*;
      if jsonb_typeof(coalesce(entry->'receipt_attachment_ids','[]'::jsonb)) is distinct from 'array'
        or exists(select 1 from jsonb_array_elements(coalesce(entry->'receipt_attachment_ids','[]'::jsonb))
          where jsonb_typeof(value)<>'string') then
        raise exception using errcode='22023',message='Expense receipt mapping invalid';
      end if;
      insert into ledger_private.expense_receipt_attachments(account_id,expense_id,attachment_id,position)
        select expense.account_id,expense.id,value#>>'{}',(ordinality-1)::integer
        from jsonb_array_elements(coalesce(entry->'receipt_attachment_ids','[]'::jsonb)) with ordinality;
    elsif line->>'source_kind'='fee_installment' then
      if jsonb_typeof(entry->'record') is distinct from 'object' then
        raise exception using errcode='22023',message='Invoice source evidence invalid';
      end if;
      fee:=jsonb_populate_record(null::ledger_private.fee_installments,entry->'record');
      if entry-array['record','source_document_id','source_project_id','source_bytes']<>'{}'::jsonb
        or jsonb_typeof(entry->'source_project_id') is distinct from 'string'
        or (entry->'record')-array(select jsonb_object_keys(to_jsonb(fee)))<>'{}'::jsonb
        or line->>'item_id' is not null
        or row(fee.id,fee.account_id,fee.project_id,fee.currency,fee.amount_minor_units::text,fee.revision::text)
          is distinct from row(line->>'source_id',p_invoice->>'account_id',p_invoice->>'project_id',p_invoice->>'currency',
            line->>'signed_amount_minor_units',line->>'source_revision')
        or (line->>'source_snapshot_json')::jsonb is distinct from
          jsonb_build_object('feeInstallment',jsonb_build_object('installmentId',fee.id)) then
        raise exception using errcode='22023',message='Fee must match its exact frozen source';
      end if;
      insert into ledger_private.fee_installments select fee.*;
    else
      raise exception using errcode='22023',message='Invoice source kind requires mapping';
    end if;
  end loop;
  perform ledger_private.store_collected_invoice(p_invoice);
  insert into ledger_private.imported_expense_invoice_sources values
    (p_invoice->>'invoice_id',p_source_account,p_source_invoice,p_invoice_bytes,request);
  for entry,line in select e.value,l.value from jsonb_array_elements(p_sources) with ordinality e
    join jsonb_array_elements(p_invoice->'lines') with ordinality l using(ordinality) loop
    if line->>'source_kind'='item' then
      insert into ledger_private.imported_item_invoice_sources values
        (line->>'id',p_invoice->>'invoice_id',p_source_account,p_source_invoice,
          entry->>'source_line_id',entry->>'source_document_id',
          (entry->>'source_bytes')::bytea,(entry->>'line_source_bytes')::bytea);
    elsif line->>'source_kind'='expense' then
      insert into ledger_private.imported_expense_sources values
        (entry->'record'->>'id',p_invoice->>'invoice_id',p_source_account,entry->>'source_document_id');
    else
      insert into ledger_private.imported_fee_sources values
        (entry->'record'->>'id',p_invoice->>'invoice_id',p_source_account,
          entry->>'source_project_id',entry->>'source_document_id',(entry->>'source_bytes')::bytea);
    end if;
  end loop;
  return ledger_private.read_collected_invoice(p_invoice->>'account_id',p_invoice->>'invoice_id');
end;
$$;
revoke all on function ledger_private.import_invoice_sources(jsonb,jsonb,jsonb,text,text,bytea)
  from public,anon,authenticated,service_role;
