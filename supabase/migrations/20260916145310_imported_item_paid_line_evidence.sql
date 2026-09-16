-- Paid-line evidence is not a fabricated historical placement or price rule.
create table ledger_private.imported_item_invoice_sources (
  line_id text primary key references ledger_private.collected_invoice_lines(id),
  invoice_id text not null references ledger_private.imported_expense_invoice_sources(invoice_id),
  source_account_id text not null,
  source_invoice_id text not null,
  source_line_id text not null,
  source_item_id text not null,
  item_source_bytes bytea not null check(octet_length(item_source_bytes) between 1 and 4194304),
  line_source_bytes bytea not null check(octet_length(line_source_bytes) between 1 and 4194304),
  unique(source_account_id,source_invoice_id,source_line_id),
  check(octet_length(source_account_id) between 1 and 1500 and source_account_id not in ('.','..') and position('/' in source_account_id)=0),
  check(octet_length(source_invoice_id) between 1 and 1500 and source_invoice_id not in ('.','..') and position('/' in source_invoice_id)=0),
  check(octet_length(source_line_id) between 1 and 1500 and source_line_id not in ('.','..') and position('/' in source_line_id)=0),
  check(octet_length(source_item_id) between 1 and 1500 and source_item_id not in ('.','..') and position('/' in source_item_id)=0)
);
create index imported_item_invoice_sources_invoice_idx on ledger_private.imported_item_invoice_sources(invoice_id);
alter table ledger_private.imported_item_invoice_sources enable row level security;
alter table ledger_private.imported_item_invoice_sources force row level security;
revoke all on ledger_private.imported_item_invoice_sources from public,anon,authenticated,service_role;
create trigger imported_item_invoice_source_immutable before update or delete
  on ledger_private.imported_item_invoice_sources for each row
  execute function ledger_private.guard_imported_expense_invoice_source();
create trigger imported_item_invoice_source_no_truncate before truncate
  on ledger_private.imported_item_invoice_sources for each statement
  execute function ledger_private.guard_imported_expense_invoice_source();

create function ledger_private.require_imported_item_line_evidence() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if new.source_kind<>'item' or not(coalesce(new.source_snapshot#>'{item,price,basis}','{}'::jsonb) ? 'importedInvoiceAmount') then
    return null;
  end if;
  if new.signed_amount_minor_units<=0 or new.source_revision<>1
    or new.source_snapshot is distinct from jsonb_build_object('item',jsonb_build_object(
      'itemId',new.item_id,'occurrenceId',new.source_id,'price',jsonb_build_object(
        'basis',jsonb_build_object('importedInvoiceAmount','{}'::jsonb),
        'amount',jsonb_build_object('minorUnits',new.signed_amount_minor_units,'currency',new.currency))))
    or not exists(select 1 from ledger_private.imported_item_invoice_sources e
      join ledger_private.imported_expense_invoice_sources i on i.invoice_id=e.invoice_id
      where e.line_id=new.id and e.invoice_id=new.invoice_id
        and e.source_account_id=i.source_account_id and e.source_invoice_id=i.source_invoice_id) then
    raise exception using errcode='23514',message='Imported Item amount requires exact retained Invoice-line evidence';
  end if;
  return null;
end;
$$;
revoke all on function ledger_private.require_imported_item_line_evidence() from public,anon,authenticated,service_role;
create constraint trigger imported_item_line_evidence after insert on ledger_private.collected_invoice_lines
  deferrable initially deferred for each row execute function ledger_private.require_imported_item_line_evidence();
