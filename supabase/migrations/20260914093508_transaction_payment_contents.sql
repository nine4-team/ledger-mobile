-- Generated schema diff, reviewed for invoker and column/function grants that
-- migra omits. No local replication-role grants or public write authority.
grant select (purchase_id,invoice_revision,currency,total_minor_units)
 on ledger_private.collected_invoices to authenticated;
grant select (line_position,description,source_snapshot)
 on ledger_private.collected_invoice_lines to authenticated;
grant execute on function ledger_private.read_collected_invoice(text,text) to authenticated;

drop policy "item_client_payment_current_full_read" on "ledger_private"."item_client_payment_connections";

create or replace view "ledger_private"."transaction_payment_contents" with (security_invoker=true) as SELECT id,
    account_id,
    jsonb_build_object('accountId', account_id, 'principalId', ledger_private.current_principal_id(), 'transactionId', id, 'projectId', project_id, 'clientId', client_id, 'connections', COALESCE(( SELECT jsonb_agg(jsonb_build_object('id', link.id, 'itemId', link.item_id, 'placementId', link.placement_id, 'endedAt', (link.ended_at)::text) ORDER BY link.id) AS jsonb_agg
           FROM ledger_private.item_client_payment_connections link
          WHERE ((link.account_id = t.account_id) AND (link.transaction_id = t.id) AND (link.project_id = t.project_id) AND (link.client_id = t.client_id) AND (link.transaction_type = t.type) AND (link.transaction_role = t.role))), '[]'::jsonb), 'invoice', ( SELECT ledger_private.read_collected_invoice(invoice.account_id, invoice.id) AS read_collected_invoice
           FROM ledger_private.collected_invoices invoice
          WHERE ((invoice.account_id = t.account_id) AND (invoice.project_id = t.project_id) AND (invoice.client_id = t.client_id) AND (invoice.purchase_id = t.id) AND invoice.sealed))) AS payload
   FROM public.spike_transactions t
  WHERE ((origin = 'firebase_client_payment'::text) AND (scope_kind = 'project'::text) AND (type = 'purchase'::text) AND (role = 'standalone'::text));


revoke all on ledger_private.transaction_payment_contents from public,anon,authenticated,service_role;
grant select on ledger_private.transaction_payment_contents to authenticated;


  create policy "item_client_payment_full_history_read"
  on "ledger_private"."item_client_payment_connections"
  as permissive
  for select
  to authenticated
using ((EXISTS ( SELECT 1
   FROM (public.spike_principals principal
     JOIN public.spike_account_memberships membership ON ((membership.principal_id = principal.id)))
  WHERE ((principal.auth_user_id = ( SELECT auth.uid() AS uid)) AND (membership.account_id = item_client_payment_connections.account_id) AND (membership.state = 'active'::text) AND (membership.financial_access = 'full'::text)))));
