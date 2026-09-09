-- Shared physical-report accounting facts, governed by current full membership.
grant select (id,account_id,project_id,item_id,placement_id,category_id,amount_minor_units,currency,revision,withdrawn_at)
 on ledger_private.item_charge_occurrences to authenticated;
grant select (id,account_id,invoice_id,source_kind,source_id,item_id,source_revision,category_id,signed_amount_minor_units,currency)
 on ledger_private.collected_invoice_lines to authenticated;
grant select (id,account_id,project_id,client_id,sealed)
 on ledger_private.collected_invoices to authenticated;
create policy item_charge_occurrences_full_member_read on ledger_private.item_charge_occurrences
 for select to authenticated using (exists (
  select 1 from public.spike_principals principal join public.spike_account_memberships membership
   on membership.principal_id=principal.id
  where principal.auth_user_id=(select auth.uid()) and membership.account_id=item_charge_occurrences.account_id
   and membership.state='active' and membership.financial_access='full'
 ));
create policy collected_invoice_lines_full_member_read on ledger_private.collected_invoice_lines
 for select to authenticated using (exists (
  select 1 from public.spike_principals principal join public.spike_account_memberships membership
   on membership.principal_id=principal.id
  where principal.auth_user_id=(select auth.uid()) and membership.account_id=collected_invoice_lines.account_id
   and membership.state='active' and membership.financial_access='full'
 ));
create policy collected_invoices_full_member_read on ledger_private.collected_invoices
 for select to authenticated using (exists (
  select 1 from public.spike_principals principal join public.spike_account_memberships membership
   on membership.principal_id=principal.id
  where principal.auth_user_id=(select auth.uid()) and membership.account_id=collected_invoices.account_id
   and membership.state='active' and membership.financial_access='full'
 ));

create function ledger_private.project_item_accounting_evidence(p_account text,p_project text)
returns table(placement_id text,accounting jsonb)
language sql stable security invoker set search_path='' as $$
 with scoped as (
  select placement.id,placement.account_id,placement.project_id,placement.item_id,placement.space_id,project.client_id
  from public.spike_item_placements placement join public.spike_projects project
   on project.account_id=placement.account_id and project.id=placement.project_id
  where placement.account_id=p_account and placement.project_id=p_project
   and placement.scope_kind='project' and placement.ended_at is null
 ), payments as (
  select link.placement_id,jsonb_agg(jsonb_build_object(
   'id',link.id,'accountId',link.account_id,'projectId',link.project_id,'clientId',link.client_id,
   'itemId',link.item_id,'transactionId',link.transaction_id,'classification',jsonb_build_object(
    'type',link.transaction_type,'role',link.transaction_role,'scope',jsonb_build_object(
      'ownerKind','project','accountId',link.account_id,'projectId',link.project_id,'clientId',link.client_id)))
    order by link.id) as facts
  from ledger_private.item_client_payment_connections link join scoped
   on scoped.id=link.placement_id and scoped.account_id=link.account_id
    and scoped.project_id=link.project_id and scoped.item_id=link.item_id and scoped.client_id=link.client_id
  where link.ended_at is null group by link.placement_id
 ), charges as (
  select charge.placement_id,jsonb_agg(jsonb_build_object(
   'id',charge.id,'accountId',charge.account_id,'projectId',charge.project_id,'itemId',charge.item_id,
   'polarity','charge','phase',case when line.id is null then jsonb_build_object('kind','availableToInvoice')
    else jsonb_build_object('kind','frozenPaid','invoiceId',invoice.id) end) order by charge.id) as facts
  from ledger_private.item_charge_occurrences charge join scoped
   on scoped.id=charge.placement_id and scoped.account_id=charge.account_id
    and scoped.project_id=charge.project_id and scoped.item_id=charge.item_id
  left join ledger_private.collected_invoice_lines line on line.account_id=charge.account_id
   and line.source_kind='item' and line.source_id=charge.id
  left join ledger_private.collected_invoices invoice on invoice.account_id=line.account_id and invoice.id=line.invoice_id
   and invoice.project_id=charge.project_id and invoice.client_id=scoped.client_id and invoice.sealed
  where charge.withdrawn_at is null group by charge.placement_id
 )
 select scoped.id,jsonb_build_object('evidence',jsonb_build_object(
  'accountId',scoped.account_id,'projectId',scoped.project_id,'clientId',scoped.client_id,
  'itemId',scoped.item_id,'spaceId',scoped.space_id,
  'clientPaidPurchases',coalesce(payments.facts,'[]'::jsonb),'billableOccurrences',coalesce(charges.facts,'[]'::jsonb)),
  'relationshipAbsenceIsAuthoritative',false,'resolution','accountedFor')
 from scoped left join payments on payments.placement_id=scoped.id left join charges on charges.placement_id=scoped.id
 where payments.placement_id is not null or charges.placement_id is not null;
