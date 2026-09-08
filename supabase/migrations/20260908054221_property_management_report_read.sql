-- One coherent physical report read. No payment/billing projection or writes.
create function public.spike_read_property_management_report(
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
  select coalesce(jsonb_agg(jsonb_build_object('accountId',p.account_id,'projectId',p.project_id,
    'itemId',i.id,'placementId',p.id,'spaceId',p.space_id,'name',coalesce(i.name,i.description,''),
    'sku',i.sku,'itemRevision',i.revision::text,'marketValueMinorUnits',i.market_value_minor_units::text,
    'marketValueCurrency',i.market_value_currency) order by i.id,p.id),'[]'::jsonb)
    into v_items from public.spike_item_placements p join public.spike_items i
      on i.account_id=p.account_id and i.id=p.item_id
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
