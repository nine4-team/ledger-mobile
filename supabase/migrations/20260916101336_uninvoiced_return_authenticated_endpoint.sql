-- Existing narrow command boundary: all business authorization remains in the
-- private handler; clients receive no table write privileges.
create function public.spike_return_uninvoiced_items(p_command text)
returns public.spike_operation_results language sql security invoker set search_path='' as $$
  select ledger_private.return_uninvoiced_items(p_command)
$$;
revoke all on function public.spike_return_uninvoiced_items(text) from public,anon,service_role;
grant execute on function public.spike_return_uninvoiced_items(text) to authenticated;
grant execute on function ledger_private.return_uninvoiced_items(text) to authenticated;

-- Read-only selection review. No amounts, Invoice identities or inaccessible
-- selections escape; the writer rechecks eligibility under its mutation locks.
create or replace function ledger_private.read_uninvoiced_return_review(p_account_id text,p_project_id text,p_item_ids text[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text; result jsonb;
begin
  actor:=ledger_private.current_principal_id();
  if (select auth.uid()) is null or actor is null then
    raise exception using errcode='42501',message='Authenticated member required';
  end if;
  perform 1 from public.spike_account_memberships where account_id=p_account_id
    and principal_id=actor and state='active' for share;
  if not found then raise exception using errcode='42501',message='Active Account membership required'; end if;
  if p_item_ids is null or cardinality(p_item_ids) not between 1 and 500
    or exists(select 1 from unnest(p_item_ids) id where id is null or id='')
    or (select count(distinct id) from unnest(p_item_ids) id)<>cardinality(p_item_ids) then
    raise exception using errcode='22023',message='Invalid Item selection';
  end if;
  select jsonb_agg(jsonb_build_object('itemId',c.item_id,'placementId',p.id,
    'chargeId',c.id,'revision',c.revision::text) order by c.item_id collate "C") into result
  from ledger_private.item_charge_occurrences c
  join public.spike_item_placements p on p.account_id=c.account_id and p.id=c.placement_id
    and p.item_id=c.item_id and p.project_id=c.project_id
  join public.spike_projects project on project.account_id=c.account_id and project.id=c.project_id and project.lifecycle='active'
  join public.spike_clients client on client.account_id=project.account_id and client.id=project.client_id and client.lifecycle='active'
  join public.spike_budget_categories category on category.account_id=c.account_id and category.id=c.category_id
  where c.account_id=p_account_id and c.project_id=p_project_id and c.item_id=any(p_item_ids)
    and c.withdrawn_at is null and c.revision>0 and c.revision<9223372036854775807
    and p.scope_kind='project' and p.ended_at is null and p.start_evidence='recorded_move'
    and ledger_private.can_view_budget_category(c.account_id,category.visibility_class)
    and exists(select 1 from public.spike_item_placements predecessor where predecessor.account_id=p.account_id
      and predecessor.item_id=p.item_id and predecessor.scope_kind='business_inventory' and predecessor.ended_at=p.started_at)
    and not exists(select 1 from ledger_private.live_invoice_memberships l where l.account_id=c.account_id
      and l.source_kind='item' and l.source_id=c.id and l.released_at is null)
    and not exists(select 1 from ledger_private.collected_invoice_lines l where l.account_id=c.account_id
      and l.source_kind='item' and l.source_id=c.id);
  if coalesce(jsonb_array_length(result),0)<>cardinality(p_item_ids) then
    raise exception using errcode='42501',message='Return selection unavailable';
  end if;
  return jsonb_build_object('accountId',p_account_id,'principalId',actor,'projectId',p_project_id,'items',result);
end;
$$;
revoke all on function ledger_private.read_uninvoiced_return_review(text,text,text[]) from public,anon,authenticated,service_role;
grant execute on function ledger_private.read_uninvoiced_return_review(text,text,text[]) to authenticated;
create or replace function public.spike_read_uninvoiced_return_review(p_account_id text,p_project_id text,p_item_ids text[])
returns jsonb language sql security invoker set search_path='' as $$
  select ledger_private.read_uninvoiced_return_review(p_account_id,p_project_id,p_item_ids)
$$;
revoke all on function public.spike_read_uninvoiced_return_review(text,text,text[]) from public,anon,authenticated,service_role;
grant execute on function public.spike_read_uninvoiced_return_review(text,text,text[]) to authenticated;
