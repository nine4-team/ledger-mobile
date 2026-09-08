-- Private storage for already-validated frozen contents. This does not create
-- payments, approve source eligibility or authorize a collection command.
alter table public.spike_transactions add constraint spike_transactions_frozen_scope
  unique (account_id, project_id, client_id, id, currency);

create table ledger_private.collected_invoices (
  id text primary key check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id) <= 128),
  account_id text not null,
  project_id text not null,
  client_id text not null,
  purchase_id text not null unique,
  invoice_revision bigint not null check (invoice_revision > 0),
  currency text not null,
  total_minor_units bigint not null check (total_minor_units > 0),
  -- Assembly flag only, never a product Invoice phase. Every committed header
  -- must be sealed; subsequent insertion of even net-zero lines is prohibited.
  sealed boolean not null default false,
  unique (account_id, id, currency),
  -- Actual payment and frozen allocation total are separate facts. O-033 owns
  -- their acceptance policy; this storage primitive cannot decide equality.
  foreign key (account_id, project_id, client_id, purchase_id, currency)
    references public.spike_transactions(account_id, project_id, client_id, id, currency)
);

create table ledger_private.collected_invoice_lines (
  id text primary key check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id) <= 128),
  account_id text not null,
  invoice_id text not null,
  line_position integer not null check (line_position >= 0),
  currency text not null,
  source_kind text not null check (source_kind in ('item', 'expense', 'fee_installment')),
  source_id text not null check (source_id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(source_id) <= 128),
  item_id text,
  source_revision bigint not null check (source_revision > 0),
  category_id text not null check (category_id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(category_id) <= 128),
  signed_amount_minor_units bigint not null,
  description text not null,
  -- Exact typed FrozenInvoiceLine source encoding retained for lossless reload.
  -- Eligibility and referenced occurrence/Expense/Fee existence belong to the
  -- future trusted writer; a JSON object alone is not proof of those facts.
  source_snapshot jsonb not null check (jsonb_typeof(source_snapshot) = 'object'),
  unique (account_id, source_kind, source_id),
  unique (invoice_id, line_position),
  foreign key (account_id, invoice_id, currency)
    references ledger_private.collected_invoices(account_id, id, currency),
  foreign key (account_id, item_id) references public.spike_items(account_id, id),
  check ((source_kind = 'item' and item_id is not null) or (source_kind <> 'item' and item_id is null))
);
create index collected_invoice_lines_invoice_idx on ledger_private.collected_invoice_lines(account_id, invoice_id);
create index collected_invoice_lines_item_idx on ledger_private.collected_invoice_lines(account_id, item_id);

create function ledger_private.guard_collected_invoice() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if tg_table_name = 'collected_invoices' and tg_op = 'UPDATE' then
    if not old.sealed and new.sealed
      and (to_jsonb(old) - 'sealed') = (to_jsonb(new) - 'sealed') then
      return new;
    end if;
  end if;
  raise exception using errcode='55000', message='Frozen Invoice contents are immutable';
end;
$$;
create trigger collected_invoice_immutable before update or delete on ledger_private.collected_invoices
  for each row execute function ledger_private.guard_collected_invoice();
create trigger collected_invoice_no_truncate before truncate on ledger_private.collected_invoices
  for each statement execute function ledger_private.guard_collected_invoice();
create trigger collected_invoice_line_immutable before update or delete on ledger_private.collected_invoice_lines
  for each row execute function ledger_private.guard_collected_invoice();
create trigger collected_invoice_line_no_truncate before truncate on ledger_private.collected_invoice_lines
  for each statement execute function ledger_private.guard_collected_invoice();

create function ledger_private.guard_collected_invoice_line_insert() returns trigger
language plpgsql security invoker set search_path = '' as $$
declare is_sealed boolean;
begin
  select sealed into is_sealed from ledger_private.collected_invoices
    where account_id=new.account_id and id=new.invoice_id for update;
  if not found then
    raise exception using errcode='23503', message='Frozen line requires its exact Invoice';
  end if;
  if is_sealed then
    raise exception using errcode='55000', message='Cannot add lines to a sealed Invoice';
  end if;
  return new;
end;
$$;
create trigger collected_invoice_line_insert before insert on ledger_private.collected_invoice_lines
  for each row execute function ledger_private.guard_collected_invoice_line_insert();

