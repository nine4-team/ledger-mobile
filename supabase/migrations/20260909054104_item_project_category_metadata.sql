-- Current physical category attribution, not a budget allocation or a billing
-- snapshot. Ordinary writers must assign the enabled Furnishings default and
-- preserve whole-batch correction invariants; no such writer is granted here.
create table public.spike_item_project_categories (
  id text primary key,
  account_id text not null,
  project_id text not null,
  item_id text not null,
  category_id text not null,
  revision bigint not null default 1 check (revision > 0),
  foreign key (account_id,id,item_id,project_id)
    references public.spike_item_placements(account_id,id,item_id,project_id),
  foreign key (account_id,category_id) references public.spike_budget_categories(account_id,id)
);
create index spike_item_project_categories_category_idx
  on public.spike_item_project_categories(account_id,category_id);
create index spike_item_project_categories_placement_idx
  on public.spike_item_project_categories(account_id,id,item_id,project_id);
create index spike_item_project_categories_project_idx
  on public.spike_item_project_categories(account_id,project_id);

create function ledger_private.guard_item_project_category() returns trigger
language plpgsql security invoker set search_path = '' as $$
begin
  if tg_op <> 'UPDATE' then
    raise exception using errcode='55000',message='Physical category attribution cannot be deleted';
  end if;
  -- Serialize correction with departure; checking an unlocked current row could
  -- otherwise race the transaction which closes this placement.
  perform 1 from public.spike_item_placements
    where account_id=old.account_id and id=old.id and ended_at is null for update;
  if row(new.id,new.account_id,new.project_id,new.item_id)
      is distinct from row(old.id,old.account_id,old.project_id,old.item_id)
    or new.revision <> old.revision+1
    or not found then
    raise exception using errcode='55000',message='Category correction requires current exact placement and next revision';
  end if;
  return new;
end;
$$;
create trigger spike_item_project_categories_update before update or delete
  on public.spike_item_project_categories for each row execute function ledger_private.guard_item_project_category();
create trigger spike_item_project_categories_no_truncate before truncate
  on public.spike_item_project_categories for each statement execute function ledger_private.guard_item_project_category();
revoke all on function ledger_private.guard_item_project_category() from public,anon,authenticated,service_role;
alter table public.spike_item_project_categories enable row level security;
alter table public.spike_item_project_categories force row level security;
revoke all on public.spike_item_project_categories from public,anon,authenticated,service_role;
grant select on public.spike_item_project_categories to authenticated;
create policy spike_item_project_categories_visible_member
  on public.spike_item_project_categories for select to authenticated
  using ((select ledger_private.has_active_membership(account_id)) and exists (
    select 1 from public.spike_budget_categories category
    where category.account_id=spike_item_project_categories.account_id
      and category.id=spike_item_project_categories.category_id
      and ledger_private.can_view_budget_category(category.account_id,category.visibility_class)
  ));
