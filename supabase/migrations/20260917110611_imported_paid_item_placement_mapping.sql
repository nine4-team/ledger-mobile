-- Operator-only, explicitly reviewed physical-cycle mapping. Never choose a
-- placement from the Item's current location or the nearest timestamp.
alter table ledger_private.item_charge_occurrences
  drop constraint item_charge_occurrences_price_basis_check,
  add constraint item_charge_occurrences_price_basis_check
    check(price_basis in ('project_price','imported_invoice_amount'));

create table ledger_private.imported_invoice_placement_reviews (
  invoice_id text primary key references ledger_private.imported_expense_invoice_sources(invoice_id),
  mappings jsonb not null check(jsonb_typeof(mappings)='array' and jsonb_array_length(mappings)>0),
  reviewed_by text not null references public.spike_principals(id),
  review_bytes bytea not null check(octet_length(review_bytes) between 1 and 4194304)
);
create index imported_invoice_placement_reviews_reviewer_idx
  on ledger_private.imported_invoice_placement_reviews(reviewed_by);
alter table ledger_private.imported_invoice_placement_reviews enable row level security;
alter table ledger_private.imported_invoice_placement_reviews force row level security;
revoke all on ledger_private.imported_invoice_placement_reviews from public,anon,authenticated,service_role;
create trigger imported_invoice_placement_reviews_immutable before update or delete
  on ledger_private.imported_invoice_placement_reviews for each row
  execute function ledger_private.guard_imported_expense_invoice_source();
create trigger imported_invoice_placement_reviews_no_truncate before truncate
  on ledger_private.imported_invoice_placement_reviews for each statement
  execute function ledger_private.guard_imported_expense_invoice_source();

create function ledger_private.import_invoice_sources_with_placements(
  p_invoice jsonb,p_sources jsonb,p_payment jsonb,p_source_account text,
  p_source_invoice text,p_invoice_bytes bytea,p_mappings jsonb,p_reviewer text,p_review_bytes bytea)
returns jsonb language plpgsql volatile security invoker set search_path='' as $$
declare
  retained ledger_private.imported_invoice_placement_reviews;
  mapping jsonb; line jsonb; result jsonb;
begin
  -- Serialize exact retries before inserting sources; the existing source guard
  -- still forbids retroactive attachment behind an already frozen line.
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    jsonb_build_array('ledger-import-invoice-placement',p_invoice->>'invoice_id')::text,0));
  select * into retained from ledger_private.imported_invoice_placement_reviews
    where invoice_id=p_invoice->>'invoice_id';
  if found then
    if row(retained.mappings,retained.reviewed_by,retained.review_bytes)
      is distinct from row(p_mappings,p_reviewer,p_review_bytes) then
      raise exception using errcode='22000',message='Invoice placement review conflicts with retained evidence';
    end if;
    return ledger_private.import_invoice_sources(p_invoice,p_sources,p_payment,p_source_account,p_source_invoice,p_invoice_bytes);
  end if;
  if jsonb_typeof(p_mappings) is distinct from 'array' or jsonb_array_length(p_mappings)=0
    or p_reviewer is null or p_review_bytes is null or octet_length(p_review_bytes) not between 1 and 4194304
    or jsonb_array_length(p_mappings)<>(select count(*) from jsonb_array_elements(p_invoice->'lines') l where l->>'source_kind'='item')
    or (select count(distinct m->>'line_id') from jsonb_array_elements(p_mappings) m)<>jsonb_array_length(p_mappings) then
    raise exception using errcode='22023',message='Every imported Item line requires one explicit placement review';
  end if;
  for mapping in select value from jsonb_array_elements(p_mappings) loop
    select value into line from jsonb_array_elements(p_invoice->'lines')
      where value->>'id'=mapping->>'line_id' and value->>'source_kind'='item';
    if line is null or jsonb_typeof(mapping) is distinct from 'object'
      or mapping-array['line_id','placement_id']<>'{}'::jsonb
      or jsonb_typeof(mapping->'line_id') is distinct from 'string'
      or jsonb_typeof(mapping->'placement_id') is distinct from 'string'
      or not exists(select 1 from public.spike_item_placements p
        where p.id=mapping->>'placement_id' and p.account_id=p_invoice->>'account_id'
          and p.item_id=line->>'item_id' and p.project_id=p_invoice->>'project_id'
          and p.scope_kind='project' and p.start_evidence='recorded_move') then
      raise exception using errcode='22023',message='Reviewed paid line requires its exact evidenced Project placement';
    end if;
    insert into ledger_private.item_charge_occurrences
      (id,account_id,project_id,item_id,placement_id,category_id,amount_minor_units,currency,
       price_basis,revision,created_by_principal_id)
    values(line->>'source_id',p_invoice->>'account_id',p_invoice->>'project_id',line->>'item_id',
      mapping->>'placement_id',line->>'category_id',(line->>'signed_amount_minor_units')::bigint,
      p_invoice->>'currency','imported_invoice_amount',(line->>'source_revision')::bigint,p_reviewer);
  end loop;
  result:=ledger_private.import_invoice_sources(p_invoice,p_sources,p_payment,p_source_account,p_source_invoice,p_invoice_bytes);
  insert into ledger_private.imported_invoice_placement_reviews values
    (p_invoice->>'invoice_id',p_mappings,p_reviewer,p_review_bytes);
  return result;
end;
$$;
revoke all on function ledger_private.import_invoice_sources_with_placements(jsonb,jsonb,jsonb,text,text,bytea,jsonb,text,bytea)
  from public,anon,authenticated,service_role;
