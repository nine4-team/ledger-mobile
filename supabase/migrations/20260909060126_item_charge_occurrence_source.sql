-- Canonical positive project-price charge facts. This is not the Link command:
-- its acquisition evidence (O-016), role grants and source validation remain
-- required. No Purchase, Invoice, payment or acquisition is invented here.
create table ledger_private.item_charge_occurrences (
  id text primary key check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id)<=128),
  account_id text not null,
  project_id text not null,
  item_id text not null,
  placement_id text not null,
  category_id text not null,
  amount_minor_units bigint not null check (amount_minor_units>0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  price_basis text not null default 'project_price' check (price_basis='project_price'),
  revision bigint not null default 1 check (revision>0),
  created_at timestamptz not null default statement_timestamp() check (isfinite(created_at)),
  created_by_principal_id text not null references public.spike_principals(id),
  withdrawn_at timestamptz,
  withdrawn_by_principal_id text references public.spike_principals(id),
  unique (account_id,id),
  foreign key (account_id,placement_id,item_id,project_id)
    references public.spike_item_placements(account_id,id,item_id,project_id),
  foreign key (account_id,category_id) references public.spike_budget_categories(account_id,id),
  check ((withdrawn_at is null and withdrawn_by_principal_id is null)
    or (withdrawn_at is not null and withdrawn_by_principal_id is not null
      and isfinite(withdrawn_at) and withdrawn_at>=created_at))
);
create unique index item_charge_occurrences_open_placement_idx
  on ledger_private.item_charge_occurrences(account_id,placement_id) where withdrawn_at is null;
create index item_charge_occurrences_placement_idx
  on ledger_private.item_charge_occurrences(account_id,placement_id,item_id,project_id);
create index item_charge_occurrences_project_idx on ledger_private.item_charge_occurrences(account_id,project_id);
create index item_charge_occurrences_category_idx on ledger_private.item_charge_occurrences(account_id,category_id);
create index item_charge_occurrences_creator_idx on ledger_private.item_charge_occurrences(created_by_principal_id);
create index item_charge_occurrences_withdrawer_idx on ledger_private.item_charge_occurrences(withdrawn_by_principal_id);

-- Serialize source creation/correction and frozen membership, including when
-- the source is absent. Separate post-lock queries require fresh RC snapshots.
create function ledger_private.lock_item_charge_source(p_account text,p_source text) returns void
language plpgsql volatile security invoker set search_path = '' as $$
begin
  if current_setting('transaction_isolation') <> 'read committed' then
    raise exception using errcode='25001',message='Item charge writes require READ COMMITTED';
  end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(
    pg_catalog.json_build_array('ledger-item-charge',p_account,p_source)::text,0));
end;
$$;
revoke all on function ledger_private.lock_item_charge_source(text,text) from public,anon,authenticated,service_role;

create function ledger_private.guard_item_charge_occurrence() returns trigger
language plpgsql volatile security invoker set search_path = '' as $$
begin
  if tg_op not in ('INSERT','UPDATE') then
    raise exception using errcode='55000',message='Item charge history cannot be deleted';
  end if;
  if tg_op='INSERT' then
    perform ledger_private.lock_item_charge_source(new.account_id,new.id);
    if exists(select 1 from ledger_private.collected_invoice_lines
      where account_id=new.account_id and source_kind='item' and source_id=new.id) then
      raise exception using errcode='55000',message='Import charge source before its frozen membership';
    end if;
    return new;
  end if;
  perform ledger_private.lock_item_charge_source(old.account_id,old.id);
  if old.withdrawn_at is not null
    or row(new.id,new.account_id,new.project_id,new.item_id,new.placement_id,new.price_basis,new.created_at,new.created_by_principal_id)
      is distinct from row(old.id,old.account_id,old.project_id,old.item_id,old.placement_id,old.price_basis,old.created_at,old.created_by_principal_id)
    or new.revision<>old.revision+1
    or (new.withdrawn_at is not null and
      row(new.amount_minor_units,new.currency,new.category_id)
        is distinct from row(old.amount_minor_units,old.currency,old.category_id))
    or exists(select 1 from ledger_private.collected_invoice_lines
      where account_id=old.account_id and source_kind='item' and source_id=old.id) then
    raise exception using errcode='55000',message='Charge correction requires mutable exact occurrence and next revision';
  end if;
  return new;
end;
$$;
create trigger item_charge_occurrences_update before insert or update or delete
  on ledger_private.item_charge_occurrences for each row execute function ledger_private.guard_item_charge_occurrence();
create trigger item_charge_occurrences_no_truncate before truncate
  on ledger_private.item_charge_occurrences for each statement execute function ledger_private.guard_item_charge_occurrence();
revoke all on function ledger_private.guard_item_charge_occurrence() from public,anon,authenticated,service_role;

create function ledger_private.validate_collected_item_charge() returns trigger
language plpgsql volatile security invoker set search_path = '' as $$
declare charge ledger_private.item_charge_occurrences; project_id text;
begin
  if new.source_kind<>'item' then return new; end if;
  perform ledger_private.lock_item_charge_source(new.account_id,new.source_id);
  select * into charge from ledger_private.item_charge_occurrences
    where account_id=new.account_id and id=new.source_id;
  -- Generic legacy frozen records remain retained, not proof of an occurrence.
  -- The shared lock prevents a late charge from appearing behind such a record.
  if not found then return new; end if;
  select invoice.project_id into project_id from ledger_private.collected_invoices invoice
    where invoice.account_id=new.account_id and invoice.id=new.invoice_id;
  if charge.withdrawn_at is not null or
    row(charge.project_id,charge.item_id,charge.revision,charge.category_id,charge.amount_minor_units,charge.currency)
      is distinct from row(project_id,new.item_id,new.source_revision,new.category_id,new.signed_amount_minor_units,new.currency) then
    raise exception using errcode='23514',message='Frozen Item line must match its exact current charge';
  end if;
  return new;
end;
$$;
create trigger item_charge_collection_validate before insert on ledger_private.collected_invoice_lines
  for each row execute function ledger_private.validate_collected_item_charge();
revoke all on function ledger_private.validate_collected_item_charge() from public,anon,authenticated,service_role;
alter table ledger_private.item_charge_occurrences enable row level security;
alter table ledger_private.item_charge_occurrences force row level security;
revoke all on ledger_private.item_charge_occurrences from public,anon,authenticated,service_role;
-- Posting/collection writers and read projections are added only with their
-- exact authorization contracts. Amount/category are occurrence snapshots, not
-- the Item's current mutable metadata or paid Invoice membership.
