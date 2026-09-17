-- Descriptive editing follows the existing operation/result protocol. Financial
-- facts and imported collected-payment locks are deliberately not relaxed.
alter table public.spike_transactions add column details_revision bigint not null default 1
  check (details_revision > 0);
grant select(details_revision) on public.spike_transactions to authenticated;

create function ledger_private.advance_transaction_details_revision()
returns trigger language plpgsql security invoker set search_path='' as $$
begin
  if row(new.source,new.notes,new.payment_method,new.has_email_receipt)
    is distinct from row(old.source,old.notes,old.payment_method,old.has_email_receipt) then
    new.details_revision := old.details_revision + 1;
  elsif new.details_revision is distinct from old.details_revision then
    raise sqlstate '23514' using message='Transaction details revision is server owned';
  end if;
  return new;
end;
$$;
revoke all on function ledger_private.advance_transaction_details_revision() from public,anon,authenticated,service_role;
create trigger transaction_details_revision before update on public.spike_transactions
  for each row execute function ledger_private.advance_transaction_details_revision();

alter table public.spike_operation_results drop constraint spike_operation_results_command_type_check;
alter table public.spike_operation_results add constraint spike_operation_results_command_type_check check
 (command_type in ('create_client','create_project','archive_project','archive_client','revise_space_checklists','manage_categories','sell_inventory_items','create_expense','edit_expense','create_invoice','create_fee_installment','revise_created_invoice','return_uninvoiced_items','edit_uncollected_item_price','edit_item_details','return_paid_items','assign_items_to_space','clear_item_space_assignments','edit_transaction_details'));