$$;
revoke all on function ledger_private.project_item_accounting_evidence(text,text) from public,anon,service_role;
grant execute on function ledger_private.project_item_accounting_evidence(text,text) to authenticated;

create or replace function public.spike_read_property_management_report(
  p_account_id text, p_project_id text, p_currency text
) returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  v_principal text;
  v_project jsonb;
  v_spaces jsonb;
  v_items jsonb;
  v_visibility text;
begin
  select p.id into v_principal from public.spike_principals p
    join public.spike_account_memberships m on m.principal_id=p.id
    where p.auth_user_id=(select auth.uid()) and m.account_id=p_account_id and m.state='active';
  if v_principal is null then
    raise exception using errcode='42501', message='account_not_authorized';
  end if;
  if p_currency is null or p_currency !~ '^[A-Z]{3}$' then
    raise exception using errcode='22023', message='property_report_invalid_currency';
  end if;
  select jsonb_build_object('accountId',p.account_id,'projectId',p.id,
    'name',p.display_name,'address',p.property_address,'revision',p.revision::text)
    into v_project from public.spike_projects p where p.account_id=p_account_id and p.id=p_project_id;
  if v_project is null then
    raise exception using errcode='42501', message='property_report_project_unavailable';
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('accountId',s.account_id,'projectId',s.project_id,
    'spaceId',s.id,'name',s.display_name,'revision',s.revision::text) order by s.id),'[]'::jsonb)
    into v_spaces from public.spike_spaces s
    where s.account_id=p_account_id and s.project_id=p_project_id and s.scope_kind='project'
      and (s.lifecycle='active' or exists(select 1 from public.spike_item_placements p
        where p.account_id=p_account_id and p.project_id=p_project_id and p.space_id=s.id and p.ended_at is null));
  -- Do not silently omit a placement whose Item/Space evidence is unreadable.
  if exists(select 1 from public.spike_item_placements p
    left join public.spike_items i on i.account_id=p.account_id and i.id=p.item_id
    left join public.spike_spaces s on s.account_id=p.account_id and s.id=p.space_id
      and s.project_id=p.project_id and s.scope_kind='project'
    where p.account_id=p_account_id and p.project_id=p_project_id and p.ended_at is null
      and (i.id is null or (p.space_id is not null and s.id is null))) then
    raise exception using errcode='22000', message='property_report_incomplete_evidence';
  end if;
  if exists(select 1 from public.spike_item_placements p join public.spike_items i
    on i.account_id=p.account_id and i.id=p.item_id
    where p.account_id=p_account_id and p.project_id=p_project_id and p.ended_at is null
      and i.market_value_currency is not null and i.market_value_currency<>p_currency) then
    raise exception using errcode='22023', message='property_report_mixed_currency';
  end if;
  with payment_evidence as (
    select * from ledger_private.project_item_accounting_evidence(p_account_id,p_project_id)
  )
  select coalesce(jsonb_agg(jsonb_build_object('accountId',p.account_id,'projectId',p.project_id,
    'itemId',i.id,'placementId',p.id,'spaceId',p.space_id,'name',coalesce(i.name,i.description,''),
    'sku',i.sku,'itemRevision',i.revision::text,'marketValueMinorUnits',i.market_value_minor_units::text,
    'marketValueCurrency',i.market_value_currency,
    'accounting',evidence.accounting) order by i.id,p.id),'[]'::jsonb)
    into v_items from public.spike_item_placements p join public.spike_items i
      on i.account_id=p.account_id and i.id=p.item_id
    left join payment_evidence evidence on evidence.placement_id=p.id
    where p.account_id=p_account_id and p.project_id=p_project_id and p.ended_at is null;
  -- Match the native scope fingerprint's compact JSON array, not jsonb spacing.
  v_visibility := encode(extensions.digest(convert_to('[' || to_json(p_account_id)::text || ',' ||
    to_json(v_principal)::text || ',' || to_json(p_project_id)::text || ',"physical-property-report-v1"]','UTF8'),'sha256'),'hex');
  return jsonb_build_object('project',v_project,'spaces',v_spaces,'items',v_items,'currency',p_currency,
    'provenance',jsonb_build_object('accountId',p_account_id,'projectId',p_project_id,'principalId',v_principal,
      'visibilityScopeID',v_visibility,'source',jsonb_build_object('kind','authoritative'),
      'authorityVersion','property-management-v1','asOf',floor(extract(epoch from statement_timestamp())*1000)::bigint,
      'readiness','ready'));
end;
$$;
revoke all on function public.spike_read_property_management_report(text,text,text) from public,anon,service_role;
grant execute on function public.spike_read_property_management_report(text,text,text) to authenticated;

create or replace function public.spike_read_client_summary_physical_report(
  p_account_id text, p_project_id text
) returns jsonb language plpgsql stable security invoker set search_path = '' as $$
declare
  v_principal text;
  v_project jsonb;
  v_client jsonb;
  v_spaces jsonb;
  v_items jsonb;
  v_visibility text;
