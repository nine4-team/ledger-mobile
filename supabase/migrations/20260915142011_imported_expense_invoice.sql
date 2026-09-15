-- Operator-only migration, not live Invoice collection or an app write API.
-- Complete source envelopes and the exact import request survive every retry.
-- Legacy Transactions have optional createdAt and no creator field. Preserve
-- unknown attribution; the deferred check permits it only with import evidence.
alter table ledger_private.expenses alter column created_at drop not null;
alter table ledger_private.expenses alter column created_by_principal_id drop not null;
create table ledger_private.imported_expense_invoice_sources (
  invoice_id text primary key references ledger_private.collected_invoices(id),
  source_account_id text not null,
  source_invoice_id text not null,
  invoice_bytes bytea not null check (octet_length(invoice_bytes) between 1 and 4194304),
  import_payload jsonb not null,
  unique (source_account_id,source_invoice_id),
  check (octet_length(source_account_id) between 1 and 1500 and source_account_id not in ('.','..') and position('/' in source_account_id)=0),
  check (octet_length(source_invoice_id) between 1 and 1500 and source_invoice_id not in ('.','..') and position('/' in source_invoice_id)=0)
);
alter table ledger_private.imported_expense_invoice_sources enable row level security;
alter table ledger_private.imported_expense_invoice_sources force row level security;
revoke all on ledger_private.imported_expense_invoice_sources from public,anon,authenticated,service_role;

-- One original business cost cannot be imported again under another target ID
-- or another Invoice. The manifest alone cannot enforce that across imports.
create table ledger_private.imported_expense_sources (
  expense_id text primary key references ledger_private.expenses(id),
  invoice_id text not null references ledger_private.imported_expense_invoice_sources(invoice_id),
  source_account_id text not null,
  source_document_id text not null,
  unique(source_account_id,source_document_id)
);
create index imported_expense_sources_invoice_idx on ledger_private.imported_expense_sources(invoice_id);
alter table ledger_private.imported_expense_sources enable row level security;
alter table ledger_private.imported_expense_sources force row level security;
revoke all on ledger_private.imported_expense_sources from public,anon,authenticated,service_role;

create or replace function ledger_private.require_expense_creation_evidence() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  -- Native creation already supplies both fields. Deferred triggers execute
  -- after an RPC's SECURITY DEFINER context ends, so do not read private tables
  -- for this case or grant API roles private-table access to satisfy the guard.
  if new.created_at is not null and new.created_by_principal_id is not null then return null; end if;
  if exists(select 1 from ledger_private.expenses e where e.id=new.id
    and (e.created_at is null or e.created_by_principal_id is null)
    and not exists(select 1 from ledger_private.imported_expense_sources s where s.expense_id=e.id)) then
    raise exception using errcode='23514',message='Unknown Expense creation metadata requires retained import evidence';
  end if;
  return null;
end;
$$;
revoke all on function ledger_private.require_expense_creation_evidence() from public,anon,authenticated,service_role;
create constraint trigger expense_creation_evidence after insert or update on ledger_private.expenses
  deferrable initially deferred for each row execute function ledger_private.require_expense_creation_evidence();

create function ledger_private.guard_imported_expense_invoice_source() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  raise exception using errcode='55000',message='Imported Invoice evidence is immutable';
end;
$$;
revoke all on function ledger_private.guard_imported_expense_invoice_source() from public,anon,authenticated,service_role;
create trigger imported_expense_invoice_source_immutable before update or delete
  on ledger_private.imported_expense_invoice_sources for each row
  execute function ledger_private.guard_imported_expense_invoice_source();
create trigger imported_expense_invoice_source_no_truncate before truncate
  on ledger_private.imported_expense_invoice_sources for each statement
  execute function ledger_private.guard_imported_expense_invoice_source();
create trigger imported_expense_source_immutable before update or delete
  on ledger_private.imported_expense_sources for each row
  execute function ledger_private.guard_imported_expense_invoice_source();
create trigger imported_expense_source_no_truncate before truncate
  on ledger_private.imported_expense_sources for each statement
  execute function ledger_private.guard_imported_expense_invoice_source();

-- p_expenses contains {record,source_document_id,source_bytes}. record is the
-- complete expenses row, including original creation time when available and
-- null for unknown attribution; never substitute the operator or today's date.
-- Optional receipt_attachment_ids must name already-verified objects in the
-- same Account. References are inserted atomically with source and membership.
create or replace function ledger_private.import_expense_invoice(p_invoice jsonb,p_expenses jsonb,p_payment jsonb,
  p_source_account text,p_source_invoice text,p_invoice_bytes bytea) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare
  request jsonb:=jsonb_build_object('invoice',p_invoice,'expenses',p_expenses,'payment',p_payment);
  evidence ledger_private.imported_expense_invoice_sources;
  payment public.spike_transactions;
  payment_source ledger_private.imported_transaction_sources;
  entry jsonb; line jsonb; expense ledger_private.expenses; source_ids text[]:='{}';
