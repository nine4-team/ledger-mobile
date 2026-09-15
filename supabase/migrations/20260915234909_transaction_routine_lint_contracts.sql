-- Read-only frozen contents share the caller's statement snapshot. Keep invoker
-- security, grants and exact sealed-Invoice validation unchanged.
alter function ledger_private.read_collected_invoice(text,text) stable;

-- Preserve deployed function bodies and grants; change only the diagnosed
-- declarations. Fail if a future definition no longer matches this repair.
do $repair$
declare
  routine_name text;
  definition text;
  repaired text;
begin
  foreach routine_name in array array[
    'import_vendor_purchase', 'valid_non_item_receipt_lines', 'import_expense_invoice'
  ] loop
    select pg_get_functiondef(p.oid) into strict definition
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace
    where n.nspname='ledger_private' and p.proname=routine_name;
    repaired := replace(replace(definition,
      'text[] := ''{}''', 'text[] := ARRAY[]::text[]'),
      'text[]:=''{}''', 'text[]:=ARRAY[]::text[]');
    if routine_name='valid_non_item_receipt_lines' then
      repaired := replace(repaired, '; amount bigint;', ';');
      repaired := replace(repaired, 'amount := (line->>''amountMinorUnits'')::bigint;',
        'perform (line->>''amountMinorUnits'')::bigint;');
    end if;
    if repaired=definition then
      raise exception 'Expected lint repair source missing for %',routine_name;
    end if;
    execute repaired;
  end loop;
end;
$repair$;
