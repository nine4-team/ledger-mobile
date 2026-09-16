-- Live demand stores membership, not a competing copy of source money.
-- No API writes: source validation, commands and reads follow separately.
create table ledger_private.live_invoices (
  id text primary key check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id)<=128),
  account_id text not null,
  project_id text not null,
  name text not null default '',
  notes text not null default '',
  status text not null default 'created' check(status in ('created','sent','paid','canceled')),
  revision bigint not null default 1 check(revision>0),
  created_at timestamptz not null check(isfinite(created_at)),
  created_by_principal_id text not null references public.spike_principals(id),
  unique(account_id,id),
  foreign key(account_id,project_id) references public.spike_projects(account_id,id)
);
create index live_invoices_project_idx on ledger_private.live_invoices(account_id,project_id,id);
create index live_invoices_actor_idx on ledger_private.live_invoices(created_by_principal_id);

create table ledger_private.live_invoice_memberships (
  account_id text not null,
  invoice_id text not null,
  source_kind text not null check(source_kind in ('item','expense','fee_installment')),
  source_id text not null check(source_id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(source_id)<=128),
  position integer not null check(position>=0),
  -- Released membership is retained for provenance. This does not authorize
  -- cancellation or sent-membership changes; those commands need their policy.
  released_at timestamptz check(released_at is null or isfinite(released_at)),
  primary key(account_id,invoice_id,source_kind,source_id),
  foreign key(account_id,invoice_id) references ledger_private.live_invoices(account_id,id)
);
-- Item source_id is its charge/credit occurrence, never the physical Item ID.
-- Paid membership remains reserved; a later return/resale has a new occurrence.
create unique index live_invoice_source_exclusive_idx
  on ledger_private.live_invoice_memberships(account_id,source_kind,source_id) where released_at is null;
create unique index live_invoice_position_idx
  on ledger_private.live_invoice_memberships(account_id,invoice_id,position) where released_at is null;

alter table ledger_private.live_invoices enable row level security;
alter table ledger_private.live_invoice_memberships enable row level security;
revoke all on ledger_private.live_invoices,ledger_private.live_invoice_memberships from public,anon,authenticated,service_role;
