-- Read-only parity with the native Expense/frozen-Invoice relationship. Null
-- means no confirmed collected membership, never proof of unpaid availability.
create function ledger_private.read_expense_invoice(p_account_id text,p_project_id text,p_expense_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
declare expense jsonb; selected_invoice_id text; invoice jsonb;
begin
  expense:=ledger_private.read_expense(p_account_id,p_project_id,p_expense_id);
  select h.id into selected_invoice_id from ledger_private.collected_invoice_lines l
    join ledger_private.collected_invoices h on h.account_id=l.account_id and h.id=l.invoice_id
    where l.account_id=p_account_id and l.source_kind='expense' and l.source_id=p_expense_id
      and h.project_id=p_project_id and h.sealed;
  if selected_invoice_id is not null then
    invoice:=ledger_private.read_collected_invoice(p_account_id,selected_invoice_id);
    if not exists(select 1 from ledger_private.collected_invoice_lines l
      where l.account_id=p_account_id and l.invoice_id=selected_invoice_id and l.source_kind='expense' and l.source_id=p_expense_id
        and l.source_revision::text=expense->>'revision' and l.currency=expense->>'currency'
        and l.signed_amount_minor_units::text=expense->>'amountMinorUnits') then
      raise exception using errcode='22000',message='Expense frozen source mismatch';
    end if;
  end if;
  return jsonb_build_object('expense',expense,'invoice',invoice);
end;
$$;
revoke all on function ledger_private.read_expense_invoice(text,text,text) from public,anon,authenticated,service_role;
grant execute on function ledger_private.read_expense_invoice(text,text,text) to authenticated;
create function public.spike_read_expense_invoice(p_account_id text,p_project_id text,p_expense_id text)
returns jsonb language sql security invoker set search_path='' as $$
  select ledger_private.read_expense_invoice(p_account_id,p_project_id,p_expense_id)
$$;
revoke all on function public.spike_read_expense_invoice(text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.spike_read_expense_invoice(text,text,text) to authenticated;
