-- Retained source metadata only; no inferred tax/subtotal or accounting inputs.
-- Generated with migra, then reviewed: omit local replication-role grants and
-- explicitly retain invoker security and the required column SELECT grants.
alter table "public"."spike_transactions" add column "legacy_subtotal_minor_units" bigint;

alter table "public"."spike_transactions" add column "legacy_tax_rate_pct" numeric;

alter table "public"."spike_transactions" add constraint "spike_transactions_legacy_tax_finite" CHECK (((legacy_tax_rate_pct IS NULL) OR (legacy_tax_rate_pct <> ALL (ARRAY['NaN'::numeric, 'Infinity'::numeric, '-Infinity'::numeric])))) not valid;

alter table "public"."spike_transactions" validate constraint "spike_transactions_legacy_tax_finite";

grant select (legacy_subtotal_minor_units,legacy_tax_rate_pct) on public.spike_transactions to authenticated;

create or replace view "ledger_private"."transaction_display" with (security_invoker=true) as SELECT t.id,
    t.account_id,
    t.scope_kind,
    t.project_id,
    t.client_id,
    jsonb_build_object('accountId', t.account_id, 'principalId', ledger_private.current_principal_id(), 'transactionId', t.id, 'scopeKind', t.scope_kind, 'projectId', t.project_id, 'clientId', t.client_id, 'type', t.type, 'role', t.role, 'origin', t.origin, 'amountMinorUnits', (t.amount_minor_units)::text, 'currency', t.currency, 'source', t.source, 'transactionDate', to_char((t.transaction_date)::timestamp with time zone, 'YYYY-MM-DD'::text), 'createdAtMilliseconds', (t.created_at_ms)::text, 'notes', t.notes, 'paymentMethod', t.payment_method, 'hasEmailReceipt', t.has_email_receipt, 'legacySubtotalMinorUnits', (t.legacy_subtotal_minor_units)::text, 'legacyTaxRatePct', (t.legacy_tax_rate_pct)::text, 'category',
        CASE
            WHEN (c.id IS NULL) THEN NULL::jsonb
            ELSE jsonb_build_object('id', c.id, 'name', c.display_name, 'kind', c.kind, 'revision', (c.revision)::text)
        END, 'receipt', r.payload) AS payload
   FROM ((public.spike_transactions t
     LEFT JOIN public.spike_budget_categories c ON (((c.account_id = t.account_id) AND (c.id = t.category_id))))
     LEFT JOIN ledger_private.transaction_receipt_display r ON (((r.account_id = t.account_id) AND (r.id = t.id))));
