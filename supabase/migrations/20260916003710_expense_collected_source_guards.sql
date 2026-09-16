-- Pre-collection editing never rewrites a collected Expense or its receipt facts.
-- Parent row locks serialize edits with frozen line insertion. No new API grants.
create function ledger_private.guard_expense_collected_write() returns trigger
language plpgsql volatile security invoker set search_path='' as $$
declare account text; expense text;
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode='25001',message='Expense writes require READ COMMITTED';
  end if;
  if tg_table_name='expenses' then
    account:=old.account_id; expense:=old.id;
  elsif tg_op='INSERT' then
    account:=new.account_id; expense:=new.expense_id;
  else
    account:=old.account_id; expense:=old.expense_id;
    if tg_op='UPDATE' and row(new.account_id,new.expense_id) is distinct from row(account,expense) then
      raise exception using errcode='23514',message='Expense receipt parent is immutable';
    end if;
  end if;
  perform 1 from ledger_private.expenses where account_id=account and id=expense for update;
  if exists(select 1 from ledger_private.collected_invoice_lines
    where account_id=account and source_kind='expense' and source_id=expense) then
    raise exception using errcode='23514',message='Collected Expense is immutable';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function ledger_private.guard_expense_collected_write() from public,anon,authenticated,service_role;
create trigger expense_collected_write before update or delete on ledger_private.expenses
for each row execute function ledger_private.guard_expense_collected_write();
create trigger expense_receipt_line_collected_write before insert or update or delete on ledger_private.expense_receipt_lines
for each row execute function ledger_private.guard_expense_collected_write();
create trigger expense_receipt_attachment_collected_write before insert or update or delete on ledger_private.expense_receipt_attachments
for each row execute function ledger_private.guard_expense_collected_write();

create function ledger_private.guard_collected_expense_source() returns trigger
language plpgsql volatile security invoker set search_path='' as $$
declare source ledger_private.expenses; project text;
begin
  if new.source_kind<>'expense' then return new; end if;
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode='25001',message='Expense writes require READ COMMITTED';
  end if;
  select * into source from ledger_private.expenses
    where account_id=new.account_id and id=new.source_id for share;
  -- Existing historical storage permits source-only snapshots. This guard does
  -- not invent a missing Expense during historical import.
  if not found then return new; end if;
  select project_id into project from ledger_private.collected_invoices
    where account_id=new.account_id and id=new.invoice_id;
  if row(source.project_id,source.revision,source.currency,source.final_amount_minor_units)
    is distinct from row(project,new.source_revision,new.currency,new.signed_amount_minor_units) then
    raise exception using errcode='23514',message='Collected Expense source changed';
  end if;
  return new;
end;
$$;
revoke all on function ledger_private.guard_collected_expense_source() from public,anon,authenticated,service_role;
create trigger collected_expense_source before insert on ledger_private.collected_invoice_lines
for each row execute function ledger_private.guard_collected_expense_source();
