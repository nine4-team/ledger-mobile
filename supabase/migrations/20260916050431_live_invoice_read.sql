-- One statement snapshot of live source facts. Paid Invoices use the existing
-- frozen read; no partial redaction or inferred zero values.
create function ledger_private.read_live_invoice(p_account_id text,p_project_id text,p_invoice_id text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare h ledger_private.live_invoices; r record; lines jsonb:='[]'::jsonb;
  total numeric:=0; currency text; client text; position integer:=0;
begin
  if (select auth.uid()) is null then raise sqlstate '42501' using message='invoice_not_available'; end if;
  select i.* into h from ledger_private.live_invoices i
    join public.spike_account_memberships m on m.account_id=i.account_id
      and m.principal_id=ledger_private.current_principal_id() and m.state='active' and m.financial_access='full'
    where i.account_id=p_account_id and i.project_id=p_project_id and i.id=p_invoice_id and i.status in ('created','sent');
  if not found then raise sqlstate '42501' using message='invoice_not_available'; end if;
  select client_id into client from public.spike_projects where account_id=h.account_id and id=h.project_id;
  if not found then raise sqlstate '55000' using message='invoice_sources_incomplete'; end if;
  for r in
    select m.source_kind,m.source_id,m.position,
      coalesce(i.revision,e.revision,f.revision) as source_revision,
      coalesce(i.amount_minor_units,e.final_amount_minor_units,f.amount_minor_units) as amount,
      coalesce(i.currency,e.currency,f.currency) as currency,
      coalesce(i.category_id,e.category_id,f.category_id) as category_id,
      case m.source_kind when 'item' then item.description when 'expense' then e.vendor else f.label end as description,
      exists(select 1 from ledger_private.collected_invoice_lines paid where paid.account_id=m.account_id
        and paid.source_kind=m.source_kind and paid.source_id=m.source_id) as collected
    from ledger_private.live_invoice_memberships m
    left join ledger_private.item_charge_occurrences i on m.source_kind='item' and i.account_id=m.account_id
      and i.id=m.source_id and i.project_id=h.project_id and i.withdrawn_at is null
    left join public.spike_items item on item.account_id=i.account_id and item.id=i.item_id
    left join ledger_private.expenses e on m.source_kind='expense' and e.account_id=m.account_id
      and e.id=m.source_id and e.project_id=h.project_id
    left join ledger_private.fee_installments f on m.source_kind='fee_installment' and f.account_id=m.account_id
      and f.id=m.source_id and f.project_id=h.project_id
    where m.account_id=h.account_id and m.invoice_id=h.id and m.released_at is null order by m.position
  loop
    if r.source_revision is null or r.amount is null or r.currency is null or r.category_id is null
      or r.description is null or r.position<>position or r.collected then
      raise sqlstate '55000' using message='invoice_sources_incomplete';
    end if;
    if currency is not null and currency<>r.currency then raise sqlstate '55000' using message='invoice_currency_mismatch'; end if;
    currency:=r.currency; total:=total+r.amount;
    lines:=lines || jsonb_build_array(jsonb_build_object('kind',r.source_kind,'sourceId',r.source_id,
      'sourceRevision',r.source_revision::text,'amountMinorUnits',r.amount::text,'currency',r.currency,
      'categoryId',r.category_id,'description',r.description));
    position:=position+1;
  end loop;
  if position=0 then raise sqlstate '55000' using message='invoice_sources_incomplete'; end if;
  if total < -9223372036854775808 or total > 9223372036854775807 then
    raise sqlstate '55000' using message='invoice_total_overflow';
  end if;
  return jsonb_build_object('accountId',h.account_id,'projectId',h.project_id,'clientId',client,
    'invoiceId',h.id,'revision',h.revision::text,'status',h.status,'name',h.name,'notes',h.notes,
    'currency',currency,'totalMinorUnits',total::text,'lines',lines);
end;
$$;
revoke all on function ledger_private.read_live_invoice(text,text,text) from public,anon,authenticated,service_role;
grant execute on function ledger_private.read_live_invoice(text,text,text) to authenticated;
create function public.spike_read_live_invoice(p_account_id text,p_project_id text,p_invoice_id text)
returns jsonb language sql stable security invoker set search_path='' as $$
  select ledger_private.read_live_invoice(p_account_id,p_project_id,p_invoice_id)
$$;
revoke all on function public.spike_read_live_invoice(text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.spike_read_live_invoice(text,text,text) to authenticated;
