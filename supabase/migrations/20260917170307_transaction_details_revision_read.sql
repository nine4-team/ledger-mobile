-- Preserve the existing shared invoker projection, adding only the descriptive
-- edit token. It is not a version of the frozen accounting evidence.
create or replace view ledger_private.transaction_display with (security_invoker=true) as
select t.id,t.account_id,t.scope_kind,t.project_id,t.client_id,
  jsonb_build_object(
    'accountId',t.account_id,'principalId',ledger_private.current_principal_id(),
    'transactionId',t.id,'scopeKind',t.scope_kind,'projectId',t.project_id,'clientId',t.client_id,
    'type',t.type,'role',t.role,'origin',t.origin,
    'amountMinorUnits',t.amount_minor_units::text,'currency',t.currency,
    'source',t.source,'transactionDate',to_char(t.transaction_date,'YYYY-MM-DD'),
    'createdAtMilliseconds',t.created_at_ms::text,'notes',t.notes,
    'paymentMethod',t.payment_method,'hasEmailReceipt',t.has_email_receipt,
    'detailsRevision',t.details_revision::text,
    'legacySubtotalMinorUnits',t.legacy_subtotal_minor_units::text,'legacyTaxRatePct',t.legacy_tax_rate_pct::text,
    'category',case when c.id is null then null else jsonb_build_object(
      'id',c.id,'name',c.display_name,'kind',c.kind,'revision',c.revision::text) end,
    'receipt',r.payload,'currentItemCategories',i.items,'paymentContents',p.payload) as payload
from public.spike_transactions t
left join public.spike_budget_categories c on c.account_id=t.account_id and c.id=t.category_id
left join ledger_private.transaction_receipt_display r on r.account_id=t.account_id and r.id=t.id
left join ledger_private.transaction_current_item_categories i on i.account_id=t.account_id and i.id=t.id
left join ledger_private.transaction_payment_contents p on p.account_id=t.account_id and p.id=t.id;
