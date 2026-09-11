-- Read only the canonical Purchase attached to a current physical Item placement.
-- O-060 authorizes full financial reads, not new payment writes (O-065).
-- Imported source bytes and the existing immutable triggers remain untouched.
grant select (id, account_id, project_id, client_id, type, role,
  amount_minor_units, currency, origin) on public.spike_transactions to authenticated;

create policy item_linked_purchase_full_read on public.spike_transactions
  for select to authenticated using (
    exists (
      select 1 from public.spike_principals principal
      join public.spike_account_memberships membership on membership.principal_id=principal.id
      where principal.auth_user_id=(select auth.uid())
        and membership.account_id=spike_transactions.account_id
        and membership.state='active' and membership.financial_access='full'
    ) and exists (
      select 1 from ledger_private.item_client_payment_connections link
      join public.spike_item_placements placement on placement.id=link.placement_id
        and placement.account_id=link.account_id and placement.project_id=link.project_id
        and placement.item_id=link.item_id
      where link.transaction_id=spike_transactions.id
        and link.account_id=spike_transactions.account_id
        and link.project_id=spike_transactions.project_id
        and link.client_id=spike_transactions.client_id
        and link.transaction_type=spike_transactions.type
        and link.transaction_role=spike_transactions.role
        and link.ended_at is null and placement.ended_at is null
        and placement.scope_kind='project'
    )
  );
