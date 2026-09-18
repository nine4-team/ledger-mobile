-- Shared exact input contract for live vendor-order Item pricing. These helpers
-- are private arithmetic, not new write endpoints or migration price guesses.
create function ledger_private.item_price_fraction(n numeric,d numeric)
returns numeric[] language plpgsql immutable security invoker set search_path='' as $$
declare divisor numeric;
begin
  if d=0 or n<>trunc(n) or d<>trunc(d) or n::text in ('NaN','Infinity','-Infinity')
    or d::text in ('NaN','Infinity','-Infinity') then raise sqlstate '22003'; end if;
  divisor:=gcd(abs(n),abs(d));
  if divisor=0 then divisor:=1; end if;
  n:=div(n,divisor)*sign(d); d:=div(abs(d),divisor);
  if length(abs(n)::text)>38 or length(d::text)>38 then raise sqlstate '22003'; end if;
  return array[n,d];
end;
$$;
revoke all on function ledger_private.item_price_fraction(numeric,numeric) from public,anon,authenticated,service_role;

-- Match the native checked-integer arithmetic envelope before reduction.
create function ledger_private.item_price_product(a numeric,b numeric)
returns numeric language plpgsql immutable set search_path='' as $$
declare result numeric:=a*b;
begin
  if length(abs(result)::text)>38 then raise sqlstate '22003'; end if;
  return result;
end;
$$;
create function ledger_private.item_price_multiply(a numeric[],b numeric[])
returns numeric[] language plpgsql immutable set search_path='' as $$
declare x numeric:=gcd(abs(a[1]),b[2]); y numeric:=gcd(abs(b[1]),a[2]);
begin
  return ledger_private.item_price_fraction(
    ledger_private.item_price_product(div(a[1],x),div(b[1],y)),
    ledger_private.item_price_product(div(a[2],y),div(b[2],x)));
end;
$$;
create function ledger_private.item_price_add(a numeric[],b numeric[])
returns numeric[] language plpgsql immutable set search_path='' as $$
declare common numeric:=gcd(a[2],b[2]); n numeric;
begin
  n:=ledger_private.item_price_product(a[1],div(b[2],common))+ledger_private.item_price_product(b[1],div(a[2],common));
  if length(abs(n)::text)>38 then raise sqlstate '22003'; end if;
  return ledger_private.item_price_fraction(n,ledger_private.item_price_product(a[2],div(b[2],common)));
end;
$$;
create function ledger_private.item_price_round(a numeric[])
returns bigint language sql immutable set search_path='' as $$
 select (sign(a[1])*(div(abs(a[1]),a[2])+case when mod(abs(a[1]),a[2])>=a[2]-mod(abs(a[1]),a[2]) then 1 else 0 end))::bigint;
$$;
revoke all on function ledger_private.item_price_product(numeric,numeric),ledger_private.item_price_multiply(numeric[],numeric[]),
 ledger_private.item_price_add(numeric[],numeric[]),ledger_private.item_price_round(numeric[]) from public,anon,authenticated,service_role;

create function ledger_private.item_price_inverse(requested bigint,total bigint,adjustments bigint)
returns jsonb language plpgsql immutable security invoker set search_path='' as $$
declare base numeric:=total::numeric-adjustments; fraction numeric[];
begin
  if base<=0 then return jsonb_build_object('requestedProjectPriceMinorUnits',requested::text,'issue','nonpositiveBase'); end if;
  if total=0 and requested<>0 then
    return jsonb_build_object('requestedProjectPriceMinorUnits',requested::text,'issue','zeroFactor');
  end if;
  begin
    fraction:=ledger_private.item_price_multiply(array[requested::numeric,1],ledger_private.item_price_fraction(base,case when total=0 then 1 else total end));
    return jsonb_build_object('requestedProjectPriceMinorUnits',requested::text,
      'numerator',fraction[1]::text,'denominator',fraction[2]::text);
  exception when numeric_value_out_of_range then
    return jsonb_build_object('requestedProjectPriceMinorUnits',requested::text,'issue','arithmeticRange');
  end;
end;
$$;
revoke all on function ledger_private.item_price_inverse(bigint,bigint,bigint) from public,anon,authenticated,service_role;

