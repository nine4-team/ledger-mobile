-- Space changes preserve the Project/Inventory custody interval and its billing
-- links. A separate per-Item token detects any intervening placement mutation.
create table public.item_placement_versions (
  id text primary key,
  account_id text not null,
  revision bigint not null check (revision > 0),
  placement_id text,
  space_id text,
  project_id text,
  foreign key (account_id,id) references public.spike_items(account_id,id),
  foreign key (account_id,placement_id,id) references public.spike_item_placements(account_id,id,item_id),
  foreign key (account_id,space_id) references public.spike_spaces(account_id,id)
);
create index item_placement_versions_account_idx on public.item_placement_versions(account_id,id);
create index item_placement_versions_placement_idx on public.item_placement_versions(account_id,placement_id,id);
create index item_placement_versions_space_idx on public.item_placement_versions(account_id,space_id);
alter table public.item_placement_versions enable row level security;
alter table public.item_placement_versions force row level security;
revoke all on public.item_placement_versions from public,anon,authenticated,service_role;
grant select on public.item_placement_versions to authenticated;
create policy item_placement_versions_member_read on public.item_placement_versions
  for select to authenticated using (exists (
    select 1 from public.spike_account_memberships m
    where m.account_id=item_placement_versions.account_id
      and m.principal_id=ledger_private.current_principal_id() and m.state='active'
  ));

-- This initializes a concurrency token, not a reconstructed historical count.
insert into public.item_placement_versions(id,account_id,revision,placement_id,space_id,project_id)
  select i.id,i.account_id,1,p.id,p.space_id,p.project_id from public.spike_items i
  left join public.spike_item_placements p on p.account_id=i.account_id and p.item_id=i.id and p.ended_at is null;

create table ledger_private.item_space_changes (
  id uuid primary key default gen_random_uuid(),
  account_id text not null,
  item_id text not null,
  placement_id text not null,
  placement_revision bigint not null check (placement_revision > 0),
  from_space_id text,
  to_space_id text,
  changed_at timestamptz not null default clock_timestamp() check (isfinite(changed_at)),
  changed_by_principal_id text not null references public.spike_principals(id),
  foreign key (account_id,placement_id,item_id) references public.spike_item_placements(account_id,id,item_id),
  foreign key (account_id,from_space_id) references public.spike_spaces(account_id,id),
  foreign key (account_id,to_space_id) references public.spike_spaces(account_id,id),
  unique (account_id,item_id,placement_revision),
  check (from_space_id is distinct from to_space_id)
);
create index item_space_changes_placement_idx on ledger_private.item_space_changes(account_id,placement_id,item_id);
create index item_space_changes_from_idx on ledger_private.item_space_changes(account_id,from_space_id);
create index item_space_changes_to_idx on ledger_private.item_space_changes(account_id,to_space_id);
create index item_space_changes_actor_idx on ledger_private.item_space_changes(changed_by_principal_id);
alter table ledger_private.item_space_changes enable row level security;
alter table ledger_private.item_space_changes force row level security;
revoke all on ledger_private.item_space_changes from public,anon,authenticated,service_role;
create trigger item_space_changes_immutable before update or delete or truncate
  on ledger_private.item_space_changes for each statement
  execute function ledger_private.guard_imported_expense_invoice_source();

create or replace function ledger_private.guard_item_placement_history() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if tg_op<>'UPDATE' then
    raise sqlstate '55000' using message='Placement history cannot be deleted or truncated';
  end if;
  if old.ended_at is not null
    or row(new.id,new.account_id,new.item_id,new.scope_kind,new.project_id,
      new.started_at,new.started_by_principal_id)
      is distinct from row(old.id,old.account_id,old.item_id,old.scope_kind,old.project_id,
      old.started_at,old.started_by_principal_id) then
    raise sqlstate '55000' using message='Placement identity and closed history are immutable';
  end if;
  if new.ended_at is not null then
    if new.space_id is distinct from old.space_id then
      raise sqlstate '55000' using message='Closing placement cannot rewrite Space';
    end if;
  elsif new.space_id is not distinct from old.space_id or new.ended_by_principal_id is not null then
    raise sqlstate '55000' using message='Open placement update requires a Space change';
  end if;
  return new;
end;
$$;

create or replace function ledger_private.record_item_placement_change() returns trigger
language plpgsql security invoker set search_path='' as $$
declare version bigint; actor text; current_placement text; current_space text; current_project text;
begin
  select id,space_id,project_id into current_placement,current_space,current_project from public.spike_item_placements
    where account_id=new.account_id and item_id=new.item_id and ended_at is null;
  insert into public.item_placement_versions(id,account_id,revision,placement_id,space_id,project_id)
    values(new.item_id,new.account_id,1,current_placement,current_space,current_project)
    on conflict(id) do update set revision=item_placement_versions.revision+1,
      placement_id=excluded.placement_id,space_id=excluded.space_id,project_id=excluded.project_id
    returning revision into version;
  if tg_op='UPDATE' and new.space_id is distinct from old.space_id then
    actor:=ledger_private.current_principal_id();
    if actor is null then raise sqlstate '42501' using message='Space change requires an authenticated actor'; end if;
    insert into ledger_private.item_space_changes(account_id,item_id,placement_id,placement_revision,
      from_space_id,to_space_id,changed_by_principal_id)
      values(new.account_id,new.item_id,new.id,version,old.space_id,new.space_id,actor);
  end if;
  return null;
end;
$$;
revoke all on function ledger_private.record_item_placement_change() from public,anon,authenticated,service_role;
create trigger spike_item_placements_version after insert or update on public.spike_item_placements
  for each row execute function ledger_private.record_item_placement_change();

-- Compute the net current-membership delta, including an in-scope Space change.
drop trigger spike_item_placements_sync_space_close on public.spike_item_placements;
create or replace function ledger_private.update_space_sync_item_count() returns trigger
language plpgsql security invoker set search_path='' as $$
declare delta record;
begin
  if tg_op='INSERT' then
    for delta in select account_id,space_id,count(*) as amount from new_placements
      where ended_at is null and space_id is not null
      group by account_id,space_id order by account_id,space_id
    loop
      update public.spike_spaces set sync_current_item_count=sync_current_item_count+delta.amount
        where account_id=delta.account_id and id=delta.space_id;
      if not found then raise sqlstate '23503' using message='Missing exact Space parent'; end if;
    end loop;
  elsif tg_op='UPDATE' then
    for delta in select account_id,space_id,sum(amount) as amount from (
      select account_id,space_id,1 as amount from new_placements where ended_at is null and space_id is not null
      union all
      select account_id,space_id,-1 as amount from old_placements where ended_at is null and space_id is not null
    ) changes group by account_id,space_id having sum(amount)<>0 order by account_id,space_id
    loop
      update public.spike_spaces set sync_current_item_count=sync_current_item_count+delta.amount
        where account_id=delta.account_id and id=delta.space_id;
      if not found then raise sqlstate '23503' using message='Missing exact Space parent'; end if;
    end loop;
  end if;
  return null;
end;
$$;
create trigger spike_item_placements_sync_space_close after update on public.spike_item_placements
  referencing old table as old_placements new table as new_placements
  for each statement execute function ledger_private.update_space_sync_item_count();

do $$ begin
  if exists(select 1 from pg_publication where pubname='powersync') then
    alter publication powersync add table public.item_placement_versions;
  end if;
end $$;
