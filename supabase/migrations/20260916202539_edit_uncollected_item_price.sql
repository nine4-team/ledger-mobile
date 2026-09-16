-- Internal command first; no API grants until authorization/race tests pass.
alter table public.spike_operation_results drop constraint spike_operation_results_command_type_check;
alter table public.spike_operation_results add constraint spike_operation_results_command_type_check check
 (command_type in ('create_client','create_project','archive_project','archive_client','revise_space_checklists','manage_categories','sell_inventory_items','create_expense','edit_expense','create_invoice','create_fee_installment','revise_created_invoice','return_uninvoiced_items','edit_uncollected_item_price'));

create function ledger_private.edit_uncollected_item_price(p_command text)
returns public.spike_operation_results language plpgsql security definer set search_path='' as $$
declare
  c jsonb:=p_command::jsonb; actor text; account text; operation text; fingerprint text;
  result public.spike_operation_results; received timestamptz:=clock_timestamp(); failure text;
  charge ledger_private.item_charge_occurrences; price ledger_private.item_project_prices;
  invoice_id text; current_invoice text; client text; cost_count bigint; cost bigint; cost_currency text;
  requested bigint; reviewed bigint; price_exists boolean;
  required text[]:=array['operationId','accountId','actorPrincipalId','contractVersion','createdAtMs',
    'projectId','itemId','placementId','occurrenceId','expectedPriceRevision','expectedChargeRevision',
    'requestedPriceMinorUnits','reviewedPriceMinorUnits','currency'];
