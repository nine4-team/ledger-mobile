-- Reviewed generated diff: retain invoker authorization, omit local-only
-- replication grants. Current labels do not rewrite frozen Invoice contents.
create or replace view "ledger_private"."transaction_payment_contents" with (security_invoker=true) as SELECT id,
    account_id,
    jsonb_build_object('accountId', account_id, 'principalId', ledger_private.current_principal_id(), 'transactionId', id, 'projectId', project_id, 'clientId', client_id, 'connections', COALESCE(( SELECT jsonb_agg(jsonb_build_object('id', link.id, 'itemId', link.item_id, 'placementId', link.placement_id, 'endedAt', (link.ended_at)::text) ORDER BY link.id) AS jsonb_agg
           FROM ledger_private.item_client_payment_connections link
          WHERE ((link.account_id = t.account_id) AND (link.transaction_id = t.id) AND (link.project_id = t.project_id) AND (link.client_id = t.client_id) AND (link.transaction_type = t.type) AND (link.transaction_role = t.role))), '[]'::jsonb), 'invoice', ( SELECT ledger_private.read_collected_invoice(invoice.account_id, invoice.id) AS read_collected_invoice
           FROM ledger_private.collected_invoices invoice
          WHERE ((invoice.account_id = t.account_id) AND (invoice.project_id = t.project_id) AND (invoice.client_id = t.client_id) AND (invoice.purchase_id = t.id) AND invoice.sealed)), 'items', COALESCE(( SELECT jsonb_agg(jsonb_build_object('itemId', member.item_id, 'name', COALESCE(item.name, item.description), 'sku', item.sku, 'source', item.source, 'currentSource', item.current_source, 'currentSpaceName', space.display_name, 'imageCount', (images.expected_count)::text) ORDER BY (member.item_id COLLATE "C")) AS jsonb_agg
           FROM ((((( SELECT link.item_id
                   FROM ledger_private.item_client_payment_connections link
                  WHERE ((link.account_id = t.account_id) AND (link.transaction_id = t.id) AND (link.project_id = t.project_id) AND (link.client_id = t.client_id) AND (link.transaction_type = t.type) AND (link.transaction_role = t.role))
                UNION
                 SELECT line.item_id
                   FROM (ledger_private.collected_invoice_lines line
                     JOIN ledger_private.collected_invoices invoice ON (((invoice.account_id = line.account_id) AND (invoice.id = line.invoice_id))))
                  WHERE ((invoice.account_id = t.account_id) AND (invoice.purchase_id = t.id) AND (invoice.project_id = t.project_id) AND (invoice.client_id = t.client_id) AND invoice.sealed AND (line.source_kind = 'item'::text) AND (line.item_id IS NOT NULL))) member
             LEFT JOIN public.spike_items item ON (((item.account_id = t.account_id) AND (item.id = member.item_id))))
             LEFT JOIN public.spike_item_placements placement ON (((placement.account_id = t.account_id) AND (placement.item_id = member.item_id) AND (placement.ended_at IS NULL))))
             LEFT JOIN public.spike_spaces space ON (((space.account_id = placement.account_id) AND (space.id = placement.space_id) AND (space.scope_kind = placement.scope_kind) AND (NOT (space.project_id IS DISTINCT FROM placement.project_id)))))
             LEFT JOIN public.item_image_sets images ON (((images.account_id = t.account_id) AND (images.item_id = member.item_id))))), '[]'::jsonb)) AS payload
   FROM public.spike_transactions t
  WHERE ((origin = 'firebase_client_payment'::text) AND (scope_kind = 'project'::text) AND (type = 'purchase'::text) AND (role = 'standalone'::text));
