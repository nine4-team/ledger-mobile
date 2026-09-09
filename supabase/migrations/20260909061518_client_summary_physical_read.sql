-- Physical-only Client Summary. Existing RLS governs every source; absent or
-- hidden category/payment evidence remains unavailable, never authoritative absence.
-- STABLE invoker reads share the caller's statement snapshot. No financial totals.
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
    select link.placement_id, link.client_id,
      jsonb_agg(jsonb_build_object('id',link.id,'accountId',link.account_id,
        'projectId',link.project_id,'clientId',link.client_id,'itemId',link.item_id,
        'transactionId',link.transaction_id,'classification',jsonb_build_object(
          'type',link.transaction_type,'role',link.transaction_role,'scope',jsonb_build_object(
            'ownerKind','project','accountId',link.account_id,'projectId',link.project_id,
            'clientId',link.client_id))) order by link.id) as purchases
    from ledger_private.item_client_payment_connections link
    join public.spike_item_placements placement on placement.account_id=link.account_id
      and placement.id=link.placement_id and placement.item_id=link.item_id
      and placement.project_id=link.project_id and placement.scope_kind='project' and placement.ended_at is null
    join public.spike_projects project on project.account_id=link.account_id
      and project.id=link.project_id and project.client_id=link.client_id
    where link.account_id=p_account_id and link.project_id=p_project_id and link.ended_at is null
    group by link.placement_id,link.client_id
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
    'accounting',case when evidence.placement_id is null then null else jsonb_build_object(
      'evidence',jsonb_build_object('accountId',p.account_id,'projectId',p.project_id,
        'clientId',evidence.client_id,'itemId',i.id,'spaceId',p.space_id,
        'clientPaidPurchases',evidence.purchases,'billableOccurrences','[]'::jsonb),
      'relationshipAbsenceIsAuthoritative',false,'resolution','accountedFor') end) order by i.id,p.id),'[]'::jsonb)
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
