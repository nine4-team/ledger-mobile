-- Read-only composition of existing facts, not a second ledger. STABLE keeps
-- authorization, collection membership and amounts on the calling snapshot.
create function ledger_private.read_project_budget(p_account_id text,p_project_id text,p_currency text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor text:=ledger_private.current_principal_id(); client text;
  contributions jsonb; categories jsonb; overall_paid numeric; overall_unpaid numeric; overall_budget numeric;
begin
  select p.client_id into client from public.spike_projects p
    join public.spike_account_memberships m on m.account_id=p.account_id
      and m.principal_id=actor and m.state='active' and m.financial_access='full'
    where p.account_id=p_account_id and p.id=p_project_id;
  if (select auth.uid()) is null or client is null then
    raise sqlstate '42501' using message='budget_not_available';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise sqlstate '22023' using message='budget_currency_invalid';
  end if;
  if exists(select 1 from ledger_private.collected_invoices h
    where h.account_id=p_account_id and h.project_id=p_project_id and not h.sealed)
    or exists(select 1 from public.spike_transactions t
      where t.account_id=p_account_id and t.project_id=p_project_id and (
        t.client_id is distinct from client or t.scope_kind<>'project' or t.role<>'standalone'
        or t.origin not in ('vendor_payment','firebase_client_payment') or t.type not in ('purchase','return')
        or (t.origin='firebase_client_payment' and (t.type<>'purchase' or t.category_id is not null or not exists(
          select 1 from ledger_private.collected_invoices h where h.account_id=t.account_id
            and h.project_id=t.project_id and h.purchase_id=t.id and h.sealed
            and h.total_minor_units=t.amount_minor_units and h.currency=t.currency))))) then
    raise sqlstate '22023' using message='budget_source_incomplete';
  end if;
  with sources as (
    select 'item' as kind,id,account_id,project_id,category_id,amount_minor_units as amount,currency
      from ledger_private.item_charge_occurrences where account_id=p_account_id and project_id=p_project_id and withdrawn_at is null
    union all select 'expense',id,account_id,project_id,category_id,final_amount_minor_units,currency
      from ledger_private.expenses where account_id=p_account_id and project_id=p_project_id
    union all select 'fee_installment',id,account_id,project_id,category_id,amount_minor_units,currency
      from ledger_private.fee_installments where account_id=p_account_id and project_id=p_project_id
  ), facts as (
    select s.category_id,s.currency,0::numeric as paid,s.amount::numeric as unpaid from sources s
      where not exists(select 1 from ledger_private.collected_invoice_lines l
        where l.account_id=s.account_id and l.source_kind=s.kind and l.source_id=s.id)
    union all select l.category_id,l.currency,l.signed_amount_minor_units::numeric,0::numeric
      from ledger_private.collected_invoice_lines l join ledger_private.collected_invoices h
        on h.account_id=l.account_id and h.id=l.invoice_id
      where h.account_id=p_account_id and h.project_id=p_project_id and h.sealed
    union all select l.category_id,l.currency,0::numeric,-l.signed_amount_minor_units::numeric
      from ledger_private.paid_item_return_credits c join ledger_private.collected_invoice_lines l
        on l.account_id=c.account_id and l.id=c.paid_invoice_line_id
      where c.account_id=p_account_id and c.project_id=p_project_id
    union all select t.category_id,t.currency,
        case when t.type='return' then -t.amount_minor_units::numeric else t.amount_minor_units::numeric end,0::numeric
      from public.spike_transactions t where t.account_id=p_account_id and t.project_id=p_project_id
        and t.origin='vendor_payment'
  ) select coalesce(jsonb_agg(to_jsonb(facts)),'[]'::jsonb) into contributions from facts;
  if exists(select 1 from jsonb_to_recordset(contributions) f(category_id text,currency text,paid numeric,unpaid numeric)
    where f.currency<>p_currency or not exists(select 1 from public.spike_budget_categories c
      where c.account_id=p_account_id and c.id=f.category_id))
    or exists(select 1 from public.spike_project_category_allocations a where a.account_id=p_account_id
      and a.project_id=p_project_id and a.allocation_currency is not null and a.allocation_currency<>p_currency) then
    raise sqlstate '22023' using message='budget_source_incomplete';
  end if;
  with amounts as (
    select category_id,sum(paid) as paid,sum(unpaid) as unpaid
      from jsonb_to_recordset(contributions) f(category_id text,currency text,paid numeric,unpaid numeric) group by category_id
  ) select coalesce(jsonb_agg(jsonb_build_object('id',c.id,'name',c.display_name,'kind',c.kind,
    'excludesFromOverallBudget',c.excludes_from_overall_budget,'enabled',a.id is not null,
    'allocationMinorUnits',a.allocation_minor_units::text,'paidMinorUnits',coalesce(v.paid,0)::bigint::text,
    'unpaidMinorUnits',coalesce(v.unpaid,0)::bigint::text,
    'recognizedMinorUnits',(coalesce(v.paid,0)+coalesce(v.unpaid,0))::bigint::text) order by c.id),'[]'::jsonb),
    coalesce(sum(coalesce(v.paid,0)) filter(where not c.excludes_from_overall_budget),0),
    coalesce(sum(coalesce(v.unpaid,0)) filter(where not c.excludes_from_overall_budget),0),
    coalesce(sum(coalesce(a.allocation_minor_units,0)::numeric) filter(where not c.excludes_from_overall_budget),0)
    into categories,overall_paid,overall_unpaid,overall_budget
    from public.spike_budget_categories c left join amounts v on v.category_id=c.id
    left join public.spike_project_category_allocations a on a.account_id=c.account_id
      and a.category_id=c.id and a.project_id=p_project_id where c.account_id=p_account_id;
  return jsonb_build_object('accountId',p_account_id,'principalId',actor,'projectId',p_project_id,'clientId',client,
    'currency',p_currency,'isCompleteForProjectBudget',false,'missingCoverage',jsonb_build_array('transfers','additional_requests'),
    'categories',categories,'overallPaidMinorUnits',overall_paid::bigint::text,'overallUnpaidMinorUnits',overall_unpaid::bigint::text,
    'overallRecognizedMinorUnits',(overall_paid+overall_unpaid)::bigint::text,'overallBudgetMinorUnits',overall_budget::bigint::text);
end;
$$;
revoke all on function ledger_private.read_project_budget(text,text,text) from public,anon,authenticated,service_role;
grant execute on function ledger_private.read_project_budget(text,text,text) to authenticated;
create function public.spike_read_project_budget(p_account_id text,p_project_id text,p_currency text)
returns jsonb language sql stable security invoker set search_path='' as $$
  select ledger_private.read_project_budget(p_account_id,p_project_id,p_currency)
$$;
revoke all on function public.spike_read_project_budget(text,text,text) from public,anon,authenticated,service_role;
grant execute on function public.spike_read_project_budget(text,text,text) to authenticated;
