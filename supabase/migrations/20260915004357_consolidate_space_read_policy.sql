-- Preserve the union of active directory rows and current archived parents.
-- Factor out the shared membership check; no grants or write policies change.
alter policy spike_spaces_select_active_member on public.spike_spaces
using (
  (select ledger_private.has_active_membership(account_id))
  and (
    lifecycle = 'active'
    or (
      lifecycle = 'archived'
      and exists (
        select 1 from public.spike_item_placements placement
        where placement.account_id = spike_spaces.account_id
          and placement.space_id = spike_spaces.id
          and placement.scope_kind = spike_spaces.scope_kind
          and placement.project_id is not distinct from spike_spaces.project_id
          and placement.ended_at is null
      )
    )
  )
);
drop policy spike_spaces_report_current_parent_read on public.spike_spaces;
