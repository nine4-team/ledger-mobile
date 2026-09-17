-- A paid return is new evidence, never a withdrawal of the frozen positive charge.
create table ledger_private.paid_item_return_credits (
  id text primary key check(id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id)<=128),
  account_id text not null,
  charge_id text not null,
  paid_invoice_line_id text not null unique references ledger_private.collected_invoice_lines(id),
  return_occurrence_id text not null unique
    check(return_occurrence_id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(return_occurrence_id)<=128),
  inventory_placement_id text not null,
  item_id text not null,
  unique(account_id,charge_id),
  unique(account_id,inventory_placement_id),
  foreign key(account_id,charge_id) references ledger_private.item_charge_occurrences(account_id,id),
  foreign key(account_id,inventory_placement_id,item_id) references public.spike_item_placements(account_id,id,item_id)
);
alter table ledger_private.paid_item_return_credits enable row level security;
alter table ledger_private.paid_item_return_credits force row level security;
revoke all on ledger_private.paid_item_return_credits from public,anon,authenticated,service_role;

create or replace function ledger_private.guard_paid_item_return_credit() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if tg_op<>'INSERT' then
    raise sqlstate '55000' using message='Paid return credit provenance is immutable';
  end if;
  if not exists (
    select 1 from ledger_private.item_charge_occurrences c
    join ledger_private.collected_invoice_lines l on l.account_id=c.account_id
      and l.source_kind='item' and l.source_id=c.id and l.item_id=c.item_id
    join ledger_private.collected_invoices i on i.account_id=l.account_id and i.id=l.invoice_id
      and i.project_id=c.project_id and i.sealed
    join public.spike_item_placements source_placement on source_placement.account_id=c.account_id and source_placement.id=c.placement_id
      and source_placement.item_id=c.item_id and source_placement.project_id=c.project_id and source_placement.scope_kind='project'
    join public.spike_item_placements successor on successor.account_id=c.account_id
      and successor.id=new.inventory_placement_id and successor.item_id=c.item_id
      and successor.scope_kind='business_inventory' and successor.started_at=source_placement.ended_at
    where c.account_id=new.account_id and c.id=new.charge_id and c.item_id=new.item_id
      and l.id=new.paid_invoice_line_id and l.signed_amount_minor_units>0
      and c.withdrawn_at is null and source_placement.start_evidence='recorded_move'
      and exists(select 1 from public.spike_item_placements predecessor
        where predecessor.account_id=c.account_id and predecessor.item_id=c.item_id
          and predecessor.scope_kind='business_inventory' and predecessor.ended_at=source_placement.started_at)
  ) then raise sqlstate '23514' using message='Paid credit requires exact frozen sale and physical return'; end if;
  return new;
end;
$$;
revoke all on function ledger_private.guard_paid_item_return_credit() from public,anon,authenticated,service_role;
create trigger paid_return_credit_evidence before insert or update or delete on ledger_private.paid_item_return_credits
for each row execute function ledger_private.guard_paid_item_return_credit();
create trigger paid_return_credit_no_truncate before truncate on ledger_private.paid_item_return_credits
for each statement execute function ledger_private.guard_paid_item_return_credit();

alter table public.spike_operation_results drop constraint spike_operation_results_command_type_check;
alter table public.spike_operation_results add constraint spike_operation_results_command_type_check check
 (command_type in ('create_client','create_project','archive_project','archive_client','revise_space_checklists','manage_categories','sell_inventory_items','create_expense','edit_expense','create_invoice','create_fee_installment','revise_created_invoice','return_uninvoiced_items','edit_uncollected_item_price','edit_item_details','return_paid_items'));

create function ledger_private.return_paid_items(p_command text)
returns public.spike_operation_results language plpgsql security definer set search_path='' as $$
declare c jsonb:=p_command::jsonb; actor text; account text; operation text; fingerprint text;
  entry jsonb; result public.spike_operation_results; failure text; client text;
  charge ledger_private.item_charge_occurrences; placement public.spike_item_placements;
  paid_line ledger_private.collected_invoice_lines; received timestamptz;