begin
  -- The existing payment lock serializes concurrent retries and other frozen
  -- membership writers. No new payment is created by this function.
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
  if jsonb_typeof(p_expenses) is distinct from 'array' or jsonb_typeof(p_invoice->'lines') is distinct from 'array'
    or jsonb_array_length(p_expenses)=0 or jsonb_array_length(p_expenses)<>jsonb_array_length(p_invoice->'lines') then
    raise exception using errcode='22023',message='Invoice import requires all Expense sources';
  end if;
  for entry,line in select e.value,l.value from jsonb_array_elements(p_expenses) with ordinality e
    join jsonb_array_elements(p_invoice->'lines') with ordinality l using(ordinality) loop
    if jsonb_typeof(entry) is distinct from 'object'
      or not(entry ?& array['record','source_document_id','source_bytes'])
      or entry-array['record','source_document_id','source_bytes','receipt_attachment_ids']<>'{}'::jsonb
      or jsonb_typeof(entry->'record') is distinct from 'object'
      or jsonb_typeof(entry->'source_document_id') is distinct from 'string'
      or jsonb_typeof(entry->'source_bytes') is distinct from 'string'
      or octet_length(entry->>'source_document_id') not between 1 and 1500
      or entry->>'source_document_id' in ('.','..') or position('/' in (entry->>'source_document_id'))<>0
      or entry->>'source_document_id'=any(source_ids)
      or entry->>'source_bytes' !~ '^\\x([0-9a-f]{2})+$'
      or octet_length((entry->>'source_bytes')::bytea)>4194304 then
      raise exception using errcode='22023',message='Expense import source evidence invalid';
    end if;
    source_ids:=array_append(source_ids,entry->>'source_document_id');
    expense:=jsonb_populate_record(null::ledger_private.expenses,entry->'record');
    if (entry->'record')-array(select jsonb_object_keys(to_jsonb(expense)))<>'{}'::jsonb
      or line->>'source_kind' is distinct from 'expense' or line->>'item_id' is not null
      or row(expense.id,expense.account_id,expense.project_id,expense.currency,expense.final_amount_minor_units::text,expense.revision::text)
        is distinct from row(line->>'source_id',p_invoice->>'account_id',p_invoice->>'project_id',p_invoice->>'currency',
          line->>'signed_amount_minor_units',line->>'source_revision')
      or (line->>'source_snapshot_json')::jsonb is distinct from
        jsonb_build_object('expense',jsonb_build_object('expenseId',expense.id)) then
      raise exception using errcode='22023',message='Expense must match its exact frozen source';
    end if;
    -- Plain INSERT intentionally refuses adoption/overwrite of an existing
    -- Expense. Only a fully evidenced retry above may reuse imported identities.
    insert into ledger_private.expenses select expense.*;
    if jsonb_typeof(coalesce(entry->'receipt_attachment_ids','[]'::jsonb)) is distinct from 'array'
      or exists(select 1 from jsonb_array_elements(coalesce(entry->'receipt_attachment_ids','[]'::jsonb))
        where jsonb_typeof(value)<>'string') then
      raise exception using errcode='22023',message='Expense receipt mapping invalid';
    end if;
    insert into ledger_private.expense_receipt_attachments(account_id,expense_id,attachment_id,position)
      select expense.account_id,expense.id,value#>>'{}',(ordinality-1)::integer
      from jsonb_array_elements(coalesce(entry->'receipt_attachment_ids','[]'::jsonb)) with ordinality;
  end loop;
  perform ledger_private.store_collected_invoice(p_invoice);
  insert into ledger_private.imported_expense_invoice_sources values
    (p_invoice->>'invoice_id',p_source_account,p_source_invoice,p_invoice_bytes,request);
  insert into ledger_private.imported_expense_sources(expense_id,invoice_id,source_account_id,source_document_id)
    select value->'record'->>'id',p_invoice->>'invoice_id',p_source_account,value->>'source_document_id'
    from jsonb_array_elements(p_expenses);
  return ledger_private.read_collected_invoice(p_invoice->>'account_id',p_invoice->>'invoice_id');
end;
$$;
revoke all on function ledger_private.import_expense_invoice(jsonb,jsonb,jsonb,text,text,bytea)
  from public,anon,authenticated,service_role;
