-- Reviewed local pull: retain protected functions/extensions and omit local
-- service/owner grants. Backfill before NOT NULL; never rewrite frozen facts.
begin;
lock table ledger_private.collected_invoices,ledger_private.collected_invoice_lines in share row exclusive mode;
alter table ledger_private.collected_invoice_lines add column sync_project_id text;
-- ALTER TABLE holds an exclusive lock until commit. Disable only this exact
-- immutable-line guard for the derived-column backfill, not runtime writes.
alter table ledger_private.collected_invoice_lines disable trigger collected_invoice_line_immutable;
update ledger_private.collected_invoice_lines line set sync_project_id=invoice.project_id
  from ledger_private.collected_invoices invoice where invoice.account_id=line.account_id and invoice.id=line.invoice_id;
alter table ledger_private.collected_invoice_lines enable trigger collected_invoice_line_immutable;
alter table ledger_private.collected_invoice_lines alter column sync_project_id set not null;
create or replace function ledger_private.guard_collected_invoice_line_insert() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare is_sealed boolean;
begin
  select sealed,project_id into is_sealed,new.sync_project_id from ledger_private.collected_invoices
    where account_id=new.account_id and id=new.invoice_id for update;
  if not found then
    raise exception using errcode='23503', message='Frozen line requires its exact Invoice';
  end if;
  if is_sealed then
    raise exception using errcode='55000', message='Cannot add lines to a sealed Invoice';
  end if;
  return new;
end;
$$;
-- Existing function identity, trigger and grants remain unchanged. Header scope
-- and all committed lines are immutable; no ongoing propagation is necessary.
commit;
