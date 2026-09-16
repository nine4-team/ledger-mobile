-- Read canonical Fee sources and membership, including archived Projects.
-- Frozen collected facts win; current category names never rewrite paid history.
create function ledger_private.read_project_fees(p_account_id text,p_project_id text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare client text; can_create boolean; r record; rows jsonb:='[]'::jsonb;
begin
  if (select auth.uid()) is null then raise sqlstate '42501' using message='fees_not_available'; end if;
  select p.client_id,p.lifecycle='active' and c.lifecycle='active' into client,can_create
    from public.spike_projects p
    join public.spike_clients c on c.account_id=p.account_id and c.id=p.client_id
    join public.spike_account_memberships m on m.account_id=p.account_id
      and m.principal_id=ledger_private.current_principal_id() and m.state='active' and m.financial_access='full'
    where p.account_id=p_account_id and p.id=p_project_id;
  if not found then raise sqlstate '42501' using message='fees_not_available'; end if;
  for r in
    select f.*,c.display_name as category_name,m.invoice_id as live_id,i.status as live_status,i.name as live_name,
      i.project_id as live_project,l.invoice_id as paid_id,l.description as paid_description,
      l.signed_amount_minor_units as paid_amount,l.currency as paid_currency,l.category_id as paid_category,
      l.source_revision as paid_revision,h.sealed,h.project_id as paid_project,
      h.display_metadata->>'invoiceNumber' as paid_name
    from ledger_private.fee_installments f
    left join public.spike_budget_categories c on c.account_id=f.account_id and c.id=f.category_id
    left join ledger_private.live_invoice_memberships m on m.account_id=f.account_id
      and m.source_kind='fee_installment' and m.source_id=f.id and m.released_at is null
    left join ledger_private.live_invoices i on i.account_id=m.account_id and i.id=m.invoice_id
    left join ledger_private.collected_invoice_lines l on l.account_id=f.account_id
      and l.source_kind='fee_installment' and l.source_id=f.id
    left join ledger_private.collected_invoices h on h.account_id=l.account_id and h.id=l.invoice_id
    where f.account_id=p_account_id and f.project_id=p_project_id order by f.id
  loop
    if (r.paid_id is not null and (r.sealed is distinct from true or r.paid_project is distinct from p_project_id
          or (r.live_id is not null and r.live_id<>r.paid_id)))
      or (r.paid_id is null and r.live_id is not null and
          (r.live_project is distinct from p_project_id or r.live_status not in ('created','sent'))) then
      raise sqlstate '55000' using message='fee_history_incomplete';
    end if;
    rows:=rows || jsonb_build_array(jsonb_build_object('id',r.id,
      'label',case when r.paid_id is not null then r.paid_description else r.label end,
      'amountMinorUnits',(case when r.paid_id is not null then r.paid_amount else r.amount_minor_units end)::text,
      'currency',coalesce(r.paid_currency,r.currency),'categoryId',coalesce(r.paid_category,r.category_id),
      'categoryName',case when r.paid_id is null then r.category_name end,
      'revision',coalesce(r.paid_revision,r.revision)::text,
      'status',case when r.paid_id is not null then 'paid' when r.live_id is not null then r.live_status else 'available' end,
      'invoiceId',coalesce(r.paid_id,r.live_id),
      'invoiceName',case when r.paid_id is not null then r.paid_name else r.live_name end));
  end loop;
  return jsonb_build_object('accountId',p_account_id,'projectId',p_project_id,'clientId',client,
    'canCreate',can_create,'fees',rows);
end;
$$;
revoke all on function ledger_private.read_project_fees(text,text) from public,anon,authenticated,service_role;
grant execute on function ledger_private.read_project_fees(text,text) to authenticated;
create function public.spike_read_project_fees(p_account_id text,p_project_id text)
returns jsonb language sql stable security invoker set search_path='' as $$
  select ledger_private.read_project_fees(p_account_id,p_project_id)
$$;
revoke all on function public.spike_read_project_fees(text,text) from public,anon,authenticated,service_role;
grant execute on function public.spike_read_project_fees(text,text) to authenticated;