create function ledger_private.edit_transaction_details(p_command text)
returns public.spike_operation_results language plpgsql security definer set search_path='' as $$
declare
  c jsonb := p_command::jsonb; changes jsonb := c->'changes';
  account text := c->>'accountId'; actor text := c->>'actorPrincipalId'; operation text := c->>'operationId';
  received timestamptz := clock_timestamp(); result public.spike_operation_results;
  payment public.spike_transactions; category public.spike_budget_categories;
  digest text; failure text;
  required text[] := array['operationId','accountId','actorPrincipalId','contractVersion','createdAtMs',
    'transactionId','scopeKind','projectId','clientId','expectedRevision','changes'];
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise sqlstate '25001' using message='Transaction edits require READ COMMITTED';
  end if;
  if (select auth.uid()) is null or actor is distinct from ledger_private.current_principal_id() then
    raise sqlstate '42501' using message='Authenticated actor required';
  end if;
  perform 1 from public.spike_account_memberships where account_id=account and principal_id=actor
    and state='active' for share;
  if not found then raise sqlstate '42501' using message='Transaction edit access required'; end if;
  if octet_length(p_command)>4194304 or jsonb_typeof(c) is distinct from 'object'
    or not(c ?& required) or c-required<>'{}'
    or c->>'contractVersion' is distinct from 'transaction-details-edit-v1'
    or exists(select 1 from jsonb_each(c-array['changes','projectId','clientId']) where jsonb_typeof(value)<>'string')
    or exists(select 1 from jsonb_each_text(c-array['changes','projectId','clientId','contractVersion','createdAtMs','scopeKind','expectedRevision'])
      where value !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(value)>128)
    or c->>'createdAtMs' !~ '^(0|[1-9][0-9]*)$' or (c->>'createdAtMs')::numeric>=1000000000000000
    or c->>'expectedRevision' !~ '^[1-9][0-9]*$' or (c->>'expectedRevision')::numeric>=9223372036854775807
    or c->>'scopeKind' not in ('project','business_inventory')
    or (c->>'scopeKind'='business_inventory' and (c->'projectId'<>'null' or c->'clientId'<>'null'))
    or (c->>'scopeKind'='project' and (jsonb_typeof(c->'projectId')<>'string' or jsonb_typeof(c->'clientId')<>'string'))
    or exists(select 1 from jsonb_each_text(c) where key in ('projectId','clientId') and value is not null
      and (value !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(value)>128))
    or jsonb_typeof(changes) is distinct from 'object' or changes='{}'
    or changes-array['source','notes','paymentMethod','hasEmailReceipt']<>'{}' then
    raise sqlstate '22023' using message='Invalid Transaction edit command';
  end if;
  if exists(select 1 from jsonb_each(changes) where
    (key in ('source','notes','paymentMethod') and jsonb_typeof(value) not in ('string','null'))
    or (key='hasEmailReceipt' and jsonb_typeof(value)<>'boolean')) then
    raise sqlstate '22023' using message='Invalid Transaction field changes';
  end if;
  digest := encode(extensions.digest(convert_to(p_command,'UTF8'),'sha256'),'hex');
  perform pg_advisory_xact_lock(hashtextextended(operation,0));
  -- Recheck current visibility even for an already-applied retry. Membership and
  -- category locks serialize revocation/reclassification with this operation.
  select * into payment from public.spike_transactions
    where account_id=account and id=c->>'transactionId' for update;
  if not found or row(payment.scope_kind,payment.project_id,payment.client_id)
    is distinct from row(c->>'scopeKind',c->>'projectId',c->>'clientId') then
    raise sqlstate '42501' using message='Transaction edit unavailable';
  end if;
  if payment.origin<>'vendor_payment' then
    raise sqlstate '42501' using message='Transaction edit unavailable';
  end if;
  select * into category from public.spike_budget_categories
    where account_id=account and id=payment.category_id for share;
  if not found or not ledger_private.can_view_budget_category(account,category.visibility_class) then
    raise sqlstate '42501' using message='Transaction edit unavailable';
  end if;
  select * into result from public.spike_operation_results where operation_id=operation;
  if found then
    if row(result.account_id,result.actor_principal_id,result.command_type,result.command_fingerprint)
      is distinct from row(account,actor,'edit_transaction_details',digest) then
      raise sqlstate '23505' using message='Operation identity conflict';
    end if;
    return result;
  end if;
  begin
    if payment.details_revision<>(c->>'expectedRevision')::bigint then
      raise exception 'transaction_edit_stale';
    end if;
    update public.spike_transactions set
      source=case when changes?'source' then changes->>'source' else payment.source end,
      notes=case when changes?'notes' then changes->>'notes' else payment.notes end,
      payment_method=case when changes?'paymentMethod' then changes->>'paymentMethod' else payment.payment_method end,
      has_email_receipt=case when changes?'hasEmailReceipt' then (changes->>'hasEmailReceipt')::boolean else payment.has_email_receipt end
    where account_id=account and id=payment.id;
  exception when raise_exception then failure:=SQLERRM;
    when integrity_constraint_violation or numeric_value_out_of_range then failure:='transaction_edit_integrity_conflict';
  end;
  insert into public.spike_operation_results(operation_id,account_id,actor_principal_id,command_type,contract_version,
    command_fingerprint,envelope_sha256,subject_id,phase,result_code,error_code,client_created_at,server_received_at,
    completed_at,client_created_at_ms,server_received_at_ms,completed_at_ms)
  values(operation,account,actor,'edit_transaction_details','transaction-details-edit-v1',digest,digest,payment.id,
    case when failure is null then 'applied' else 'rejected' end,
    case when failure is null then 'transaction_details_updated' end,failure,
    to_timestamp((c->>'createdAtMs')::numeric/1000),received,received,(c->>'createdAtMs')::bigint,
    floor(extract(epoch from received)*1000)::bigint,floor(extract(epoch from received)*1000)::bigint)
  returning * into result;
  return result;
end;
$$;
-- Internal until native/MCP transport, race and offline integration checks pass.
revoke all on function ledger_private.edit_transaction_details(text) from public,anon,authenticated,service_role;
