-- D-013: Item accounting's category identity is not a mutable name/type/default.
-- Existing Accounts remain unresolved until their setup/import supplies a
-- reviewed identity. Never infer this relationship from display-name matching.
alter table public.spike_accounts add column furnishings_category_id text;
alter table public.spike_accounts add constraint spike_accounts_furnishings_category_fk
  foreign key (id,furnishings_category_id) references public.spike_budget_categories(account_id,id);
create index spike_accounts_furnishings_category_idx
  on public.spike_accounts(id,furnishings_category_id) where furnishings_category_id is not null;

create function ledger_private.guard_furnishings_identity() returns trigger
language plpgsql security invoker set search_path='' as $$
begin
  if old.furnishings_category_id is not null
    and new.furnishings_category_id is distinct from old.furnishings_category_id then
    raise exception using errcode='55000',message='Canonical Furnishings identity cannot be reassigned';
  end if;
  return new;
end;
$$;
revoke all on function ledger_private.guard_furnishings_identity() from public,anon,authenticated,service_role;
create trigger spike_accounts_furnishings_identity before update of furnishings_category_id
  on public.spike_accounts for each row execute function ledger_private.guard_furnishings_identity();
