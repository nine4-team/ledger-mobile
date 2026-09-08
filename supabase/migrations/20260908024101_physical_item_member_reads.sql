-- Preserve ordinary member reads of physical facts only. Explicit columns
-- ensure future financial columns do not inherit this grant accidentally.
grant select (id, account_id, description, revision, created_at, created_by_principal_id)
  on public.spike_items to authenticated;
grant select (id, account_id, item_id, scope_kind, project_id, space_id,
  started_at, started_by_principal_id, ended_at, ended_by_principal_id)
  on public.spike_item_placements to authenticated;
create policy spike_items_member_read on public.spike_items for select to authenticated
  using ((select ledger_private.has_active_membership(account_id)));
create policy spike_item_placements_member_read on public.spike_item_placements for select to authenticated
  using ((select ledger_private.has_active_membership(account_id)));
-- No API writes, service-role grant, private-view access or financial evidence
-- access. Historical physical placement does not prove payment or billing.
