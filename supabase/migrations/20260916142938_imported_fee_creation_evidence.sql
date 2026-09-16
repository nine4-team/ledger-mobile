-- Operator import evidence only. Never invent a creator/time for legacy Fees.
-- Native Fee creation continues supplying both fields through its typed writer.
alter table ledger_private.fee_installments alter column created_at drop not null;
alter table ledger_private.fee_installments alter column created_by_principal_id drop not null;

create table ledger_private.imported_fee_sources (
  fee_id text primary key references ledger_private.fee_installments(id),
  invoice_id text not null references ledger_private.imported_expense_invoice_sources(invoice_id),
  source_account_id text not null,
  source_project_id text not null,
  source_document_id text not null,
  source_bytes bytea not null check(octet_length(source_bytes) between 1 and 4194304),
  unique(source_account_id,source_project_id,source_document_id),
  check(octet_length(source_account_id) between 1 and 1500 and source_account_id not in ('.','..') and position('/' in source_account_id)=0),
  check(octet_length(source_project_id) between 1 and 1500 and source_project_id not in ('.','..') and position('/' in source_project_id)=0),
  check(octet_length(source_document_id) between 1 and 1500 and source_document_id not in ('.','..') and position('/' in source_document_id)=0)
);
create index imported_fee_sources_invoice_idx on ledger_private.imported_fee_sources(invoice_id);
alter table ledger_private.imported_fee_sources enable row level security;
alter table ledger_private.imported_fee_sources force row level security;
revoke all on ledger_private.imported_fee_sources from public,anon,authenticated,service_role;
create trigger imported_fee_source_immutable before update or delete
  on ledger_private.imported_fee_sources for each row
  execute function ledger_private.guard_imported_expense_invoice_source();
create trigger imported_fee_source_no_truncate before truncate
  on ledger_private.imported_fee_sources for each statement
  execute function ledger_private.guard_imported_expense_invoice_source();

create or replace function ledger_private.require_fee_creation_evidence() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  -- Avoid private-table reads for normal app writes after DEFINER context ends.
  if new.created_at is not null and new.created_by_principal_id is not null then return null; end if;
  if exists(select 1 from ledger_private.fee_installments f where f.id=new.id
    and (f.created_at is null or f.created_by_principal_id is null)
    and not exists(select 1 from ledger_private.imported_fee_sources s
      join ledger_private.imported_expense_invoice_sources i on i.invoice_id=s.invoice_id
      join ledger_private.collected_invoices c on c.id=i.invoice_id
      where s.fee_id=f.id and s.source_account_id=i.source_account_id
        and c.account_id=f.account_id and c.project_id=f.project_id
        and exists(select 1 from ledger_private.collected_invoice_lines l where l.invoice_id=c.id
          and l.source_kind='fee_installment' and l.source_id=f.id and l.account_id=f.account_id
          and l.source_revision=f.revision and l.currency=f.currency
          and l.signed_amount_minor_units=f.amount_minor_units))) then
    raise exception using errcode='23514',message='Unknown Fee creation metadata requires retained import evidence';
  end if;
  return null;
end;
$$;
revoke all on function ledger_private.require_fee_creation_evidence() from public,anon,authenticated,service_role;
create constraint trigger fee_creation_evidence after insert or update on ledger_private.fee_installments
  deferrable initially deferred for each row execute function ledger_private.require_fee_creation_evidence();
