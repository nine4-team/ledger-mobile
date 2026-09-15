-- Optional historical display fields live on the same immutable Invoice, not
-- a second editable record. Existing nil metadata stays unknown.
create function ledger_private.valid_invoice_display_metadata(value jsonb) returns boolean
language plpgsql immutable security invoker set search_path='' as $$
declare entry record; text_value text;
begin
  if value is null then return true; end if;
  if jsonb_typeof(value)<>'object' or value-array['invoiceNumber','notes','issuedAtMilliseconds',
    'sentAtMilliseconds','paidAtMilliseconds','canceledAtMilliseconds','voidedAtMilliseconds']<>'{}'::jsonb then return false; end if;
  for entry in select key,val from jsonb_each(value) as fields(key,val) loop
    if jsonb_typeof(entry.val)='null' then continue; end if;
    if jsonb_typeof(entry.val)<>'string' then return false; end if;
    if entry.key in ('invoiceNumber','notes') then continue; end if;
    text_value:=entry.val #>> '{}';
    if length(text_value)>16 or text_value !~ '^(0|-?[1-9][0-9]*)$' then return false; end if;
    if text_value::bigint not between -62135596800000 and 253402300799999 then return false; end if;
  end loop;
  return true;
end;
$$;
revoke all on function ledger_private.valid_invoice_display_metadata(jsonb) from public,anon,authenticated,service_role;
alter table ledger_private.collected_invoices add column display_metadata jsonb
  check (ledger_private.valid_invoice_display_metadata(display_metadata));
-- Same existing row-level financial authorization; add only the new read column.
grant select(display_metadata) on ledger_private.collected_invoices to authenticated;

create or replace function ledger_private.read_collected_invoice(p_account_id text,p_invoice_id text) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare header ledger_private.collected_invoices;
begin
  select * into header from ledger_private.collected_invoices where account_id=p_account_id and id=p_invoice_id;
  if not found then raise exception using errcode='23503',message='Frozen Invoice requires exact existing Account scope'; end if;
  if not header.sealed then raise exception using errcode='22000',message='Frozen Invoice assembly is not sealed'; end if;
  return jsonb_build_object('invoice_id',header.id,'invoice_revision',header.invoice_revision::text,
    'account_id',header.account_id,'project_id',header.project_id,'client_id',header.client_id,
    'purchase_id',header.purchase_id,'currency',header.currency,'total_minor_units',header.total_minor_units::text,
    'lines',coalesce((select jsonb_agg(jsonb_build_object(
      'id',id,'line_position',line_position,'source_kind',source_kind,'source_id',source_id,
      'item_id',item_id,'source_revision',source_revision::text,'category_id',category_id,
      'signed_amount_minor_units',signed_amount_minor_units::text,'description',description,
      'source_snapshot_json',source_snapshot::text) order by line_position)
      from ledger_private.collected_invoice_lines where account_id=header.account_id and invoice_id=header.id),'[]'::jsonb))
    || case when header.display_metadata is null then '{}'::jsonb
      else jsonb_build_object('display_metadata',jsonb_strip_nulls(header.display_metadata)) end;
end;
$$;

-- Same storage primitive/authorization and arithmetic as before; normalize only
-- optional metadata nulls and include metadata in the existing exact retry check.
create or replace function ledger_private.store_collected_invoice(p_record jsonb) returns jsonb
language plpgsql security invoker set search_path='' as $$
declare
  key text; entry jsonb; ordinal bigint; normalized_lines jsonb:='[]'::jsonb;
  normalized jsonb; source_json jsonb; metadata jsonb; existing ledger_private.collected_invoices;