begin
  select p.id into v_principal from public.spike_principals p
    join public.spike_account_memberships m on m.principal_id=p.id
    where p.auth_user_id=(select auth.uid()) and m.account_id=p_account_id and m.state='active';
  if v_principal is null then
    raise exception using errcode='42501', message='account_not_authorized';
  end if;
  select jsonb_build_object('accountId',p.account_id,'projectId',p.id,
    'name',p.display_name,'address',p.property_address,'revision',p.revision::text)
    into v_project from public.spike_projects p where p.account_id=p_account_id and p.id=p_project_id;
  if v_project is null then
    raise exception using errcode='42501', message='client_summary_physical_project_unavailable';
  end if;
  select case when c.id is null then jsonb_build_object('kind','unavailable','clientId',p.client_id)
    else jsonb_build_object('kind','known','clientId',c.id,'name',c.display_name,'revision',c.revision::text) end
    into v_client from public.spike_projects p
    left join public.spike_clients c on c.account_id=p.account_id and c.id=p.client_id
    where p.account_id=p_account_id and p.id=p_project_id;
  select coalesce(jsonb_agg(jsonb_build_object('accountId',s.account_id,'projectId',s.project_id,
    'spaceId',s.id,'name',s.display_name,'revision',s.revision::text) order by s.id),'[]'::jsonb)
    into v_spaces from public.spike_spaces s
    where s.account_id=p_account_id and s.project_id=p_project_id and s.scope_kind='project'
      and (s.lifecycle='active' or exists(select 1 from public.spike_item_placements p
        where p.account_id=p_account_id and p.project_id=p_project_id and p.space_id=s.id and p.ended_at is null));
  -- Do not silently omit a placement whose Item/Space evidence is unreadable.
  if exists(select 1 from public.spike_item_placements p
    left join public.spike_items i on i.account_id=p.account_id and i.id=p.item_id
    left join public.spike_spaces s on s.account_id=p.account_id and s.id=p.space_id
      and s.project_id=p.project_id and s.scope_kind='project'
    where p.account_id=p_account_id and p.project_id=p_project_id and p.ended_at is null
      and (i.id is null or (p.space_id is not null and s.id is null))) then
    raise exception using errcode='22000', message='client_summary_physical_incomplete_evidence';
  end if;
  with payment_evidence as (
    select * from ledger_private.project_item_accounting_evidence(p_account_id,p_project_id)
  )
  select coalesce(jsonb_agg(jsonb_build_object('accountId',p.account_id,'projectId',p.project_id,
    'itemId',i.id,'placementId',p.id,'spaceId',p.space_id,'name',coalesce(i.name,i.description,''),
    'sku',i.sku,'itemRevision',i.revision::text,
    -- Match Foundation whitespacesAndNewlines in the downloaded reader. Legacy
    -- or imported whitespace-only labels must remain unavailable in both paths.
    'category',case when category.id is null or btrim(category.display_name,
      U&' \0009\000A\000B\000C\000D\0085\00A0\1680\2000\2001\2002\2003\2004\2005\2006\2007\2008\2009\200A\200B\2028\2029\202F\205F\3000')=''
      then jsonb_build_object('unavailable','{}'::jsonb)
      else jsonb_build_object('known',jsonb_build_object('categoryId',category.id,'name',category.display_name)) end,
    'accounting',evidence.accounting) order by i.id,p.id),'[]'::jsonb)
    into v_items from public.spike_item_placements p join public.spike_items i
      on i.account_id=p.account_id and i.id=p.item_id
    left join payment_evidence evidence on evidence.placement_id=p.id
    left join public.spike_item_project_categories assignment on assignment.account_id=p.account_id
      and assignment.project_id=p.project_id and assignment.item_id=p.item_id and assignment.id=p.id
    left join public.spike_budget_categories category on category.account_id=assignment.account_id
      and category.id=assignment.category_id
    where p.account_id=p_account_id and p.project_id=p_project_id and p.ended_at is null;
  -- Match the native scope fingerprint's compact JSON array, not jsonb spacing.
  v_visibility := encode(extensions.digest(convert_to('[' || to_json(p_account_id)::text || ',' ||
    to_json(v_principal)::text || ',' || to_json(p_project_id)::text || ',"client-summary-physical-v1"]','UTF8'),'sha256'),'hex');
  return jsonb_build_object('project',v_project,'client',v_client,'spaces',v_spaces,'items',v_items,
    'provenance',jsonb_build_object('accountId',p_account_id,'projectId',p_project_id,'principalId',v_principal,
      'visibilityScopeID',v_visibility,'source',jsonb_build_object('kind','authoritative'),
      'authorityVersion','client-summary-physical-v1','asOf',floor(extract(epoch from statement_timestamp())*1000)::bigint,
      'readiness','ready'));
end;
$$;
revoke all on function public.spike_read_client_summary_physical_report(text,text) from public,anon,service_role;
grant execute on function public.spike_read_client_summary_physical_report(text,text) to authenticated;