begin
  if current_setting('transaction_isolation')<>'read committed' then
    raise sqlstate '25001' using message='Item price edits require READ COMMITTED';
  end if;
  actor:=c->>'actorPrincipalId'; account:=c->>'accountId'; operation:=c->>'operationId';
  if (select auth.uid()) is null or actor is distinct from ledger_private.current_principal_id() then
    raise sqlstate '42501' using message='Authenticated actor required';
  end if;
  perform 1 from public.spike_account_memberships where account_id=account and principal_id=actor
    and state='active' and financial_access='full' for share;
  if not found then raise sqlstate '42501' using message='Item price access required'; end if;
  if jsonb_typeof(c) is distinct from 'object' or not(c ?& required) or c-required<>'{}'::jsonb
    or exists(select 1 from jsonb_each(c) where jsonb_typeof(value)<>'string')
    or c->>'contractVersion' is distinct from 'item-uncollected-price-edit-v1'
    or exists(select 1 from jsonb_each_text(c-array['contractVersion','createdAtMs','expectedPriceRevision',
      'expectedChargeRevision','requestedPriceMinorUnits','reviewedPriceMinorUnits','currency'])
      where value !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(value)>128)
    or c->>'currency' !~ '^[A-Z]{3}$'
    or c->>'createdAtMs' !~ '^(0|[1-9][0-9]*)$'
    or (c->>'createdAtMs')::numeric>=1000000000000000
    or c->>'expectedPriceRevision' !~ '^(0|[1-9][0-9]*)$'
    or c->>'expectedChargeRevision' !~ '^[1-9][0-9]*$'
    or (c->>'expectedPriceRevision')::numeric>=9223372036854775807
    or (c->>'expectedChargeRevision')::numeric>=9223372036854775807
    or c->>'requestedPriceMinorUnits' !~ '^(0|[1-9][0-9]*)$'
    or c->>'reviewedPriceMinorUnits' !~ '^[1-9][0-9]*$' then
    raise sqlstate '22023' using message='Invalid Item price command';
  end if;
  requested:=(c->>'requestedPriceMinorUnits')::bigint;
  reviewed:=(c->>'reviewedPriceMinorUnits')::bigint;
  if reviewed<requested then raise sqlstate '22023' using message='Invalid reviewed Item price'; end if;
  fingerprint:=encode(extensions.digest(convert_to(p_command,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(operation,0));
  select * into result from public.spike_operation_results where operation_id=operation;
  if found then
    if row(result.account_id,result.actor_principal_id,result.command_type,result.command_fingerprint)
      is distinct from row(account,actor,'edit_uncollected_item_price',fingerprint) then
      raise sqlstate '23505' using message='Operation identity conflict';
    end if;
    return result;
  end if;
  begin
    select client_id into client from public.spike_projects where account_id=account and id=c->>'projectId'
      and lifecycle='active' for share;
    if not found then raise exception 'price_project_unavailable'; end if;
    perform 1 from public.spike_clients where account_id=account and id=client and lifecycle='active' for share;
    if not found then raise exception 'price_project_unavailable'; end if;
    -- Match Invoice revision's header-before-source lock order. Recheck after
    -- the source lock, since an initially absent membership could have appeared.
    select m.invoice_id into invoice_id from ledger_private.live_invoice_memberships m
      where m.account_id=account and m.source_kind='item' and m.source_id=c->>'occurrenceId' and m.released_at is null;
    if invoice_id is not null then
      perform 1 from ledger_private.live_invoices h where h.account_id=account and h.id=invoice_id
        and h.project_id=c->>'projectId' and h.status in ('created','sent') for update;
      if not found then raise exception 'price_invoice_unavailable'; end if;
    end if;
    perform 1 from public.spike_items where account_id=account and id=c->>'itemId' for update;
    if not found then raise exception 'price_item_unavailable'; end if;
    perform 1 from public.spike_item_placements where account_id=account and item_id=c->>'itemId'
      and id=c->>'placementId' and project_id=c->>'projectId' and scope_kind='project' and ended_at is null for update;
    if not found then raise exception 'price_placement_stale'; end if;
    perform ledger_private.lock_item_charge_source(account,c->>'occurrenceId');
    select m.invoice_id into current_invoice from ledger_private.live_invoice_memberships m
      where m.account_id=account and m.source_kind='item' and m.source_id=c->>'occurrenceId' and m.released_at is null;
    if current_invoice is distinct from invoice_id then raise exception 'price_invoice_changed'; end if;
    select * into charge from ledger_private.item_charge_occurrences where account_id=account and id=c->>'occurrenceId'
      and item_id=c->>'itemId' and placement_id=c->>'placementId' and project_id=c->>'projectId' for update;
    if not found or charge.withdrawn_at is not null then raise exception 'price_charge_unavailable'; end if;
    if charge.revision<>(c->>'expectedChargeRevision')::bigint then raise exception 'price_charge_stale'; end if;
    if exists(select 1 from ledger_private.collected_invoice_lines where account_id=account
      and source_kind='item' and source_id=charge.id) then raise exception 'price_charge_collected'; end if;
    perform r.id from public.transaction_receipt_items r join public.spike_transactions t
      on t.account_id=r.account_id and t.id=r.transaction_id
      where r.account_id=account and r.item_id=charge.item_id and t.type='purchase' for share of r,t;
    select count(*),min(r.amount_minor_units),min(r.currency) into cost_count,cost,cost_currency
      from public.transaction_receipt_items r join public.spike_transactions t on t.account_id=r.account_id and t.id=r.transaction_id
      where r.account_id=account and r.item_id=charge.item_id and t.type='purchase';
    if cost_count>1 then raise exception 'price_acquisition_ambiguous'; end if;
    if charge.currency<>c->>'currency' or (cost_count=1 and cost_currency<>c->>'currency') then
      raise exception 'price_currency_mismatch'; end if;
    if reviewed<>greatest(requested,coalesce(cost,0)) then raise exception 'price_review_stale'; end if;
    select * into price from ledger_private.item_project_prices where account_id=account and item_id=charge.item_id for update;
    price_exists:=found;
    if (price_exists and price.revision::text<>c->>'expectedPriceRevision')
      or (not price_exists and c->>'expectedPriceRevision'<>'0') then raise exception 'price_revision_stale'; end if;
    if price_exists and price.currency<>charge.currency then raise exception 'price_currency_mismatch'; end if;
    if not price_exists then
      insert into ledger_private.item_project_prices(account_id,item_id,amount_minor_units,currency,updated_at,updated_by_principal_id)
        values(account,charge.item_id,reviewed,charge.currency,received,actor);
    elsif price.amount_minor_units<>reviewed then
      update ledger_private.item_project_prices set amount_minor_units=reviewed,revision=revision+1,
        updated_at=received,updated_by_principal_id=actor where account_id=account and item_id=charge.item_id;
    end if;
    if charge.amount_minor_units<>reviewed then
      update ledger_private.item_charge_occurrences set amount_minor_units=reviewed,revision=revision+1
        where account_id=account and id=charge.id;
    end if;
    -- Derived totals stay single-source. Invalid/overflowing Invoice evidence
    -- aborts this subtransaction, including both price and charge writes.
    if invoice_id is not null then
      perform ledger_private.read_live_invoice(account,c->>'projectId',invoice_id);
    end if;
  exception
    when raise_exception then failure:=SQLERRM;
    when integrity_constraint_violation or numeric_value_out_of_range or object_not_in_prerequisite_state then
      failure:='price_integrity_conflict';
  end;
  insert into public.spike_operation_results(operation_id,account_id,actor_principal_id,command_type,contract_version,
    command_fingerprint,envelope_sha256,subject_id,phase,result_code,error_code,client_created_at,server_received_at,
    completed_at,client_created_at_ms,server_received_at_ms,completed_at_ms)
  values(operation,account,actor,'edit_uncollected_item_price','item-uncollected-price-edit-v1',fingerprint,fingerprint,c->>'itemId',
    case when failure is null then 'applied' else 'rejected' end,
    case when failure is null then 'item_price_updated' end,failure,
    to_timestamp((c->>'createdAtMs')::numeric/1000),received,received,(c->>'createdAtMs')::bigint,
    floor(extract(epoch from received)*1000)::bigint,floor(extract(epoch from received)*1000)::bigint)
  returning * into result;
  return result;
end;
$$;
revoke all on function ledger_private.edit_uncollected_item_price(text) from public,anon,authenticated,service_role;
