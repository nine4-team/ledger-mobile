-- Separate current destination price from immutable acquisition/paid amounts.
-- No public writes until the owning sale command is implemented and verified.
create table ledger_private.item_project_prices (
  account_id text not null,
  item_id text not null,
  amount_minor_units bigint not null check (amount_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  revision bigint not null default 1 check (revision > 0),
  updated_at timestamptz not null check (isfinite(updated_at)),
  updated_by_principal_id text not null references public.spike_principals(id),
  primary key (account_id,item_id),
  foreign key (account_id,item_id) references public.spike_items(account_id,id)
);
create index item_project_prices_actor_idx on ledger_private.item_project_prices(updated_by_principal_id);
alter table ledger_private.item_project_prices enable row level security;
alter table ledger_private.item_project_prices force row level security;
revoke all on ledger_private.item_project_prices from public,anon,authenticated,service_role;

create function ledger_private.guard_item_project_price() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if tg_op <> 'UPDATE' then
    raise exception using errcode='55000',message='Item project prices cannot be deleted or truncated';
  end if;
  if row(new.account_id,new.item_id,new.currency) is distinct from row(old.account_id,old.item_id,old.currency)
    or new.revision <> old.revision + 1 or new.updated_at < old.updated_at then
    raise exception using errcode='40001',message='Price update requires same Item/currency and next revision';
  end if;
  return new;
end;
$$;
revoke all on function ledger_private.guard_item_project_price() from public,anon,authenticated,service_role;
create trigger item_project_prices_revision before update or delete on ledger_private.item_project_prices
  for each row execute function ledger_private.guard_item_project_price();
create trigger item_project_prices_no_truncate before truncate on ledger_private.item_project_prices
  for each statement execute function ledger_private.guard_item_project_price();