begin
  if current_setting('transaction_isolation')<>'read committed' then
    raise sqlstate '25001' using message='Return requires READ COMMITTED';
  end if;
  actor:=c->>'actorPrincipalId'; account:=c->>'accountId'; operation:=c->>'operationId';
  if (select auth.uid()) is null or actor is distinct from ledger_private.current_principal_id() then
    raise sqlstate '42501' using message='Authenticated actor required';
  end if;
  perform 1 from public.spike_account_memberships where account_id=account and principal_id=actor
    and state='active' for share;
  if not found then raise sqlstate '42501' using message='Active Account membership required'; end if;
  if jsonb_typeof(c) is distinct from 'object' or c->>'contractVersion' is distinct from 'return-paid-items-v1'
    or not(c ?& array['operationId','accountId','actorPrincipalId','projectId','contractVersion','createdAtMs','items'])
    or c-array['operationId','accountId','actorPrincipalId','projectId','contractVersion','createdAtMs','items']<>'{}'::jsonb
    or exists(select 1 from jsonb_each(c-'items') where jsonb_typeof(value)<>'string')
    or operation !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(operation)>128
    or c->>'createdAtMs' !~ '^(0|[1-9][0-9]*)$' or (c->>'createdAtMs')::numeric>=1000000000000000
    or jsonb_typeof(c->'items') is distinct from 'array' or jsonb_array_length(c->'items') not between 1 and 100 then
    raise sqlstate '22023' using message='Invalid paid return command';
  end if;
  fingerprint:=encode(extensions.digest(convert_to(p_command,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(operation,0));
  select * into result from public.spike_operation_results where operation_id=operation;
  if found then
    if row(result.account_id,result.actor_principal_id,result.command_type,result.command_fingerprint)
      is distinct from row(account,actor,'return_paid_items'::text,fingerprint) then
      raise sqlstate '23505' using message='Operation identity conflict';
    end if;
    return result;
  end if;
  begin
    select client_id into client from public.spike_projects where account_id=account and id=c->>'projectId'
      and lifecycle='active' for share;
    if not found then raise exception 'return_project_unavailable'; end if;
    perform 1 from public.spike_clients where account_id=account and id=client and lifecycle='active' for share;
    if not found then raise exception 'return_project_unavailable'; end if;
    for entry in select value from jsonb_array_elements(c->'items') order by value->>'itemId' collate "C" loop
      if jsonb_typeof(entry) is distinct from 'object'
        or not(entry ?& array['itemId','placementId','chargeId','paidInvoiceLineId','inventoryPlacementId','returnOccurrenceId','creditId'])
        or entry-array['itemId','placementId','chargeId','paidInvoiceLineId','inventoryPlacementId','returnOccurrenceId','creditId']<>'{}'::jsonb
        or exists(select 1 from jsonb_each(entry) where jsonb_typeof(value)<>'string')
        or exists(select 1 from jsonb_each_text(entry)
          where value !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(value)>128)
        then raise exception 'return_item_invalid'; end if;
      perform 1 from public.spike_items where account_id=account and id=entry->>'itemId' for update;
      if not found then raise exception 'return_item_unavailable'; end if;
    end loop;
    if exists(select 1 from jsonb_array_elements(c->'items') group by value->>'itemId' having count(*)>1) then
      raise exception 'return_duplicate_item';
    end if;
    for entry in select value from jsonb_array_elements(c->'items') order by value->>'chargeId' loop
      perform ledger_private.lock_item_charge_source(account,entry->>'chargeId');
    end loop;
    received:=clock_timestamp();
    for entry in select value from jsonb_array_elements(c->'items') order by value->>'itemId' collate "C" loop
      select * into placement from public.spike_item_placements where account_id=account
        and id=entry->>'placementId' and item_id=entry->>'itemId' and project_id=c->>'projectId'
        and scope_kind='project' and ended_at is null for update;
      if not found or placement.started_at>=received then raise exception 'return_placement_stale'; end if;
      select * into charge from ledger_private.item_charge_occurrences where account_id=account
        and id=entry->>'chargeId' and item_id=placement.item_id and placement_id=placement.id
        and project_id=placement.project_id and withdrawn_at is null for update;
      if not found then raise exception 'return_charge_stale'; end if;
      select l.* into paid_line from ledger_private.collected_invoice_lines l
        join ledger_private.collected_invoices i on i.account_id=l.account_id and i.id=l.invoice_id
          and i.project_id=placement.project_id and i.sealed
        where l.account_id=account and l.id=entry->>'paidInvoiceLineId' and l.source_kind='item'
          and l.source_id=charge.id and l.item_id=placement.item_id and l.signed_amount_minor_units>0;
      if not found then raise exception 'return_paid_basis_unavailable'; end if;
      if not ledger_private.can_view_budget_category(account,(select visibility_class from public.spike_budget_categories
        where account_id=account and id=paid_line.category_id)) then raise exception 'return_charge_unavailable'; end if;
      if placement.start_evidence<>'recorded_move' or not exists(select 1 from public.spike_item_placements
        where account_id=account and item_id=placement.item_id and scope_kind='business_inventory'
          and ended_at=placement.started_at) then raise exception 'return_origin_unproven'; end if;
      update public.spike_item_placements set ended_at=received,ended_by_principal_id=actor where id=placement.id;
      insert into public.spike_item_placements(id,account_id,item_id,scope_kind,started_at,started_by_principal_id)
        values(entry->>'inventoryPlacementId',account,placement.item_id,'business_inventory',received,actor);
      insert into ledger_private.paid_item_return_credits
        (id,account_id,charge_id,paid_invoice_line_id,return_occurrence_id,inventory_placement_id,item_id)
        values(entry->>'creditId',account,charge.id,paid_line.id,entry->>'returnOccurrenceId',
          entry->>'inventoryPlacementId',placement.item_id);
    end loop;
  exception
    when raise_exception then failure:=SQLERRM;
    when integrity_constraint_violation or numeric_value_out_of_range then failure:='return_integrity_conflict';
  end;
  received:=coalesce(received,clock_timestamp());
  insert into public.spike_operation_results(operation_id,account_id,actor_principal_id,command_type,contract_version,
    command_fingerprint,envelope_sha256,subject_id,phase,result_code,error_code,client_created_at,server_received_at,
    completed_at,client_created_at_ms,server_received_at_ms,completed_at_ms)
  values(operation,account,actor,'return_paid_items','return-paid-items-v1',fingerprint,fingerprint,c->>'projectId',
    case when failure is null then 'applied' else 'rejected' end,
    case when failure is null then 'paid_items_returned' end,failure,
    to_timestamp((c->>'createdAtMs')::bigint/1000.0),received,received,(c->>'createdAtMs')::bigint,
    floor(extract(epoch from received)*1000)::bigint,floor(extract(epoch from received)*1000)::bigint)
  returning * into result;
  return result;
end;
$$;
revoke all on function ledger_private.return_paid_items(text) from public,anon,authenticated,service_role;
create function public.spike_return_paid_items(p_command text)
returns public.spike_operation_results language sql security invoker set search_path='' as $$
  select ledger_private.return_paid_items(p_command)
$$;
revoke all on function public.spike_return_paid_items(text) from public,anon,service_role;
grant execute on function public.spike_return_paid_items(text) to authenticated;
grant execute on function ledger_private.return_paid_items(text) to authenticated;

create or replace function ledger_private.read_paid_return_review(p_account_id text,p_project_id text,p_item_ids text[])
returns jsonb language plpgsql security definer set search_path='' as $$
declare actor text; result jsonb;
begin
  actor:=ledger_private.current_principal_id();
  if (select auth.uid()) is null or actor is null then
    raise sqlstate '42501' using message='Authenticated member required';
  end if;
  perform 1 from public.spike_account_memberships where account_id=p_account_id and principal_id=actor
    and state='active' and financial_access='full' for share;
  if not found then raise sqlstate '42501' using message='Financial access required'; end if;
  if p_item_ids is null or cardinality(p_item_ids) not between 1 and 100
    or exists(select 1 from unnest(p_item_ids) id where id is null or id='')
    or (select count(distinct id) from unnest(p_item_ids) id)<>cardinality(p_item_ids) then
    raise sqlstate '22023' using message='Invalid Item selection';
  end if;
  select jsonb_agg(jsonb_build_object('itemId',c.item_id,'placementId',p.id,'chargeId',c.id,
    'paidInvoiceLineId',l.id,'paidAmountMinorUnits',l.signed_amount_minor_units::text,
    'currency',l.currency,'categoryId',l.category_id) order by c.item_id collate "C") into result
  from ledger_private.item_charge_occurrences c
  join public.spike_item_placements p on p.account_id=c.account_id and p.id=c.placement_id and p.item_id=c.item_id
    and p.project_id=c.project_id and p.scope_kind='project' and p.ended_at is null
  join ledger_private.collected_invoice_lines l on l.account_id=c.account_id and l.source_id=c.id
    and l.source_kind='item' and l.item_id=c.item_id and l.signed_amount_minor_units>0
  join ledger_private.collected_invoices i on i.account_id=l.account_id and i.id=l.invoice_id and i.project_id=c.project_id and i.sealed
  join public.spike_projects project on project.account_id=c.account_id and project.id=c.project_id and project.lifecycle='active'
  join public.spike_clients client on client.account_id=project.account_id and client.id=project.client_id and client.lifecycle='active'
  where c.account_id=p_account_id and c.project_id=p_project_id and c.item_id=any(p_item_ids)
    and c.withdrawn_at is null and p.start_evidence='recorded_move'
    and exists(select 1 from public.spike_item_placements predecessor where predecessor.account_id=p.account_id
      and predecessor.item_id=p.item_id and predecessor.scope_kind='business_inventory' and predecessor.ended_at=p.started_at)
    and not exists(select 1 from ledger_private.paid_item_return_credits credit where credit.account_id=c.account_id and credit.charge_id=c.id);
  if coalesce(jsonb_array_length(result),0)<>cardinality(p_item_ids) then
    raise sqlstate '42501' using message='Return selection unavailable';
  end if;
  return jsonb_build_object('accountId',p_account_id,'principalId',actor,'projectId',p_project_id,'items',result);
end;
$$;
revoke all on function ledger_private.read_paid_return_review(text,text,text[]) from public,anon,authenticated,service_role;
grant execute on function ledger_private.read_paid_return_review(text,text,text[]) to authenticated;
create or replace function public.spike_read_paid_return_review(p_account_id text,p_project_id text,p_item_ids text[])
returns jsonb language sql security invoker set search_path='' as $$
  select ledger_private.read_paid_return_review(p_account_id,p_project_id,p_item_ids)
$$;
revoke all on function public.spike_read_paid_return_review(text,text,text[]) from public,anon,authenticated,service_role;
grant execute on function public.spike_read_paid_return_review(text,text,text[]) to authenticated;

do $$ begin
  if exists(select 1 from pg_publication where pubname='powersync') then
    alter publication powersync add table ledger_private.paid_item_return_credits;
  end if;
end $$;
