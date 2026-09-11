-- Canonical Client-paid Item relationship, not a second payment or a report
-- eligibility flag. Command permissions and financial reads remain gated.
alter table public.spike_transactions add constraint spike_transactions_exact_project_client_key
  unique (account_id, id, project_id, client_id, type, role);
alter table public.spike_item_placements add constraint spike_item_placements_exact_project_item_key
  unique (account_id, id, item_id, project_id);

create table ledger_private.item_client_payment_connections (
  id text primary key check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id) <= 128),
  account_id text not null,
  project_id text not null,
  client_id text not null,
  item_id text not null,
  placement_id text not null,
  transaction_id text not null,
  transaction_type text generated always as ('purchase'::text) stored,
  transaction_role text generated always as ('standalone'::text) stored,
  started_at timestamptz not null check (isfinite(started_at)),
  started_by_principal_id text not null references public.spike_principals(id),
  ended_at timestamptz,
  ended_by_principal_id text references public.spike_principals(id),
  foreign key (account_id, placement_id, item_id, project_id)
    references public.spike_item_placements(account_id, id, item_id, project_id),
  foreign key (account_id, transaction_id, project_id, client_id, transaction_type, transaction_role)
    references public.spike_transactions(account_id, id, project_id, client_id, type, role),
  check ((ended_at is null and ended_by_principal_id is null)
    or (ended_at is not null and ended_by_principal_id is not null
      and isfinite(ended_at) and ended_at > started_at)),
  -- Corrections retain the old interval; a retry cannot make an overlapping
  -- duplicate relationship for the same physical placement and payment.
  exclude using gist (account_id extensions.gist_text_ops with =,
    placement_id extensions.gist_text_ops with =,
    transaction_id extensions.gist_text_ops with =,
    tstzrange(started_at, ended_at, '[)') with &&)
);
create index item_client_payment_connections_placement_idx
  on ledger_private.item_client_payment_connections(account_id, placement_id, item_id, project_id);
create index item_client_payment_connections_payment_idx
  on ledger_private.item_client_payment_connections(account_id, transaction_id, project_id, client_id, transaction_type, transaction_role);
create index item_client_payment_connections_starter_idx
  on ledger_private.item_client_payment_connections(started_by_principal_id);
create index item_client_payment_connections_ender_idx
  on ledger_private.item_client_payment_connections(ended_by_principal_id);

create function ledger_private.guard_item_client_payment_connection() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if tg_op <> 'UPDATE' then
    raise exception using errcode='55000', message='Item payment connection history cannot be deleted';
  end if;
  if old.ended_at is not null or new.ended_at is null
    or row(new.id,new.account_id,new.project_id,new.client_id,new.item_id,new.placement_id,
      new.transaction_id,new.started_at,new.started_by_principal_id)
      is distinct from row(old.id,old.account_id,old.project_id,old.client_id,old.item_id,old.placement_id,
        old.transaction_id,old.started_at,old.started_by_principal_id) then
    raise exception using errcode='55000', message='Item payment connection history is immutable except first closure';
  end if;
  return new;
end;
$$;
create trigger item_client_payment_connection_history before update or delete
  on ledger_private.item_client_payment_connections for each row
  execute function ledger_private.guard_item_client_payment_connection();
create trigger item_client_payment_connection_no_truncate before truncate
  on ledger_private.item_client_payment_connections for each statement
  execute function ledger_private.guard_item_client_payment_connection();
revoke all on function ledger_private.guard_item_client_payment_connection()
  from public,anon,authenticated,service_role;
alter table ledger_private.item_client_payment_connections enable row level security;
alter table ledger_private.item_client_payment_connections force row level security;
revoke all on ledger_private.item_client_payment_connections from public,anon,authenticated,service_role;
-- No public writer or read grant is implied. The referenced Transaction table
-- admits only real Client Purchases; the composite FK keeps the qualifying
-- classification constraint even when that table gains other Transaction types.
