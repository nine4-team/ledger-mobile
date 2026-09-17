-- Discovery uses the existing frozen reader; unsealed history fails closed.
create function ledger_private.list_project_collected_invoices(p_account_id text,p_project_id text)
returns jsonb language plpgsql security definer set search_path='' as $$
begin
  if (select auth.uid()) is null or not exists (
    select 1 from public.spike_projects p
    join public.spike_account_memberships m on m.account_id=p.account_id
    where p.account_id=p_account_id and p.id=p_project_id
      and m.principal_id=ledger_private.current_principal_id()
      and m.state='active' and m.financial_access='full'
  ) then raise sqlstate '42501' using message='invoice_not_available'; end if;
  return coalesce((select jsonb_agg(
    ledger_private.read_project_collected_invoice(p_account_id,p_project_id,i.id) order by i.id)
    from ledger_private.collected_invoices i
    where i.account_id=p_account_id and i.project_id=p_project_id),'[]'::jsonb);
end;
$$;
revoke all on function ledger_private.list_project_collected_invoices(text,text) from public,anon,authenticated,service_role;
grant execute on function ledger_private.list_project_collected_invoices(text,text) to authenticated;
create function public.spike_list_project_collected_invoices(p_account_id text,p_project_id text)
returns jsonb language sql security invoker set search_path='' as $$
  select ledger_private.list_project_collected_invoices(p_account_id,p_project_id)
$$;
revoke all on function public.spike_list_project_collected_invoices(text,text) from public,anon,authenticated,service_role;
grant execute on function public.spike_list_project_collected_invoices(text,text) to authenticated;