create function ledger_private.calculate_item_adjustments(total bigint,adjustments bigint,inputs jsonb)
returns jsonb language plpgsql immutable security invoker set search_path='' as $$
declare
  base numeric:=total::numeric-adjustments; difference numeric[]:=array[base,1];
  input jsonb; item_value numeric[]; share numeric[]; final_price numeric[]; resolved jsonb;
  rows jsonb:='[]'; unknown boolean:=false; invalid boolean:=false; balanced boolean;
  rounded_share bigint; rounded_final bigint; rounded_unadjusted bigint; issue text;
  share_sum numeric:=0; final_sum numeric:=0; delta numeric; entry record; field text;
begin
  if jsonb_typeof(inputs) is distinct from 'array'
    or exists(select 1 from jsonb_array_elements(inputs) x group by x->>'itemId' having count(*)>1) then
    raise sqlstate '22023' using message='Distinct Item inputs required';
  end if;
  for input in select * from jsonb_array_elements(inputs) loop
    resolved:=input; issue:=null; item_value:=null; share:=null; final_price:=null;
    rounded_share:=null; rounded_final:=null; rounded_unadjusted:=null;
    if input->>'numerator' is null and input->>'requestedProjectPriceMinorUnits' is not null then
      resolved:=input||ledger_private.item_price_inverse((input->>'requestedProjectPriceMinorUnits')::bigint,total,adjustments);
    end if;
    begin
      if resolved->>'numerator' is null or resolved->>'denominator' is null then
        unknown:=true; issue:=coalesce(resolved->>'issue','unknownInput');
      else
        item_value:=ledger_private.item_price_fraction((resolved->>'numerator')::numeric,(resolved->>'denominator')::numeric);
        begin
          difference:=ledger_private.item_price_add(difference,array[-item_value[1],item_value[2]]);
        exception when numeric_value_out_of_range then unknown:=true;
        end;
        rounded_unadjusted:=ledger_private.item_price_round(item_value);
      end if;
      if base<=0 then issue:='nonpositiveBase';
      elsif item_value is not null then
        share:=ledger_private.item_price_multiply(item_value,ledger_private.item_price_fraction(adjustments,base));
        final_price:=ledger_private.item_price_multiply(item_value,ledger_private.item_price_fraction(total,base));
        rounded_share:=ledger_private.item_price_round(share);
        rounded_final:=ledger_private.item_price_round(final_price);
      end if;
    exception when numeric_value_out_of_range or division_by_zero then
      issue:='arithmeticRange'; unknown:=true; rounded_share:=null; rounded_final:=null;
    end;
    if issue is not null then invalid:=true; end if;
    share_sum:=share_sum+coalesce(rounded_share,0); final_sum:=final_sum+coalesce(rounded_final,0);
    rows:=rows||jsonb_build_array(jsonb_build_object('itemId',input->>'itemId',
      'numerator',resolved->>'numerator','denominator',resolved->>'denominator',
      'requestedProjectPriceMinorUnits',resolved->>'requestedProjectPriceMinorUnits',
      'unadjustedMinorUnits',rounded_unadjusted::text,'adjustmentsMinorUnits',rounded_share::text,
      'projectPriceMinorUnits',rounded_final::text,'issue',issue,
      -- Denominators are at most38 digits; 80 fractional digits preserve
      -- ordering of every distinct residual without approximate ties.
      'shareResidual',case when share is not null then ((share[1]-rounded_share::numeric*share[2])::numeric(120,80)/share[2])::text end,
      'finalResidual',case when final_price is not null then ((final_price[1]-rounded_final::numeric*final_price[2])::numeric(120,80)/final_price[2])::text end));
  end loop;
  balanced:=not unknown and difference[1]=0;
  if balanced and not invalid then
    foreach field in array array['adjustmentsMinorUnits','projectPriceMinorUnits'] loop
      delta:=case when field='adjustmentsMinorUnits' then adjustments-share_sum else total-final_sum end;
      for entry in
        select ordinality-1 as position from jsonb_array_elements(rows) with ordinality
        order by (case when field='adjustmentsMinorUnits' then value->>'shareResidual' else value->>'finalResidual' end)::numeric
          *case when delta>0 then -1 else 1 end,
          (value->>'itemId') collate "C"
        limit abs(delta)::bigint
      loop
        rows:=jsonb_set(rows,array[entry.position::text,field],
          to_jsonb(((rows->entry.position::int->>field)::bigint+sign(delta)::bigint)::text));
      end loop;
    end loop;
  end if;
  -- Displayed cents reconcile per Item as well as across the order. Retain
  -- the exact numerator/denominator as the next calculation's original input.
  for entry in select value,ordinality-1 as position from jsonb_array_elements(rows) with ordinality loop
    if entry.value->>'issue' is null then
      begin
        rounded_unadjusted:=((entry.value->>'projectPriceMinorUnits')::numeric-(entry.value->>'adjustmentsMinorUnits')::numeric)::bigint;
        rows:=jsonb_set(rows,array[entry.position::text,'unadjustedMinorUnits'],to_jsonb(rounded_unadjusted::text));
      exception when numeric_value_out_of_range then
        unknown:=true; balanced:=false;
        rows:=jsonb_set(rows,array[entry.position::text],entry.value||jsonb_build_object(
          'issue','arithmeticRange','projectPriceMinorUnits',null,'adjustmentsMinorUnits',null));
      end;
    end if;
  end loop;
  select coalesce(jsonb_agg(value-array['shareResidual','finalResidual'] order by ordinality),'[]')
    into rows from jsonb_array_elements(rows) with ordinality;
  return jsonb_build_object('totalMinorUnits',total::text,'adjustmentsMinorUnits',adjustments::text,
    'differenceNumerator',case when not unknown then difference[1]::text end,
    'differenceDenominator',case when not unknown then difference[2]::text end,
    'isBalanced',balanced,'isProvisional',not balanced,'items',rows);
