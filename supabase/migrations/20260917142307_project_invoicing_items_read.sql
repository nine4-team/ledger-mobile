-- Same historical Item sources as the native Invoicing reader. No current
-- placement filter, writes, credit settlement or new table grants.
create function ledger_private.read_project_invoicing_items(p_account_id text,p_project_id text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor text:=ledger_private.current_principal_id(); r record; rows jsonb:='[]'::jsonb;
begin
  if (select auth.uid()) is null or not exists(
    select 1 from public.spike_projects p join public.spike_account_memberships m on m.account_id=p.account_id
    where p.account_id=p_account_id and p.id=p_project_id and m.principal_id=actor
      and m.state='active' and m.financial_access='full'
  ) then raise sqlstate '42501' using message='invoicing_not_available'; end if;
  for r in
    select c.*,coalesce(i.name,i.description) as title,b.display_name as category_name,
      m.invoice_id as live_id,h.project_id as live_project,h.status as live_status,h.name as live_name,
      l.invoice_id as paid_id,l.item_id as paid_item,l.description as paid_description,
      l.category_id as paid_category,l.signed_amount_minor_units as paid_amount,l.currency as paid_currency,
      f.project_id as paid_project,f.sealed
    from ledger_private.item_charge_occurrences c
    left join public.spike_items i on i.account_id=c.account_id and i.id=c.item_id
    left join public.spike_budget_categories b on b.account_id=c.account_id and b.id=c.category_id
    left join ledger_private.live_invoice_memberships m on m.account_id=c.account_id
      and m.source_kind='item' and m.source_id=c.id and m.released_at is null
    left join ledger_private.live_invoices h on h.account_id=m.account_id and h.id=m.invoice_id
    left join ledger_private.collected_invoice_lines l on l.account_id=c.account_id and l.source_kind='item' and l.source_id=c.id
    left join ledger_private.collected_invoices f on f.account_id=l.account_id and f.id=l.invoice_id
    where c.account_id=p_account_id and c.project_id=p_project_id and c.withdrawn_at is null order by c.id
  loop
    if (r.paid_id is not null and (r.sealed is distinct from true or r.paid_project is distinct from p_project_id
        or r.paid_item is distinct from r.item_id or r.paid_amount is distinct from r.amount_minor_units
        or r.paid_currency is distinct from r.currency or (r.live_id is not null and r.live_id<>r.paid_id)))
      or (r.live_id is not null and (r.live_project is distinct from p_project_id
        or r.live_status is null or r.live_status not in ('created','sent')))
      or (r.paid_id is null and r.title is null) then
      raise sqlstate '55000' using message='invoicing_history_incomplete';
    end if;
    rows:=rows || jsonb_build_array(jsonb_build_object(
      'occurrenceId',r.id,'itemId',r.item_id,'polarity','charge',
      'amountMinorUnits',r.amount_minor_units::text,'currency',r.currency,
      'availability',case when r.paid_id is not null then 'paid' when r.live_id is not null then r.live_status else 'available' end,
      'invoiceId',coalesce(r.paid_id,r.live_id),'invoiceName',case when r.paid_id is null then r.live_name end,
      'title',case when r.paid_id is not null then r.paid_description else r.title end,
      'categoryId',case when r.paid_id is not null then r.paid_category else r.category_id end,
      'categoryName',case when r.paid_id is null then r.category_name end));
  end loop;
  for r in
    select credit.id,credit.item_id,c.id as charge_id,l.source_kind,l.source_id,l.item_id as paid_item,
      l.signed_amount_minor_units as amount,l.currency,l.description,l.category_id,h.project_id,h.sealed
    from ledger_private.paid_item_return_credits credit
    join ledger_private.item_charge_occurrences c on c.account_id=credit.account_id and c.id=credit.charge_id
    left join ledger_private.collected_invoice_lines l on l.account_id=credit.account_id and l.id=credit.paid_invoice_line_id
    left join ledger_private.collected_invoices h on h.account_id=l.account_id and h.id=l.invoice_id
    where credit.account_id=p_account_id and c.project_id=p_project_id order by credit.id
  loop
    if r.source_kind is distinct from 'item' or r.source_id is distinct from r.charge_id
      or r.paid_item is distinct from r.item_id or r.project_id is distinct from p_project_id
      or r.sealed is distinct from true or r.amount is null or r.amount<=0 then
      raise sqlstate '55000' using message='invoicing_history_incomplete';
    end if;
    rows:=rows || jsonb_build_array(jsonb_build_object('occurrenceId',r.id,'itemId',r.item_id,'polarity','credit',
      'amountMinorUnits',(-r.amount)::text,'currency',r.currency,'availability','available',
      'invoiceId',null,'invoiceName',null,'title',r.description,'categoryId',r.category_id,'categoryName',null));
  end loop;
  return jsonb_build_object('accountId',p_account_id,'principalId',actor,'projectId',p_project_id,'rows',rows);
end;
$$;
revoke all on function ledger_private.read_project_invoicing_items(text,text) from public,anon,authenticated,service_role;
grant execute on function ledger_private.read_project_invoicing_items(text,text) to authenticated;
create function public.spike_read_project_invoicing_items(p_account_id text,p_project_id text)
returns jsonb language sql stable security invoker set search_path='' as $$
  select ledger_private.read_project_invoicing_items(p_account_id,p_project_id)
$$;
revoke all on function public.spike_read_project_invoicing_items(text,text) from public,anon,authenticated,service_role;
grant execute on function public.spike_read_project_invoicing_items(text,text) to authenticated;
