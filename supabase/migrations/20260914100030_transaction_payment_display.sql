-- Generated local schema diff; keep the existing invoker/SELECT boundary and
-- omit machine-local replication grants. No write permissions change.
create or replace view "ledger_private"."transaction_display" with (security_invoker=true) as SELECT t.id,
    t.account_id,
    t.scope_kind,
    t.project_id,
    t.client_id,
    jsonb_build_object('accountId', t.account_id, 'principalId', ledger_private.current_principal_id(), 'transactionId', t.id, 'scopeKind', t.scope_kind, 'projectId', t.project_id, 'clientId', t.client_id, 'type', t.type, 'role', t.role, 'origin', t.origin, 'amountMinorUnits', (t.amount_minor_units)::text, 'currency', t.currency, 'source', t.source, 'transactionDate', to_char((t.transaction_date)::timestamp with time zone, 'YYYY-MM-DD'::text), 'createdAtMilliseconds', (t.created_at_ms)::text, 'notes', t.notes, 'paymentMethod', t.payment_method, 'hasEmailReceipt', t.has_email_receipt, 'legacySubtotalMinorUnits', (t.legacy_subtotal_minor_units)::text, 'legacyTaxRatePct', (t.legacy_tax_rate_pct)::text, 'category',
        CASE
            WHEN (c.id IS NULL) THEN NULL::jsonb
            ELSE jsonb_build_object('id', c.id, 'name', c.display_name, 'kind', c.kind, 'revision', (c.revision)::text)
        END, 'receipt', r.payload, 'currentItemCategories', i.items, 'paymentContents', p.payload) AS payload
   FROM ((((public.spike_transactions t
     LEFT JOIN public.spike_budget_categories c ON (((c.account_id = t.account_id) AND (c.id = t.category_id))))
     LEFT JOIN ledger_private.transaction_receipt_display r ON (((r.account_id = t.account_id) AND (r.id = t.id))))
     LEFT JOIN ledger_private.transaction_current_item_categories i ON (((i.account_id = t.account_id) AND (i.id = t.id))))
     LEFT JOIN ledger_private.transaction_payment_contents p ON (((p.account_id = t.account_id) AND (p.id = t.id))));