end;
$$;
revoke all on function ledger_private.calculate_item_adjustments(bigint,bigint,jsonb) from public,anon,authenticated,service_role;

-- Explicit inputs are separate from historical acquisition amounts. Existing
-- prices are not backfilled: their adjustment inclusion is unknown.
alter table public.spike_transactions drop constraint spike_transactions_amount_minor_units_check;
alter table public.spike_transactions add constraint spike_transactions_amount_minor_units_check
  check(amount_minor_units>0 or (origin='vendor_payment' and type='purchase' and amount_minor_units=0));
create table ledger_private.item_adjustment_inputs (
  account_id text not null,
  item_id text not null,
  transaction_id text not null,
  input jsonb not null,
  revision bigint not null default 1 check(revision>0),
  updated_at timestamptz not null default now(),
  updated_by_principal_id text not null references public.spike_principals(id),
  primary key(account_id,transaction_id,item_id),
  foreign key(account_id,item_id) references public.spike_items(account_id,id),
  foreign key(account_id,transaction_id) references public.spike_transactions(account_id,id)
);
alter table ledger_private.item_adjustment_inputs enable row level security;
alter table ledger_private.item_adjustment_inputs force row level security;
revoke all on ledger_private.item_adjustment_inputs from public,anon,authenticated,service_role;

-- One row is one coherent order calculation, including unknown inputs. A
-- subscriber never reconstructs a new order from separately arriving prices.
create table ledger_private.item_adjustment_orders (
  id text primary key,
  account_id text not null,
  revision bigint not null default 1 check(revision>0),
  snapshot jsonb not null,
  foreign key(account_id,id) references public.spike_transactions(account_id,id)
);
alter table ledger_private.item_adjustment_orders enable row level security;
alter table ledger_private.item_adjustment_orders force row level security;
revoke all on ledger_private.item_adjustment_orders from public,anon,authenticated,service_role;
alter table ledger_private.item_acquisition_reviews add column live_pricing jsonb;

create function ledger_private.item_live_adjustment_transaction(p_account text,p_item text)
returns text language sql stable security invoker set search_path='' as $$
 select case when count(*)=1 then min(r.transaction_id) end
 from public.transaction_receipt_items r join public.spike_transactions t
 on t.account_id=r.account_id and t.id=r.transaction_id
 where r.account_id=p_account and r.item_id=p_item and r.membership_kind='linked'
   and t.origin='vendor_payment' and t.type='purchase'
$$;
revoke all on function ledger_private.item_live_adjustment_transaction(text,text) from public,anon,authenticated,service_role;

-- A zero current charge is an amount. A calculation issue is unknown. Frozen
-- Invoice rows retain their existing constraints and immutable snapshots.
alter table ledger_private.item_charge_occurrences
  add column adjustment_transaction_id text,
  add column adjustment_revision bigint,
  alter column amount_minor_units drop not null,
  drop constraint item_charge_occurrences_amount_minor_units_check,
  add constraint item_charge_occurrences_amount_minor_units_check check(
    coalesce(amount_minor_units>0,false) or (adjustment_transaction_id is not null
      and adjustment_revision is not null and adjustment_revision>0
      and (amount_minor_units is null or amount_minor_units>=0))),
  add constraint item_charge_adjustment_transaction_fk foreign key(account_id,adjustment_transaction_id)
    references public.spike_transactions(account_id,id);

