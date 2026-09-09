-- Archived Spaces remain readable only as exact current physical parents.
-- Inventory has a NULL project_id, so ordinary equality would omit it.
-- Directory queries retain their active-only predicate; this expands neither
-- archived browsing nor mutation authority.
alter policy spike_spaces_report_current_parent_read on public.spike_spaces
using (
  lifecycle = 'archived'
  and (select ledger_private.has_active_membership(account_id))
  and exists (
    select 1 from public.spike_item_placements placement
    where placement.account_id = spike_spaces.account_id
      and placement.space_id = spike_spaces.id
      and placement.scope_kind = spike_spaces.scope_kind
      and placement.project_id is not distinct from spike_spaces.project_id
      and placement.ended_at is null
  )
);
