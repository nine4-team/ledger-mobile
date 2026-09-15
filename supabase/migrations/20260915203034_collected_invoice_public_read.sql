-- General paid-Invoice access, independent of an Expense or payment selection.
-- Match existing full-financial read authority; do not redact frozen lines.
create function ledger_private.read_project_collected_invoice(p_account_id text,p_project_id text,p_invoice_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if (select auth.uid()) is null or not exists (
    select 1 from ledger_private.collected_invoices h
    join public.spike_account_memberships m on m.account_id=h.account_id
      and m.principal_id=ledger_private.current_principal_id()
      and m.state='active' and m.financial_access='full'
    where h.account_id=p_account_id and h.project_id=p_project_id
      and h.id=p_invoice_id and h.sealed
  ) then
    raise exception using errcode='42501',message='invoice_not_available';
  end if;
  return ledger_private.read_collected_invoice(p_account_id,p_invoice_id);
end;
$$;
revoke all on function ledger_private.read_project_collected_invoice(text,text,text) from public,anon,authenticated,service_role;
grant execute on function ledger_private.read_project_collected_invoice(text,text,text) to authenticated;
create function public.spike_read_collected_invoice(p_account_id text,p_project_id text,p_invoice_id text)
returns jsonb language sql security invoker set search_path='' as $$
  select ledger_private.read_project_collected_invoice(p_account_id,p_project_id,p_invoice_id)
$$;
revoke all on function public.spike_read_collected_invoice(text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.spike_read_collected_invoice(text,text,text) to authenticated;