create function ledger_private.assert_collected_invoice_complete(p_invoice_id text) returns void
language plpgsql security invoker set search_path = '' as $$
declare header ledger_private.collected_invoices; line_count bigint; line_total numeric;
begin
  select * into strict header from ledger_private.collected_invoices where id=p_invoice_id;
  select count(*), sum(signed_amount_minor_units::numeric) into line_count,line_total
    from ledger_private.collected_invoice_lines where account_id=header.account_id and invoice_id=header.id;
  if not header.sealed or line_count=0 or line_total is distinct from header.total_minor_units::numeric
    or exists (select 1 from ledger_private.collected_invoice_lines
      where account_id=header.account_id and invoice_id=header.id
      having min(line_position) <> 0 or max(line_position)::bigint + 1 <> count(*))
    or exists (select 1 from ledger_private.collected_invoice_lines
      where account_id=header.account_id and invoice_id=header.id group by category_id
      having sum(signed_amount_minor_units::numeric) not between -9223372036854775808::numeric and 9223372036854775807::numeric) then
    raise exception using errcode='23514', message='Frozen Invoice requires sealed complete exact allocations';
  end if;
end;
$$;
create function ledger_private.validate_collected_invoice_commit() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  perform ledger_private.assert_collected_invoice_complete(new.id);
  return null;
end;
$$;
create constraint trigger collected_invoice_complete after insert or update on ledger_private.collected_invoices
  deferrable initially deferred for each row execute function ledger_private.validate_collected_invoice_commit();

alter table ledger_private.collected_invoices enable row level security;
alter table ledger_private.collected_invoices force row level security;
alter table ledger_private.collected_invoice_lines enable row level security;
alter table ledger_private.collected_invoice_lines force row level security;
revoke all on ledger_private.collected_invoices, ledger_private.collected_invoice_lines
  from public, anon, authenticated, service_role;
revoke all on function ledger_private.guard_collected_invoice(), ledger_private.guard_collected_invoice_line_insert(),
  ledger_private.validate_collected_invoice_commit(), ledger_private.assert_collected_invoice_complete(text)
  from public, anon, authenticated, service_role;

create function ledger_private.read_collected_invoice(p_account_id text, p_invoice_id text) returns jsonb
language plpgsql security invoker set search_path = '' as $$
declare header ledger_private.collected_invoices;
begin
  select * into header from ledger_private.collected_invoices
    where account_id=p_account_id and id=p_invoice_id;
  if not found then
    raise exception using errcode='23503', message='Frozen Invoice requires exact existing Account scope';
  end if;
  if not header.sealed then
    raise exception using errcode='22000', message='Frozen Invoice assembly is not sealed';
  end if;
  return jsonb_build_object('invoice_id',header.id,'invoice_revision',header.invoice_revision::text,
    'account_id',header.account_id,'project_id',header.project_id,'client_id',header.client_id,
    'purchase_id',header.purchase_id,'currency',header.currency,'total_minor_units',header.total_minor_units::text,
    'lines',coalesce((select jsonb_agg(jsonb_build_object(
      'id',id,'line_position',line_position,'source_kind',source_kind,'source_id',source_id,
      'item_id',item_id,'source_revision',source_revision::text,'category_id',category_id,
      'signed_amount_minor_units',signed_amount_minor_units::text,'description',description,
      'source_snapshot_json',source_snapshot::text) order by line_position)
      from ledger_private.collected_invoice_lines where account_id=header.account_id and invoice_id=header.id),'[]'::jsonb));
end;
$$;

-- Store caller-validated source facts only. Does not validate source eligibility,
-- record a payment, or decide O-033 payment/Invoice equality policy.
create function ledger_private.store_collected_invoice(p_record jsonb) returns jsonb
language plpgsql security invoker set search_path = '' as $$
declare
  key text; entry jsonb; ordinal bigint; normalized_lines jsonb := '[]'::jsonb;
  normalized jsonb; source_json jsonb; existing ledger_private.collected_invoices;
