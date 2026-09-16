-- Planned Fee demand, not a payment. Creation/cap validation remains in the
-- future typed writer; clients receive no direct table access here.
create table ledger_private.fee_installments (
  id text primary key check(id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id)<=128),
  account_id text not null,
  project_id text not null,
  category_id text not null,
  label text not null check(label ~ '[^[:space:]]'),
  amount_minor_units bigint not null check(amount_minor_units>0),
  currency text not null check(currency ~ '^[A-Z]{3}$'),
  sort_order integer,
  revision bigint not null default 1 check(revision>0),
  created_at timestamptz not null check(isfinite(created_at)),
  created_by_principal_id text not null references public.spike_principals(id),
  unique(account_id,id),
  foreign key(account_id,project_id) references public.spike_projects(account_id,id),
  foreign key(account_id,category_id) references public.spike_budget_categories(account_id,id)
);
create index fee_installments_project_idx on ledger_private.fee_installments(account_id,project_id,id);
create index fee_installments_category_idx on ledger_private.fee_installments(account_id,category_id);
create index fee_installments_actor_idx on ledger_private.fee_installments(created_by_principal_id);
alter table ledger_private.fee_installments enable row level security;
revoke all on ledger_private.fee_installments from public,anon,authenticated,service_role;

create function ledger_private.guard_fee_source_write() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if current_setting('transaction_isolation')<>'read committed' then
    raise sqlstate '25001' using message='Fee writes require READ COMMITTED';
  end if;
  if exists(select 1 from ledger_private.collected_invoice_lines where account_id=old.account_id
    and source_kind='fee_installment' and source_id=old.id) then
    raise sqlstate '23514' using message='Collected Fee is immutable';
  end if;
  if tg_op='UPDATE' and (row(new.id,new.account_id,new.project_id,new.created_at,new.created_by_principal_id)
    is distinct from row(old.id,old.account_id,old.project_id,old.created_at,old.created_by_principal_id)
    or new.revision<>old.revision+1) then
    raise sqlstate '23514' using message='Fee edit requires original identity and next revision';
  end if;
  if tg_op='DELETE' then return old; end if;
  return new;
end;
$$;
revoke all on function ledger_private.guard_fee_source_write() from public,anon,authenticated,service_role;
create trigger fee_source_write before update or delete on ledger_private.fee_installments
for each row execute function ledger_private.guard_fee_source_write();

create function ledger_private.guard_collected_fee_source() returns trigger
language plpgsql security invoker set search_path='' as $$
declare source ledger_private.fee_installments; project text;
begin
  if new.source_kind<>'fee_installment' then return new; end if;
  if current_setting('transaction_isolation')<>'read committed' then
    raise sqlstate '25001' using message='Fee writes require READ COMMITTED';
  end if;
  select * into source from ledger_private.fee_installments
    where account_id=new.account_id and id=new.source_id for update;
  -- Existing source-only historical snapshots stay valid; this is not import authority.
  if not found then return new; end if;
  select project_id into project from ledger_private.collected_invoices
    where account_id=new.account_id and id=new.invoice_id;
  if row(source.project_id,source.revision,source.currency,source.amount_minor_units,source.category_id)
    is distinct from row(project,new.source_revision,new.currency,new.signed_amount_minor_units,new.category_id) then
    raise sqlstate '23514' using message='Collected Fee source changed';
  end if;
  return new;
end;
$$;
revoke all on function ledger_private.guard_collected_fee_source() from public,anon,authenticated,service_role;
create trigger collected_fee_source before insert on ledger_private.collected_invoice_lines
for each row execute function ledger_private.guard_collected_fee_source();