begin
  if jsonb_typeof(p_record) is distinct from 'object'
    or p_record-array['invoice_id','invoice_revision','account_id','project_id','client_id','purchase_id','currency','total_minor_units','lines','display_metadata']<>'{}'::jsonb
    or jsonb_typeof(p_record->'lines') is distinct from 'array' then
    raise exception using errcode='22023',message='Frozen Invoice record invalid';
  end if;
  metadata:=nullif(p_record->'display_metadata','null'::jsonb);
  if not ledger_private.valid_invoice_display_metadata(metadata) then
    raise exception using errcode='22023',message='Frozen Invoice display metadata invalid';
  end if;
  metadata:=jsonb_strip_nulls(metadata);
  foreach key in array array['invoice_id','invoice_revision','account_id','project_id','client_id','purchase_id','currency','total_minor_units'] loop
    if jsonb_typeof(p_record->key) is distinct from 'string' then
      raise exception using errcode='22023',message='Frozen Invoice header value invalid';
    end if;
  end loop;
  foreach key in array array['invoice_revision','total_minor_units'] loop
    if p_record->>key !~ '^[1-9][0-9]*$' or (p_record->>key)::bigint::text<>p_record->>key then
      raise exception using errcode='22023',message='Frozen Invoice positive integer invalid';
    end if;
  end loop;
  for entry,ordinal in select value,ordinality from jsonb_array_elements(p_record->'lines') with ordinality loop
    if jsonb_typeof(entry) is distinct from 'object'
      or entry-array['id','line_position','source_kind','source_id','item_id','source_revision','category_id','signed_amount_minor_units','description','source_snapshot_json']<>'{}'::jsonb
      or jsonb_typeof(entry->'line_position') is distinct from 'number'
      or entry->>'line_position' !~ '^(0|[1-9][0-9]*)$'
      or (entry->>'line_position')::integer::bigint<>ordinal-1
      or (entry ? 'item_id' and jsonb_typeof(entry->'item_id') not in ('string','null')) then
      raise exception using errcode='22023',message='Frozen Invoice ordered line invalid';
    end if;
    foreach key in array array['id','source_kind','source_id','source_revision','category_id','signed_amount_minor_units','description','source_snapshot_json'] loop
      if jsonb_typeof(entry->key) is distinct from 'string' then
        raise exception using errcode='22023',message='Frozen Invoice line value invalid';
      end if;
    end loop;
    if entry->>'source_revision' !~ '^[1-9][0-9]*$'
      or (entry->>'source_revision')::bigint::text<>entry->>'source_revision'
      or entry->>'signed_amount_minor_units' !~ '^(0|[1-9][0-9]*|-[1-9][0-9]*)$'
      or (entry->>'signed_amount_minor_units')::bigint::text<>entry->>'signed_amount_minor_units' then
      raise exception using errcode='22023',message='Frozen Invoice exact line integer invalid';
    end if;
    source_json:=(entry->>'source_snapshot_json')::jsonb;
    if jsonb_typeof(source_json) is distinct from 'object' then
      raise exception using errcode='22023',message='Frozen Invoice source object invalid';
    end if;
    normalized_lines:=normalized_lines||jsonb_build_array(entry||jsonb_build_object(
      'item_id',entry->>'item_id','source_snapshot_json',source_json::text));
  end loop;
  normalized:=(p_record-'display_metadata')||jsonb_build_object('lines',normalized_lines)
    || case when metadata is null then '{}'::jsonb else jsonb_build_object('display_metadata',metadata) end;
  perform 1 from public.spike_transactions where id=p_record->>'purchase_id'
    and account_id=p_record->>'account_id' and project_id=p_record->>'project_id'
    and client_id=p_record->>'client_id' and currency=p_record->>'currency' and type='purchase' for update;
  if not found then raise exception using errcode='23503',message='Frozen Invoice requires its exact existing Purchase scope'; end if;
  select * into existing from ledger_private.collected_invoices where id=p_record->>'invoice_id' for update;
  if found then
    if existing.account_id<>p_record->>'account_id' or not existing.sealed
      or ledger_private.read_collected_invoice(existing.account_id,existing.id) is distinct from normalized then
      raise exception using errcode='22000',message='Frozen Invoice conflicts with existing contents';
    end if;
    return ledger_private.read_collected_invoice(existing.account_id,existing.id);
  end if;
  insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units,display_metadata)
    values(p_record->>'invoice_id',p_record->>'account_id',p_record->>'project_id',p_record->>'client_id',
      p_record->>'purchase_id',(p_record->>'invoice_revision')::bigint,p_record->>'currency',(p_record->>'total_minor_units')::bigint,metadata);
  for entry in select value from jsonb_array_elements(normalized_lines) loop
    insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,
      source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
    values(entry->>'id',p_record->>'account_id',p_record->>'invoice_id',(entry->>'line_position')::integer,
      p_record->>'currency',entry->>'source_kind',entry->>'source_id',entry->>'item_id',(entry->>'source_revision')::bigint,
      entry->>'category_id',(entry->>'signed_amount_minor_units')::bigint,entry->>'description',(entry->>'source_snapshot_json')::jsonb);
  end loop;
  update ledger_private.collected_invoices set sealed=true where id=p_record->>'invoice_id';
  perform ledger_private.assert_collected_invoice_complete(p_record->>'invoice_id');
  return ledger_private.read_collected_invoice(p_record->>'account_id',p_record->>'invoice_id');
end;
$$;
-- CREATE OR REPLACE retains the read function's existing authenticated grant
-- and its table RLS boundary. The writer remains operator-only.
revoke all on function ledger_private.store_collected_invoice(jsonb)
  from public,anon,authenticated,service_role;