create function ledger_private.refresh_item_adjustments(p_account text,p_transaction text)
returns void language plpgsql security definer set search_path='' as $$
declare
  t public.spike_transactions; adjustments bigint; inputs jsonb; calculation jsonb;
  order_revision bigint; entry jsonb; item_row record; invoice_row record;
  input_row ledger_private.item_adjustment_inputs; old_price ledger_private.item_project_prices;
  derived bigint; actor text; current_price_revision bigint;
begin
  select * into t from public.spike_transactions where account_id=p_account and id=p_transaction
    and origin='vendor_payment' and type='purchase' for update;
  if not found then return; end if;
  select coalesce(sum((line->>'amountMinorUnits')::numeric*case when line->>'effect'='increase' then 1 else -1 end),0)::bigint
    into adjustments from jsonb_array_elements(t.non_item_receipt_lines) line;
  select coalesce(jsonb_agg(jsonb_build_object('itemId',r.item_id)||coalesce(i.input,'{}') order by r.item_id),'[]')
    into inputs from public.transaction_receipt_items r
    left join ledger_private.item_adjustment_inputs i on i.account_id=r.account_id and i.item_id=r.item_id
      and i.transaction_id=r.transaction_id
    where r.account_id=p_account and r.transaction_id=p_transaction;
  calculation:=ledger_private.calculate_item_adjustments(t.amount_minor_units,adjustments,inputs);
  insert into ledger_private.item_adjustment_orders(id,account_id,snapshot)
    values(p_transaction,p_account,calculation)
    on conflict(id) do update set revision=item_adjustment_orders.revision+1,snapshot=excluded.snapshot
    returning revision into order_revision;
  -- Invoice header before source locks matches the existing price edit path.
  for invoice_row in select distinct h.id from ledger_private.live_invoices h
    join ledger_private.live_invoice_memberships m on m.account_id=h.account_id and m.invoice_id=h.id and m.released_at is null
    join ledger_private.item_charge_occurrences c on c.account_id=m.account_id and c.id=m.source_id and m.source_kind='item'
    join public.transaction_receipt_items r on r.account_id=c.account_id and r.item_id=c.item_id
    where r.account_id=p_account and r.transaction_id=p_transaction and h.status in ('created','sent') order by h.id
  loop
    perform 1 from ledger_private.live_invoices where account_id=p_account and id=invoice_row.id for update;
  end loop;
  for entry in select * from jsonb_array_elements(calculation->'items') loop
    if ledger_private.item_live_adjustment_transaction(p_account,entry->>'itemId') is distinct from p_transaction then
      continue;
    end if;
    perform 1 from public.spike_items where account_id=p_account and id=entry->>'itemId' for update;
    select * into input_row from ledger_private.item_adjustment_inputs
      where account_id=p_account and item_id=entry->>'itemId' and transaction_id=p_transaction;
    -- Only explicit current inputs may change a current price; acquisition and
    -- legacy values are retained until their basis is explicitly established.
    if found then
      if input_row.input->>'numerator' is null and entry->>'numerator' is not null then
        update ledger_private.item_adjustment_inputs set input=(input-'issue')||jsonb_build_object(
          'numerator',entry->>'numerator','denominator',entry->>'denominator'),revision=revision+1
          where account_id=p_account and item_id=entry->>'itemId' and transaction_id=p_transaction;
      end if;
      actor:=input_row.updated_by_principal_id;
      derived:=(entry->>'projectPriceMinorUnits')::bigint;
      select * into old_price from ledger_private.item_project_prices
        where account_id=p_account and item_id=entry->>'itemId' for update;
      if found then
        if old_price.currency<>t.currency then raise exception 'price_currency_mismatch'; end if;
        update ledger_private.item_project_prices set amount_minor_units=derived,revision=revision+1,
          updated_at=greatest(clock_timestamp(),updated_at),updated_by_principal_id=actor
          where account_id=p_account and item_id=entry->>'itemId' returning revision into current_price_revision;
      else
        insert into ledger_private.item_project_prices(account_id,item_id,amount_minor_units,currency,updated_at,updated_by_principal_id)
          values(p_account,entry->>'itemId',derived,t.currency,clock_timestamp(),actor)
          returning revision into current_price_revision;
      end if;
      for item_row in select c.id from ledger_private.item_charge_occurrences c
        where c.account_id=p_account and c.item_id=entry->>'itemId' and c.withdrawn_at is null
          and not exists(select 1 from ledger_private.collected_invoice_lines paid
            where paid.account_id=c.account_id and paid.source_kind='item' and paid.source_id=c.id)
        order by c.id
      loop
        perform ledger_private.lock_item_charge_source(p_account,item_row.id);
        if exists(select 1 from ledger_private.item_charge_occurrences where account_id=p_account and id=item_row.id and currency<>t.currency) then
          raise exception 'price_currency_mismatch';
        end if;
        update ledger_private.item_charge_occurrences c set amount_minor_units=derived,revision=revision+1,
          adjustment_transaction_id=p_transaction,adjustment_revision=order_revision
          where account_id=p_account and id=item_row.id
            and not exists(select 1 from ledger_private.collected_invoice_lines paid
              where paid.account_id=c.account_id and paid.source_kind='item' and paid.source_id=c.id);
      end loop;
    else
      select revision into current_price_revision from ledger_private.item_project_prices
        where account_id=p_account and item_id=entry->>'itemId';
    end if;
    update ledger_private.item_acquisition_reviews set live_pricing=jsonb_build_object(
      'transactionId',p_transaction,'revision',order_revision::text,'priceRevision',coalesce(current_price_revision,0)::text,
      'totalMinorUnits',t.amount_minor_units::text,'adjustmentsMinorUnits',adjustments::text,'currency',t.currency,
      'isProvisional',calculation->'isProvisional','price',entry)
      where account_id=p_account and id=entry->>'itemId';
  end loop;
