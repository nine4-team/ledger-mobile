create table public.spike_spaces (
  id text primary key,
  account_id text not null,
  scope_kind text not null,
  project_id text,
  display_name text not null,
  lifecycle text not null default 'active',
  revision bigint not null default 1,
  constraint spike_spaces_id_format_check check (
    id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    and octet_length(id) <= 128
  ),
  constraint spike_spaces_account_fkey
    foreign key (account_id)
    references public.spike_accounts(id) on delete cascade,
  constraint spike_spaces_project_scope_fkey
    foreign key (account_id, project_id)
    references public.spike_projects(account_id, id),
  constraint spike_spaces_scope_kind_check
    check (scope_kind in ('project', 'business_inventory')),
  constraint spike_spaces_scope_shape_check check (
    (scope_kind = 'project' and project_id is not null)
    or
    (scope_kind = 'business_inventory' and project_id is null)
  ),
  constraint spike_spaces_display_name_check check (
    display_name <> ''
    and display_name !~ '^[[:space:]]'
    and display_name !~ '[[:space:]]$'
  ),
  constraint spike_spaces_lifecycle_check
    check (lifecycle in ('active', 'archived')),
  constraint spike_spaces_revision_check check (revision > 0)
);

create index spike_spaces_assignment_destination_order_idx
  on public.spike_spaces (
    account_id,
    scope_kind,
    project_id,
    lifecycle,
    lower(display_name) collate "C",
    display_name collate "C",
    id
  );

create index spike_spaces_project_id_idx
  on public.spike_spaces (project_id, account_id)
  where project_id is not null;

create index spike_spaces_project_scope_fk_idx
  on public.spike_spaces (account_id, project_id);

alter table public.spike_spaces enable row level security;

revoke all on table public.spike_spaces from public, anon, authenticated;
grant select on table public.spike_spaces to authenticated;

create policy spike_spaces_select_active_member
on public.spike_spaces
for select
to authenticated
using (
  lifecycle = 'active'
  and (select ledger_private.has_active_membership(account_id))
);