begin
  if jsonb_typeof(p_record) is distinct from 'object'
    or (p_record - array['invoice_id','invoice_revision','account_id','project_id','client_id','purchase_id','currency','total_minor_units','lines']) <> '{}'::jsonb
    or jsonb_typeof(p_record->'lines') is distinct from 'array' then
    raise exception using errcode='22023', message='Frozen Invoice record invalid';
  end if;
  foreach key in array array['invoice_id','invoice_revision','account_id','project_id','client_id','purchase_id','currency','total_minor_units'] loop
    if jsonb_typeof(p_record->key) is distinct from 'string' then
      raise exception using errcode='22023', message='Frozen Invoice header value invalid';
    end if;
  end loop;
  foreach key in array array['invoice_revision','total_minor_units'] loop
    if (p_record->>key) !~ '^[1-9][0-9]*$' or (p_record->>key)::bigint::text <> p_record->>key then
      raise exception using errcode='22023', message='Frozen Invoice positive integer invalid';
    end if;
  end loop;
  for entry,ordinal in select value, ordinality from jsonb_array_elements(p_record->'lines') with ordinality loop
    if jsonb_typeof(entry) is distinct from 'object'
      or (entry - array['id','line_position','source_kind','source_id','item_id','source_revision','category_id','signed_amount_minor_units','description','source_snapshot_json']) <> '{}'::jsonb
      or jsonb_typeof(entry->'line_position') is distinct from 'number'
      or (entry->>'line_position') !~ '^(0|[1-9][0-9]*)$'
      or (entry->>'line_position')::integer::bigint <> ordinal-1
      or (entry ? 'item_id' and jsonb_typeof(entry->'item_id') not in ('string','null')) then
      raise exception using errcode='22023', message='Frozen Invoice ordered line invalid';
    end if;
    foreach key in array array['id','source_kind','source_id','source_revision','category_id','signed_amount_minor_units','description','source_snapshot_json'] loop
      if jsonb_typeof(entry->key) is distinct from 'string' then
        raise exception using errcode='22023', message='Frozen Invoice line value invalid';
      end if;
    end loop;
    if (entry->>'source_revision') !~ '^[1-9][0-9]*$'
      or (entry->>'source_revision')::bigint::text <> entry->>'source_revision'
      or (entry->>'signed_amount_minor_units') !~ '^(0|[1-9][0-9]*|-[1-9][0-9]*)$'
      or (entry->>'signed_amount_minor_units')::bigint::text <> entry->>'signed_amount_minor_units' then
      raise exception using errcode='22023', message='Frozen Invoice exact line integer invalid';
    end if;
    source_json := (entry->>'source_snapshot_json')::jsonb;
    if jsonb_typeof(source_json) is distinct from 'object' then
      raise exception using errcode='22023', message='Frozen Invoice source object invalid';
    end if;
    normalized_lines := normalized_lines || jsonb_build_array(entry || jsonb_build_object(
      'item_id',entry->>'item_id','source_snapshot_json',source_json::text));
  end loop;
  normalized := p_record || jsonb_build_object('lines',normalized_lines);
  perform 1 from public.spike_transactions where id=p_record->>'purchase_id'
    and account_id=p_record->>'account_id' and project_id=p_record->>'project_id'
    and client_id=p_record->>'client_id' and currency=p_record->>'currency' and type='purchase' for update;
  if not found then
    raise exception using errcode='23503', message='Frozen Invoice requires its exact existing Purchase scope';
  end if;
  select * into existing from ledger_private.collected_invoices where id=p_record->>'invoice_id' for update;
  if found then
    if existing.account_id <> p_record->>'account_id' or not existing.sealed
      or ledger_private.read_collected_invoice(existing.account_id,existing.id) is distinct from normalized then
      raise exception using errcode='22000', message='Frozen Invoice conflicts with existing contents';
    end if;
    return ledger_private.read_collected_invoice(existing.account_id,existing.id);
  end if;
  insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
    values(p_record->>'invoice_id',p_record->>'account_id',p_record->>'project_id',p_record->>'client_id',
      p_record->>'purchase_id',(p_record->>'invoice_revision')::bigint,p_record->>'currency',(p_record->>'total_minor_units')::bigint);
  for entry in select value from jsonb_array_elements(normalized_lines) loop
    insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,
      source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
    values(entry->>'id',p_record->>'account_id',p_record->>'invoice_id',(entry->>'line_position')::integer,
      p_record->>'currency',entry->>'source_kind',entry->>'source_id',entry->>'item_id',(entry->>'source_revision')::bigint,
      entry->>'category_id',(entry->>'signed_amount_minor_units')::bigint,entry->>'description',(entry->>'source_snapshot_json')::jsonb);
  end loop;
  update ledger_private.collected_invoices set sealed=true where id=p_record->>'invoice_id';
  -- Reuse the commit validator now without changing the caller's constraint mode.
  perform ledger_private.assert_collected_invoice_complete(p_record->>'invoice_id');
  return ledger_private.read_collected_invoice(p_record->>'account_id',p_record->>'invoice_id');
end;
$$;
revoke all on function ledger_private.read_collected_invoice(text,text), ledger_private.store_collected_invoice(jsonb)
  from public, anon, authenticated, service_role;