end;
$$;
revoke all on function ledger_private.refresh_item_adjustments(text,text) from public,anon,authenticated,service_role;

create function ledger_private.edit_live_item_price(p_command text)
returns public.spike_operation_results language plpgsql security definer set search_path='' as $$
declare
  c jsonb:=p_command::jsonb; account text:=c->>'accountId'; actor text:=c->>'actorPrincipalId';
  operation text:=c->>'operationId'; fingerprint text; result public.spike_operation_results;
  received timestamptz:=clock_timestamp(); failure text; t public.spike_transactions;
  order_row ledger_private.item_adjustment_orders; input jsonb; current_revision bigint;
  required text[]:=array['operationId','accountId','actorPrincipalId','contractVersion','createdAtMs',
    'itemId','placementId','transactionId','expectedAdjustmentRevision','expectedPriceRevision',
    'requestedPriceMinorUnits','reviewedPriceMinorUnits','currency'];
begin
  if current_setting('transaction_isolation')<>'read committed' then raise sqlstate '25001'; end if;
  if (select auth.uid()) is null or actor is distinct from ledger_private.current_principal_id() then
    raise sqlstate '42501' using message='Authenticated actor required';
  end if;
  perform 1 from public.spike_account_memberships where account_id=account and principal_id=actor
    and state='active' and financial_access='full' for share;
  if not found then raise sqlstate '42501' using message='Item price access required'; end if;
  if jsonb_typeof(c) is distinct from 'object' or not(c ?& required)
    or c-(required||array['projectId','occurrenceId','expectedChargeRevision','clearPrice'])<>'{}'
    or exists(select 1 from jsonb_each(c) where jsonb_typeof(value)<>'string')
    or c->>'contractVersion' is distinct from 'item-live-adjustment-price-edit-v3'
    or c->>'currency' !~ '^[A-Z]{3}$'
    or c->>'createdAtMs' !~ '^(0|[1-9][0-9]*)$' or (c->>'createdAtMs')::numeric>=1000000000000000
    or c->>'expectedPriceRevision' !~ '^(0|[1-9][0-9]*)$'
    or c->>'expectedAdjustmentRevision' !~ '^[1-9][0-9]*$'
    or c->>'requestedPriceMinorUnits' !~ '^(0|[1-9][0-9]*)$'
    or c->>'reviewedPriceMinorUnits' is distinct from c->>'requestedPriceMinorUnits'
    or (c->>'requestedPriceMinorUnits')::numeric>9223372036854775807
    or (c->>'expectedPriceRevision')::numeric>=9223372036854775807
    or (c->>'expectedAdjustmentRevision')::numeric>=9223372036854775807
    or exists(select 1 from jsonb_each_text(c-array['contractVersion','createdAtMs','expectedPriceRevision',
      'expectedAdjustmentRevision','expectedChargeRevision','requestedPriceMinorUnits','reviewedPriceMinorUnits','currency','clearPrice'])
      where value !~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' or octet_length(value)>128)
    or (c ? 'projectId' and (not(c ?& array['occurrenceId','expectedChargeRevision']) or c ? 'clearPrice'))
    or (not(c ? 'projectId') and (not(c ? 'clearPrice') or c->>'clearPrice' not in ('true','false') or c ? 'occurrenceId' or c ? 'expectedChargeRevision'))
    or (c->>'clearPrice'='true' and c->>'requestedPriceMinorUnits'<>'0') then
    raise sqlstate '22023' using message='Invalid live Item price command';
  end if;
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
    select * into t from public.spike_transactions where account_id=account and id=c->>'transactionId' for update;
    if not found or ledger_private.item_live_adjustment_transaction(account,c->>'itemId') is distinct from t.id then
      raise exception 'price_acquisition_ambiguous';
    end if;
    select * into order_row from ledger_private.item_adjustment_orders where account_id=account and id=t.id for update;
    if not found or order_row.revision::text<>c->>'expectedAdjustmentRevision' then raise exception 'price_revision_stale'; end if;
    if t.currency<>c->>'currency' then raise exception 'price_currency_mismatch'; end if;
    perform 1 from public.spike_item_placements where account_id=account and item_id=c->>'itemId'
      and id=c->>'placementId' and ended_at is null
      and ((c ? 'projectId' and project_id=c->>'projectId' and scope_kind='project')
        or (not(c ? 'projectId') and scope_kind='business_inventory')) for update;
    if not found then raise exception 'price_placement_stale'; end if;
    if c ? 'projectId' then
      perform 1 from public.spike_projects p join public.spike_clients client
        on client.account_id=p.account_id and client.id=p.client_id
        where p.account_id=account and p.id=c->>'projectId' and p.lifecycle='active' and client.lifecycle='active' for share of p,client;
      if not found then raise exception 'price_project_unavailable'; end if;
      perform 1 from ledger_private.item_charge_occurrences where account_id=account and id=c->>'occurrenceId'
        and item_id=c->>'itemId' and placement_id=c->>'placementId' and project_id=c->>'projectId'
        and withdrawn_at is null and revision::text=c->>'expectedChargeRevision';
      if not found then raise exception 'price_charge_stale'; end if;
    end if;
    select revision into current_revision from ledger_private.item_project_prices
      where account_id=account and item_id=c->>'itemId';
    -- The locked unique current order serializes input edits. Refresh takes
    -- shared Invoice headers before price/source rows across all affected Items.
    if coalesce(current_revision,0)::text<>c->>'expectedPriceRevision' then raise exception 'price_revision_stale'; end if;
    input:=case when c->>'clearPrice'='true' then jsonb_build_object('issue','unknownInput') else
      ledger_private.item_price_inverse((c->>'requestedPriceMinorUnits')::bigint,t.amount_minor_units,
        (order_row.snapshot->>'adjustmentsMinorUnits')::bigint) end;
    insert into ledger_private.item_adjustment_inputs(account_id,item_id,transaction_id,input,updated_by_principal_id)
      values(account,c->>'itemId',t.id,input,actor)
      on conflict(account_id,transaction_id,item_id) do update set input=excluded.input,
        revision=item_adjustment_inputs.revision+1,updated_at=clock_timestamp(),updated_by_principal_id=actor;
    perform ledger_private.refresh_item_adjustments(account,t.id);
  exception when raise_exception then failure:=SQLERRM;
    when integrity_constraint_violation or numeric_value_out_of_range or object_not_in_prerequisite_state then failure:='price_integrity_conflict';
  end;
  insert into public.spike_operation_results(operation_id,account_id,actor_principal_id,command_type,contract_version,
    command_fingerprint,envelope_sha256,subject_id,phase,result_code,error_code,client_created_at,server_received_at,
    completed_at,client_created_at_ms,server_received_at_ms,completed_at_ms)
  values(operation,account,actor,'edit_uncollected_item_price','item-live-adjustment-price-edit-v3',fingerprint,fingerprint,c->>'itemId',
    case when failure is null then 'applied' else 'rejected' end,case when failure is null then 'item_price_updated' end,failure,
    to_timestamp((c->>'createdAtMs')::numeric/1000),received,received,(c->>'createdAtMs')::bigint,
    floor(extract(epoch from received)*1000)::bigint,floor(extract(epoch from received)*1000)::bigint)
  returning * into result;
  return result;
end;
$$;
revoke all on function ledger_private.edit_live_item_price(text) from public,anon,authenticated,service_role;

create function ledger_private.item_adjustments_changed() returns trigger
language plpgsql security definer set search_path='' as $$
declare current_order text;
begin
  if tg_table_name='spike_transactions' then
    perform ledger_private.refresh_item_adjustments(new.account_id,new.id);
  else
    if tg_op<>'INSERT' then
      update ledger_private.item_acquisition_reviews set live_pricing=null
        where account_id=old.account_id and id=old.item_id and live_pricing->>'transactionId'=old.transaction_id;
      perform ledger_private.refresh_item_adjustments(old.account_id,old.transaction_id);
    end if;
    if tg_op<>'DELETE' then
      update ledger_private.item_acquisition_reviews set live_pricing=null where account_id=new.account_id and id=new.item_id;
      perform ledger_private.refresh_item_adjustments(new.account_id,new.transaction_id);
      current_order:=ledger_private.item_live_adjustment_transaction(new.account_id,new.item_id);
      if current_order is not null and current_order<>new.transaction_id then
        perform ledger_private.refresh_item_adjustments(new.account_id,current_order);
      end if;
    else
      current_order:=ledger_private.item_live_adjustment_transaction(old.account_id,old.item_id);
      if current_order is not null and current_order<>old.transaction_id then
        perform ledger_private.refresh_item_adjustments(old.account_id,current_order);
      end if;
    end if;
  end if;
  return null;
end;
$$;
revoke all on function ledger_private.item_adjustments_changed() from public,anon,authenticated,service_role;
create trigger item_adjustments_receipt_insert after insert or delete on public.transaction_receipt_items
  for each row execute function ledger_private.item_adjustments_changed();
create trigger item_adjustments_receipt_update after update on public.transaction_receipt_items
  for each row when (row(old.account_id,old.transaction_id,old.item_id,old.membership_kind)
    is distinct from row(new.account_id,new.transaction_id,new.item_id,new.membership_kind))
  execute function ledger_private.item_adjustments_changed();
create trigger item_adjustments_order_update after update on public.spike_transactions
  for each row when (row(old.amount_minor_units,old.non_item_receipt_lines)
    is distinct from row(new.amount_minor_units,new.non_item_receipt_lines))
  execute function ledger_private.item_adjustments_changed();

do $$ declare t record; begin
  for t in select distinct account_id,transaction_id from public.transaction_receipt_items order by transaction_id loop
    perform ledger_private.refresh_item_adjustments(t.account_id,t.transaction_id);
  end loop;
end $$;

alter function ledger_private.read_item_price_edit(text,text,text) rename to read_item_price_edit_without_adjustments;
create function ledger_private.read_item_price_edit(p_account_id text,p_project_id text,p_item_id text)
returns jsonb language plpgsql stable security definer set search_path='' as $$
declare actor text:=ledger_private.current_principal_id(); context jsonb;
  placement public.spike_item_placements; charge ledger_private.item_charge_occurrences;
  acquisition ledger_private.item_acquisition_reviews; n bigint;
begin
  if (select auth.uid()) is null or not exists(select 1 from public.spike_account_memberships
    where account_id=p_account_id and principal_id=actor and state='active' and financial_access='full') then
    raise sqlstate '42501' using message='Item price access required';
  end if;
  select * into acquisition from ledger_private.item_acquisition_reviews where account_id=p_account_id and id=p_item_id;
  context:=acquisition.live_pricing;
  if context is null then return ledger_private.read_item_price_edit_without_adjustments(p_account_id,p_project_id,p_item_id); end if;
  select * into placement from public.spike_item_placements where account_id=p_account_id and item_id=p_item_id
    and ended_at is null and ((p_project_id is null and scope_kind='business_inventory')
      or (project_id=p_project_id and scope_kind='project'));
  if not found then raise sqlstate '22023' using message='Item price review unavailable'; end if;
  if p_project_id is not null then
    if not exists(select 1 from public.spike_projects p join public.spike_clients c on c.account_id=p.account_id and c.id=p.client_id
      where p.account_id=p_account_id and p.id=p_project_id and p.lifecycle='active' and c.lifecycle='active') then
      raise sqlstate '22023' using message='Item price review unavailable';
    end if;
    select count(*) into n from ledger_private.item_charge_occurrences where account_id=p_account_id and item_id=p_item_id
      and placement_id=placement.id and project_id=p_project_id and withdrawn_at is null;
    if n<>1 then raise sqlstate '22023' using message='Item price review unavailable'; end if;
    select * into charge from ledger_private.item_charge_occurrences where account_id=p_account_id and item_id=p_item_id
      and placement_id=placement.id and project_id=p_project_id and withdrawn_at is null;
  end if;
  return jsonb_build_object('accountId',p_account_id,'principalId',actor,'projectId',p_project_id,'itemId',p_item_id,
    'placementId',placement.id,'occurrenceId',charge.id,'chargeRevision',charge.revision::text,
    'priceRevision',context->>'priceRevision','currency',context->>'currency',
    'currentPrice',case when context->'price'->>'projectPriceMinorUnits' is not null then
      jsonb_build_object('amountMinorUnits',context->'price'->>'projectPriceMinorUnits','currency',context->>'currency') end,
    'purchaseCost',case when acquisition.state='known' then jsonb_build_object('state','known',
      'amountMinorUnits',acquisition.amount_minor_units::text,'currency',acquisition.currency)
      else jsonb_build_object('state',acquisition.state) end,'livePricing',context);
end;
$$;
revoke all on function ledger_private.read_item_price_edit(text,text,text) from public,anon,authenticated,service_role;
grant execute on function ledger_private.read_item_price_edit(text,text,text) to authenticated;
grant execute on function ledger_private.edit_live_item_price(text) to authenticated;
create or replace function public.spike_edit_uncollected_item_price(p_command text)
returns public.spike_operation_results language sql security invoker set search_path='' as $$
 select case p_command::jsonb->>'contractVersion'
   when 'item-live-adjustment-price-edit-v3' then ledger_private.edit_live_item_price(p_command)
   when 'item-inventory-price-edit-v2' then ledger_private.edit_inventory_item_price(p_command)
   else ledger_private.edit_uncollected_item_price(p_command) end;
$$;

create policy item_adjustment_order_read on ledger_private.item_adjustment_orders
for select to authenticated using (exists(select 1 from public.spike_transactions t
  where t.account_id=item_adjustment_orders.account_id and t.id=item_adjustment_orders.id and t.origin='vendor_payment'));
grant select on ledger_private.item_adjustment_orders to authenticated;
do $migration$
declare definition text; needle text:='''nonItemReceiptLines'', t.non_item_receipt_lines,';
begin
  perform set_config('search_path','',true);
  definition:=pg_get_viewdef('ledger_private.transaction_receipt_display'::regclass,true);
  if (length(definition)-length(replace(definition,needle,'')))/length(needle)<>1 then
    raise exception 'Unexpected receipt display definition';
  end if;
  execute 'create or replace view ledger_private.transaction_receipt_display with (security_invoker=true) as '
    ||replace(definition,needle,needle||' ''requiresLiveAdjustments'',t.type=''purchase'',
    ''liveAdjustments'',(select snapshot from ledger_private.item_adjustment_orders a where a.account_id=t.account_id and a.id=t.id),');
end;
$migration$;

-- Accepted v1/v2 operations keep their identity and terminal result, but an
-- unapplied legacy price edit must not bypass the new revision-bound input path.
do $legacy_price_guard$
declare change record; definition text;
begin
  for change in select * from (values
    ('ledger_private.edit_uncollected_item_price(text)', E'  begin\n    select client_id'),
    ('ledger_private.edit_inventory_item_price(text)', E' begin\n   -- Same Item-before-placement/price lock order as Inventory sale.')
  ) as changes(signature,needle) loop
    definition:=pg_get_functiondef(change.signature::regprocedure);
    if (length(definition)-length(replace(definition,change.needle,'')))/length(change.needle)<>1 then
      raise exception 'Unexpected legacy Item price definition: %',change.signature;
    end if;
    execute replace(definition,change.needle,
      replace(change.needle,'begin',E'begin\n    if ledger_private.item_live_adjustment_transaction(account,c->>''itemId'') is not null then\n      raise exception ''price_review_stale'';\n    end if;'));
  end loop;
end;
$legacy_price_guard$;
