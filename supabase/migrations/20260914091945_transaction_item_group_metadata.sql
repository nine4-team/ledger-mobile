-- Current presentation metadata is distinct from retained receipt prices.
create or replace view "ledger_private"."transaction_receipt_display" with (security_invoker=true) as SELECT t.id,
    t.account_id,
    jsonb_build_object('accountId', t.account_id, 'transactionId', t.id, 'principalId', ledger_private.current_principal_id(), 'scopeKind', t.scope_kind, 'projectId', t.project_id, 'clientId', t.client_id, 'type', t.type, 'amountMinorUnits', (t.amount_minor_units)::text, 'currency', t.currency, 'category', jsonb_build_object('id', c.id, 'name', c.display_name, 'kind', c.kind, 'revision', (c.revision)::text), 'nonItemReceiptLines', t.non_item_receipt_lines, 'items', COALESCE(( SELECT jsonb_agg(jsonb_build_object('itemId', i.item_id, 'amountMinorUnits', (i.amount_minor_units)::text, 'membershipKind', i.membership_kind, 'name', COALESCE(item.name, item.description), 'sku', item.sku, 'source', item.source, 'currentSource', item.current_source, 'currentSpaceName', space.display_name, 'imageCount', (images.expected_count)::text) ORDER BY i.item_id) AS jsonb_agg
           FROM ((((public.transaction_receipt_items i
             LEFT JOIN public.spike_items item ON (((item.account_id = i.account_id) AND (item.id = i.item_id))))
             LEFT JOIN public.spike_item_placements placement ON (((placement.account_id = i.account_id) AND (placement.item_id = i.item_id) AND (placement.ended_at IS NULL))))
             LEFT JOIN public.spike_spaces space ON (((space.account_id = placement.account_id) AND (space.id = placement.space_id) AND (space.scope_kind = placement.scope_kind) AND (NOT (space.project_id IS DISTINCT FROM placement.project_id)))))
             LEFT JOIN public.item_image_sets images ON (((images.account_id = i.account_id) AND (images.item_id = i.item_id))))
          WHERE ((i.account_id = t.account_id) AND (i.transaction_id = t.id))), '[]'::jsonb)) AS payload
   FROM (public.spike_transactions t
     JOIN public.spike_budget_categories c ON (((c.account_id = t.account_id) AND (c.id = t.category_id))))
  WHERE (t.origin = 'vendor_payment'::text);
