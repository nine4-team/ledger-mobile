-- Initial canonical Transaction storage supports the verified imported client
-- payment path. Other types/writers and financial read access remain gated.
alter table public.spike_projects add constraint spike_projects_account_id_client_key
  unique (account_id, id, client_id);

create table public.spike_transactions (
  id text primary key check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id) <= 128),
  account_id text not null,
  project_id text not null,
  client_id text not null,
  type text not null default 'purchase' check (type = 'purchase'),
  role text not null default 'standalone' check (role = 'standalone'),
  amount_minor_units bigint not null check (amount_minor_units > 0),
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  origin text not null default 'firebase_client_payment' check (origin = 'firebase_client_payment'),
  unique (account_id, id),
  foreign key (account_id, project_id, client_id)
    references public.spike_projects(account_id, id, client_id)
);
create index spike_transactions_project_idx on public.spike_transactions(account_id, project_id, client_id);

create table ledger_private.imported_transaction_sources (
  transaction_id text primary key,
  account_id text not null,
  source_account_id text not null check (octet_length(source_account_id) between 1 and 1500 and source_account_id not in ('.', '..') and position('/' in source_account_id) = 0),
  source_document_id text not null check (octet_length(source_document_id) between 1 and 1500 and source_document_id not in ('.', '..') and position('/' in source_document_id) = 0),
  source_bytes bytea not null check (octet_length(source_bytes) between 1 and 4194304),
  source_sha256 text generated always as (encode(extensions.digest(source_bytes, 'sha256'), 'hex')) stored,
  unique (source_account_id, source_document_id),
  foreign key (account_id, transaction_id) references public.spike_transactions(account_id, id)
);
create index imported_transaction_sources_account_idx on ledger_private.imported_transaction_sources(account_id, transaction_id);

alter table public.spike_transactions enable row level security;
alter table public.spike_transactions force row level security;
alter table ledger_private.imported_transaction_sources enable row level security;
alter table ledger_private.imported_transaction_sources force row level security;
revoke all on public.spike_transactions, ledger_private.imported_transaction_sources from public, anon, authenticated, service_role;

create function ledger_private.reject_imported_payment_change() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  raise exception using errcode = '55000', message = 'Imported payment evidence is immutable; correction requires an explicit accounting workflow';
end;
$$;
revoke all on function ledger_private.reject_imported_payment_change() from public, anon, authenticated, service_role;
create trigger imported_payment_immutable before update or delete on public.spike_transactions
  for each row when (old.origin = 'firebase_client_payment')
  execute function ledger_private.reject_imported_payment_change();
create trigger imported_payment_source_immutable before update or delete on ledger_private.imported_transaction_sources
  for each row execute function ledger_private.reject_imported_payment_change();
create trigger imported_payment_no_truncate before truncate on public.spike_transactions
  for each statement execute function ledger_private.reject_imported_payment_change();
create trigger imported_payment_source_no_truncate before truncate on ledger_private.imported_transaction_sources
  for each statement execute function ledger_private.reject_imported_payment_change();

-- Operator-only, invoker-rights import primitive. No API role gets EXECUTE or
-- table access. The approved migration runner must provide reconciled scope,
-- currency, stable ID and canonical source bytes. It is not an app write API.
create function ledger_private.import_client_payment(
  p_id text, p_account_id text, p_project_id text, p_client_id text,
  p_amount bigint, p_currency text, p_source_account text, p_source_document text, p_source_bytes bytea
) returns text language plpgsql security invoker set search_path = '' as $$
declare
  stored public.spike_transactions;
  evidence ledger_private.imported_transaction_sources;
begin
  insert into public.spike_transactions(id, account_id, project_id, client_id, amount_minor_units, currency)
    values (p_id, p_account_id, p_project_id, p_client_id, p_amount, p_currency)
    on conflict (id) do nothing;
  select * into strict stored from public.spike_transactions where id = p_id;
  if row(stored.account_id, stored.project_id, stored.client_id, stored.amount_minor_units, stored.currency)
     is distinct from row(p_account_id, p_project_id, p_client_id, p_amount, p_currency) then
    raise exception using errcode = '22000', message = 'Imported payment identity conflicts with existing target facts';
  end if;
  insert into ledger_private.imported_transaction_sources(transaction_id, account_id, source_account_id, source_document_id, source_bytes)
    values (p_id, p_account_id, p_source_account, p_source_document, p_source_bytes)
    on conflict do nothing;
  select * into evidence from ledger_private.imported_transaction_sources where transaction_id = p_id;
  if not found or row(evidence.account_id, evidence.source_account_id, evidence.source_document_id, evidence.source_bytes)
     is distinct from row(p_account_id, p_source_account, p_source_document, p_source_bytes) then
    raise exception using errcode = '22000', message = 'Imported payment source identity or bytes conflict';
  end if;
  return p_id;
end;
$$;
revoke all on function ledger_private.import_client_payment(text,text,text,text,bigint,text,text,text,bytea)
  from public, anon, authenticated, service_role;
