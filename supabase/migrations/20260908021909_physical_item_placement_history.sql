-- Physical Item identity and custody only. No cash, billing or accounting-status
-- columns. Item command grants and final intake validation remain separate.
create extension if not exists btree_gist with schema extensions;

alter table public.spike_spaces add column placement_project_key text
  generated always as (coalesce(project_id, '')) stored;
alter table public.spike_spaces add constraint spike_spaces_exact_placement_key
  unique (account_id, id, scope_kind, placement_project_key);

create table public.spike_items (
  id text primary key check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id) <= 128),
  account_id text not null references public.spike_accounts(id),
  description text not null default '',
  revision bigint not null default 1 check (revision > 0),
  created_at timestamptz not null default statement_timestamp() check (isfinite(created_at)),
  created_by_principal_id text not null references public.spike_principals(id),
  unique (account_id, id)
);
create index spike_items_creator_idx on public.spike_items(created_by_principal_id);

create table public.spike_item_placements (
  id text primary key check (id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$' and octet_length(id) <= 128),
  account_id text not null,
  item_id text not null,
  scope_kind text not null check (scope_kind in ('business_inventory', 'project')),
  project_id text,
  space_id text,
  placement_project_key text generated always as (coalesce(project_id, '')) stored,
  started_at timestamptz not null check (isfinite(started_at)),
  started_by_principal_id text not null references public.spike_principals(id),
  ended_at timestamptz,
  ended_by_principal_id text references public.spike_principals(id),
  unique (account_id, id, item_id),
  foreign key (account_id, item_id) references public.spike_items(account_id, id),
  foreign key (account_id, project_id) references public.spike_projects(account_id, id),
  foreign key (account_id, space_id, scope_kind, placement_project_key)
    references public.spike_spaces(account_id, id, scope_kind, placement_project_key),
  check ((scope_kind = 'project' and project_id is not null)
    or (scope_kind = 'business_inventory' and project_id is null)),
  check ((ended_at is null and ended_by_principal_id is null)
    or (ended_at is not null and ended_by_principal_id is not null
      and isfinite(ended_at) and ended_at > started_at)),
  -- Adjacent [start,end) intervals are valid; concurrent overlapping inserts
  -- are rejected by Postgres itself, not a racy application preflight.
  exclude using gist (account_id extensions.gist_text_ops with =,
    item_id extensions.gist_text_ops with =,
    tstzrange(started_at, ended_at, '[)') with &&)
);
create unique index spike_item_placements_active_item_idx
  on public.spike_item_placements(account_id, item_id) where ended_at is null;
create index spike_item_placements_item_history_idx
  on public.spike_item_placements(account_id, item_id, started_at, id);
create index spike_item_placements_current_scope_idx
  on public.spike_item_placements(account_id, scope_kind, project_id, item_id)
  where ended_at is null;
create index spike_item_placements_project_fk_idx
  on public.spike_item_placements(account_id, project_id);
create index spike_item_placements_space_fk_idx
  on public.spike_item_placements(account_id, space_id, scope_kind, placement_project_key);
create index spike_item_placements_starter_idx on public.spike_item_placements(started_by_principal_id);
create index spike_item_placements_ender_idx on public.spike_item_placements(ended_by_principal_id);

create function ledger_private.guard_item_identity() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if new.id is distinct from old.id or new.account_id is distinct from old.account_id
    or new.created_at is distinct from old.created_at
    or new.created_by_principal_id is distinct from old.created_by_principal_id then
    raise exception using errcode = '55000', message = 'Item identity and creation evidence are immutable';
  end if;
  if new.revision <> old.revision + 1 then
    raise exception using errcode = '40001', message = 'Item update must advance revision exactly once';
  end if;
  return new;
end;
$$;
create trigger spike_items_identity before update on public.spike_items
  for each row execute function ledger_private.guard_item_identity();

create function ledger_private.guard_item_placement_history() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if tg_op <> 'UPDATE' then
    raise exception using errcode = '55000', message = 'Placement history cannot be deleted or truncated';
  end if;
  if old.ended_at is not null or new.ended_at is null
    or row(new.id,new.account_id,new.item_id,new.scope_kind,new.project_id,new.space_id,
      new.started_at,new.started_by_principal_id)
      is distinct from row(old.id,old.account_id,old.item_id,old.scope_kind,old.project_id,old.space_id,
      old.started_at,old.started_by_principal_id) then
    raise exception using errcode = '55000', message = 'Placement may only be closed once; movement creates a successor';
  end if;
  return new;
end;
$$;
create trigger spike_item_placements_history before update or delete on public.spike_item_placements
  for each row execute function ledger_private.guard_item_placement_history();
create trigger spike_item_placements_no_truncate before truncate on public.spike_item_placements
  for each statement execute function ledger_private.guard_item_placement_history();

alter table public.spike_items enable row level security;
alter table public.spike_items force row level security;
alter table public.spike_item_placements enable row level security;
alter table public.spike_item_placements force row level security;
revoke all on public.spike_items, public.spike_item_placements from public, anon, authenticated, service_role;
revoke all on function ledger_private.guard_item_identity(), ledger_private.guard_item_placement_history()
  from public, anon, authenticated, service_role;

-- One current-location authority; no stored is_accounted_for inference from
-- placement. Financial relationships must join through their eventual facts.
create view ledger_private.current_item_placements with (security_invoker = true) as
  select i.account_id, i.id as item_id, i.description, i.revision,
    p.id as placement_id, p.scope_kind, p.project_id, p.space_id, p.started_at
  from public.spike_items i join public.spike_item_placements p
    on p.account_id = i.account_id and p.item_id = i.id
  where p.ended_at is null;
revoke all on ledger_private.current_item_placements from public, anon, authenticated, service_role;
