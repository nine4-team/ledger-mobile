-- D-009: business-paid costs are Expense sources, not client-payment Transactions.
-- No API writes or editing/collection policy is granted by this storage migration.
create table ledger_private.expenses (
  id text primary key check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id)<=128),
  account_id text not null,
  project_id text not null,
  category_id text not null,
  vendor text not null,
  expense_date date not null check (expense_date between date '0001-01-01' and date '9999-12-31'),
  final_amount_minor_units bigint not null,
  currency text not null check (currency ~ '^[A-Z]{3}$'),
  notes text not null default '',
  revision bigint not null default 1 check (revision>0),
  created_at timestamptz not null check (isfinite(created_at)),
  created_by_principal_id text not null references public.spike_principals(id),
  unique (account_id,id),
  unique (account_id,id,currency),
  foreign key (account_id,project_id) references public.spike_projects(account_id,id),
  foreign key (account_id,category_id) references public.spike_budget_categories(account_id,id)
);
create index expenses_project_idx on ledger_private.expenses(account_id,project_id,id);
create index expenses_category_idx on ledger_private.expenses(account_id,category_id);
create index expenses_actor_idx on ledger_private.expenses(created_by_principal_id);

create table ledger_private.expense_receipt_lines (
  account_id text not null,
  expense_id text not null,
  id text not null check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id)<=128),
  position integer not null check (position>=0),
  description text not null check (description ~ '[^[:space:]]'),
  magnitude_minor_units bigint not null check (magnitude_minor_units>0),
  currency text not null,
  effect text not null check (effect in ('increase','decrease')),
  quantity bigint,
  primary key (account_id,expense_id,id),
  unique (account_id,expense_id,position),
  foreign key (account_id,expense_id,currency) references ledger_private.expenses(account_id,id,currency)
);

-- Reuse the existing verified media object catalog; no separate upload store.
create table ledger_private.expense_receipt_attachments (
  account_id text not null,
  expense_id text not null,
  attachment_id text not null,
  position integer not null check (position>=0),
  primary key (account_id,expense_id,attachment_id),
  unique (account_id,expense_id,position),
  foreign key (account_id,expense_id) references ledger_private.expenses(account_id,id),
  foreign key (account_id,attachment_id) references public.item_image_objects(account_id,id)
);
create index expense_receipt_attachment_object_idx on ledger_private.expense_receipt_attachments(account_id,attachment_id);

alter table ledger_private.expenses enable row level security;
alter table ledger_private.expenses force row level security;
alter table ledger_private.expense_receipt_lines enable row level security;
alter table ledger_private.expense_receipt_lines force row level security;
alter table ledger_private.expense_receipt_attachments enable row level security;
alter table ledger_private.expense_receipt_attachments force row level security;
revoke all on ledger_private.expenses,ledger_private.expense_receipt_lines,ledger_private.expense_receipt_attachments
  from public,anon,authenticated,service_role;
