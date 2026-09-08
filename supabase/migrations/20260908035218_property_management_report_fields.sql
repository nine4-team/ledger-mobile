-- Report inputs are ordinary physical/property facts, not collected cash or
-- company revenue. Unknown source values remain NULL; never infer a name or
-- address from description, or an unknown valuation from zero.
alter table public.spike_items
  add column name text,
  add column sku text,
  add column market_value_minor_units bigint,
  add column market_value_currency text,
  add constraint spike_items_market_value_shape check (
    (market_value_minor_units is null and market_value_currency is null)
    or (market_value_minor_units is not null
      and market_value_currency is not null and market_value_currency ~ '^[A-Z]{3}$')
  );
alter table public.spike_projects add column property_address text;

-- The existing active-member RLS still governs these reads. Item writes remain
-- ungranted and Project updates remain behind their existing trusted commands.
grant select (name, sku, market_value_minor_units, market_value_currency)
  on public.spike_items to authenticated;
grant select (property_address) on public.spike_projects to authenticated;

-- A current Item's archived room is retained physical parent evidence. This
-- does not make unrelated archived Spaces browsable or grant Space mutations.
create policy spike_spaces_report_current_parent_read on public.spike_spaces
for select to authenticated using (
  lifecycle='archived' and scope_kind='project'
  and (select ledger_private.has_active_membership(account_id))
  and exists (select 1 from public.spike_item_placements placement
    where placement.account_id=spike_spaces.account_id
      and placement.project_id=spike_spaces.project_id
      and placement.scope_kind='project' and placement.space_id=spike_spaces.id
      and placement.ended_at is null)
);
