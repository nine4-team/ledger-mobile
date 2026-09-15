begin;
set local search_path=public,extensions;
select plan(21);
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values('vendor-import-project','account-primary','client-existing','Import fixture',now(),now(),1,1,'principal-owner');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values('vendor-import-item','account-primary','Item','principal-owner');
create function pg_temp.vendor_import(p_id text default 'vendor-import',p_items jsonb default
  '[{"id":"vendor-import-link","itemId":"vendor-import-item","amountMinorUnits":null,"membershipKind":"linked"}]',
  p_amount bigint default 9007199254740993,p_source text default 'vendor-source',p_bytes bytea default '\x0102')
returns text language sql as $$
  select ledger_private.import_vendor_purchase(p_id,'account-primary','project','vendor-import-project','client-existing',
    'category-system',p_amount,'USD','[]',p_items,'source-account',p_source,p_bytes);
$$;
select is(pg_temp.vendor_import(),'vendor-import','imports vendor purchase');
select is((select amount_minor_units from public.spike_transactions where id='vendor-import'),9007199254740993::bigint,'preserves exact cents');
select is((select origin from public.spike_transactions where id='vendor-import'),'vendor_payment','never collection payment');
select ok((select amount_minor_units is null from public.transaction_receipt_items where id='vendor-import-link'),'unknown Item cost stays unknown');
select is((select source_bytes from ledger_private.imported_transaction_sources where transaction_id='vendor-import'),'\x0102'::bytea,'source bytes preserved');
select is(pg_temp.vendor_import(),'vendor-import','identical replay succeeds');
select throws_ok($$select pg_temp.vendor_import(p_amount=>42)$$,'22000',null,'changed amount rejected');
select throws_ok($$select pg_temp.vendor_import(p_bytes=>'\x03')$$,'22000',null,'changed source rejected');
select throws_ok($$select pg_temp.vendor_import(p_items=>'[]')$$,'22000',null,'cannot remove Items on replay');
select throws_ok($$select pg_temp.vendor_import('vendor-invalid','[{"id":"bad","itemId":"vendor-import-item","amountMinorUnits":1,"membershipKind":"linked"}]',10,'bad-source')$$,
  '22023',null,'numeric JSON amounts rejected');
select is((select count(*) from public.spike_transactions where id='vendor-invalid'),0::bigint,'failed relationship rolls back Transaction');
select is((select count(*) from ledger_private.imported_transaction_sources where source_document_id='bad-source'),0::bigint,'failed relationship rolls back provenance');
select throws_ok($$select pg_temp.vendor_import('vendor-duplicate','[]',10)$$,'22000',null,'source cannot become another Transaction');
select is(ledger_private.import_vendor_purchase('vendor-business','account-primary','business_inventory',null,null,
  'category-system',15,'USD','[]','[]','source-account','business-source','\x03'),
  'vendor-business','business-paid vendor purchase stays in inventory money scope');
select throws_ok($$select ledger_private.import_vendor_purchase('vendor-foreign','account-other','business_inventory',null,null,
  'category-system',15,'USD','[]','[]','source-account','foreign-source','\x04')$$,
  '23503',null,'foreign category cannot cross Account');
select throws_ok($$select pg_temp.vendor_import('vendor-source-collision','[]',9007199254740993)$$,
  '22000',null,'same source identity cannot be imported under new target');
select is((select count(*) from public.spike_transactions where id='vendor-source-collision'),0::bigint,'source collision rolls back new target');
select throws_ok($$select pg_temp.vendor_import(p_items=>'[{"id":"vendor-import-link","itemId":"vendor-import-item","amountMinorUnits":"12","membershipKind":"linked"}]')$$,
  '22000',null,'replay cannot replace unknown Item cost with a guessed amount');
select throws_ok($$select ledger_private.import_vendor_purchase('vendor-business','account-primary','business_inventory',null,null,
  'category-system',15,'USD','[]','[{"id":"added-link","itemId":"vendor-import-item","amountMinorUnits":null,"membershipKind":"linked"}]',
  'source-account','business-source','\x03')$$,'22000',null,'replay cannot append Items');
select ok(not exists(select 1 from unnest(array['anon','authenticated','service_role']) r
  where has_function_privilege(r,'ledger_private.import_vendor_purchase(text,text,text,text,text,text,bigint,text,jsonb,jsonb,text,text,bytea)','EXECUTE')),
  'API roles cannot invoke import');
select ok(not (select prosecdef from pg_proc where oid='ledger_private.import_vendor_purchase(text,text,text,text,text,text,bigint,text,jsonb,jsonb,text,text,bytea)'::regprocedure),
  'import uses invoker rights');
select * from finish();
rollback;
