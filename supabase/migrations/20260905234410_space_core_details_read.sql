alter table public.spike_spaces
  add constraint spike_spaces_account_identity_key
  unique (account_id, id);

create table public.spike_space_core_details (
  id text primary key,
  account_id text not null,
  notes text,
  created_at timestamptz not null,
  updated_at timestamptz not null,
  created_at_ms bigint not null,
  updated_at_ms bigint not null,
  constraint spike_space_core_details_space_scope_fkey
    foreign key (account_id, id)
    references public.spike_spaces(account_id, id)
    on delete cascade,
  constraint spike_space_core_details_created_at_exact_check check (
    pg_catalog.isfinite(created_at)
    and created_at = date_trunc('milliseconds', created_at)
    and created_at_ms = floor(extract(epoch from created_at) * 1000)::bigint
  ),
  constraint spike_space_core_details_updated_at_exact_check check (
    pg_catalog.isfinite(updated_at)
    and updated_at = date_trunc('milliseconds', updated_at)
    and updated_at_ms = floor(extract(epoch from updated_at) * 1000)::bigint
  )
);

create index spike_space_core_details_scope_idx
  on public.spike_space_core_details (account_id, id);

create table public.spike_space_checklists (
  id text primary key,
  account_id text not null,
  space_id text not null,
  checklist_id text not null,
  name text not null,
  presentation_order bigint not null,
  constraint spike_space_checklists_provider_id_format_check check (
    id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    and octet_length(id) <= 128
  ),
  constraint spike_space_checklists_domain_id_format_check check (
    checklist_id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    and octet_length(checklist_id) <= 128
  ),
  constraint spike_space_checklists_space_scope_fkey
    foreign key (account_id, space_id)
    references public.spike_spaces(account_id, id)
    on delete cascade,
  constraint spike_space_checklists_domain_identity_key
    unique (account_id, space_id, checklist_id),
  constraint spike_space_checklists_presentation_order_key
    unique (account_id, space_id, presentation_order),
  constraint spike_space_checklists_presentation_order_check check (
    presentation_order between 0 and 4294967295
  )
);

create index spike_space_checklists_scope_order_idx
  on public.spike_space_checklists (
    account_id,
    space_id,
    presentation_order,
    id
  );

create table public.spike_space_checklist_items (
  id text primary key,
  account_id text not null,
  space_id text not null,
  checklist_id text not null,
  item_id text not null,
  item_text text not null,
  is_checked boolean not null,
  presentation_order bigint not null,
  constraint spike_space_checklist_items_provider_id_format_check check (
    id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    and octet_length(id) <= 128
  ),
  constraint spike_space_checklist_items_domain_id_format_check check (
    item_id ~ '^[[:alnum:]][[:alnum:]_.:-]{0,127}$'
    and octet_length(item_id) <= 128
  ),
  constraint spike_space_checklist_items_checklist_scope_fkey
    foreign key (account_id, space_id, checklist_id)
    references public.spike_space_checklists(account_id, space_id, checklist_id)
    on delete cascade,
  constraint spike_space_checklist_items_domain_identity_key
    unique (account_id, space_id, checklist_id, item_id),
  constraint spike_space_checklist_items_presentation_order_key
    unique (account_id, space_id, checklist_id, presentation_order),
  constraint spike_space_checklist_items_presentation_order_check check (
    presentation_order between 0 and 4294967295
  )
);

create index spike_space_checklist_items_scope_order_idx
  on public.spike_space_checklist_items (
    account_id,
    space_id,
    checklist_id,
    presentation_order,
    id
  );

alter table public.spike_space_core_details enable row level security;
alter table public.spike_space_core_details force row level security;
alter table public.spike_space_checklists enable row level security;
alter table public.spike_space_checklists force row level security;
alter table public.spike_space_checklist_items enable row level security;
alter table public.spike_space_checklist_items force row level security;

revoke all on table public.spike_space_core_details
from public, anon, authenticated;
revoke all on table public.spike_space_checklists
from public, anon, authenticated;
revoke all on table public.spike_space_checklist_items
from public, anon, authenticated;

create policy spike_space_core_details_select_active_member
on public.spike_space_core_details
for select
to authenticated
using ((select ledger_private.has_active_membership(account_id)));

create policy spike_space_checklists_select_active_member
on public.spike_space_checklists
for select
to authenticated
using ((select ledger_private.has_active_membership(account_id)));

create policy spike_space_checklist_items_select_active_member
on public.spike_space_checklist_items
for select
to authenticated
using ((select ledger_private.has_active_membership(account_id)));
