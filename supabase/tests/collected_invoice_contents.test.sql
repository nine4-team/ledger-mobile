begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('frozen-project','account-primary','client-existing','Frozen fixture',now(),now(),1,1,'principal-owner');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values ('frozen-item','account-primary','Original Item','principal-owner');

create function pg_temp.freeze_invoice(p_id text, p_total bigint default 100, p_payment bigint default 100,
  p_seal boolean default true, p_lines boolean default true) returns void language plpgsql as $$
begin
  perform ledger_private.import_client_payment('payment-'||p_id,'account-primary','frozen-project','client-existing',
    p_payment,'USD','synthetic-frozen',p_id,'\x01'::bytea);
  insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
  values(p_id,'account-primary','frozen-project','client-existing','payment-'||p_id,1,'USD',p_total);
  if p_lines then
    insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,
      source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
    values
      (p_id||'-charge','account-primary',p_id,0,'USD','item',p_id||'-sale','frozen-item',2,'furnishings',120,
       E'  Original charge\n','{"basis":"projectPrice","amount":"120"}'),
      (p_id||'-credit','account-primary',p_id,1,'USD','item',p_id||'-return','frozen-item',3,'furnishings',-20,
       'Original credit','{"basis":"paidInvoiceLine","invoiceId":"original","lineId":"original-line","amount":"20"}');
  end if;
  if p_seal then update ledger_private.collected_invoices set sealed=true where id=p_id; end if;
  set constraints all immediate;
  set constraints all deferred;
end;
$$;

select lives_ok($$select pg_temp.freeze_invoice('frozen-one')$$,'Complete signed allocations can be sealed');
select is((select string_agg(id,',' order by line_position) from ledger_private.collected_invoice_lines where invoice_id='frozen-one'),
  'frozen-one-charge,frozen-one-credit','Input line order is retained independently of identity sorting');
select is((select sum(signed_amount_minor_units) from ledger_private.collected_invoice_lines where invoice_id='frozen-one'),100::numeric,'Credits reduce frozen allocations exactly once');
select is((select description from ledger_private.collected_invoice_lines where id='frozen-one-charge'),E'  Original charge\n','Frozen description retains whitespace');
select is((select source_snapshot from ledger_private.collected_invoice_lines where id='frozen-one-credit'),
  '{"basis":"paidInvoiceLine","invoiceId":"original","lineId":"original-line","amount":"20"}'::jsonb,'Original price provenance retained independently of current Item');
select lives_ok($$select pg_temp.freeze_invoice('different-payment',p_payment=>101)$$,'Storage does not decide open O-033 payment-equality policy');
select is((select t.amount_minor_units-i.total_minor_units from ledger_private.collected_invoices i
  join public.spike_transactions t on t.id=i.purchase_id where i.id='different-payment'),1::bigint,'Payment and allocation total stay separate facts');
select throws_ok($$select pg_temp.freeze_invoice('wrong-total',p_total=>99)$$,'23514',null,'Frozen lines must equal frozen Invoice total');
select throws_ok($$select pg_temp.freeze_invoice('unsealed',p_seal=>false)$$,'23514',null,'Unsealed assembly cannot commit');
select throws_ok($$select pg_temp.freeze_invoice('empty',p_lines=>false)$$,'23514',null,'Empty paid membership cannot commit');
select is((select count(*) from ledger_private.collected_invoices where id in ('wrong-total','unsealed','empty')),0::bigint,'Failed assembly rolls back headers');
select is((select count(*) from public.spike_transactions where id in ('payment-wrong-total','payment-unsealed','payment-empty')),0::bigint,'Failed assembly rolls back provisional synthetic payments');
select throws_ok($$update ledger_private.collected_invoices set sealed=false where id='frozen-one'$$,'55000',null,'Cannot reopen frozen contents');
select throws_ok($$update ledger_private.collected_invoice_lines set description='Changed' where id='frozen-one-charge'$$,'55000',null,'Cannot rewrite a frozen line');
select throws_ok($$delete from ledger_private.collected_invoice_lines where id='frozen-one-charge'$$,'55000',null,'Cannot delete frozen membership');
select throws_ok($$insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,
  source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
  values('late-zero','account-primary','frozen-one',2,'USD','item','late-source','frozen-item',1,'furnishings',0,'Late','{}')$$,
  '55000',null,'Even a zero-value line cannot be added after sealing');
update public.spike_items set description='Current edited Item',revision=2 where id='frozen-item';
select is((select description from ledger_private.collected_invoice_lines where id='frozen-one-charge'),E'  Original charge\n','Current Item edits do not change frozen description');
select throws_ok('truncate ledger_private.collected_invoice_lines','55000',null,'Frozen line truncation denied');
select ok((select bool_and(not has_table_privilege(r,'ledger_private.collected_invoices','SELECT,INSERT,UPDATE,DELETE,TRUNCATE')
  and not has_table_privilege(r,'ledger_private.collected_invoice_lines','SELECT,INSERT,UPDATE,DELETE,TRUNCATE'))
  from unnest(array['anon','authenticated','service_role']) r),'All API roles denied private snapshot access');
select ok((select bool_and(relrowsecurity and relforcerowsecurity) from pg_class
  where oid in ('ledger_private.collected_invoices'::regclass,'ledger_private.collected_invoice_lines'::regclass)),
  'Both private tables force RLS');
create function pg_temp.frozen_record(p_id text) returns jsonb language sql as $$
 select jsonb_build_object('invoice_id',p_id,'invoice_revision','1','account_id','account-primary',
   'project_id','frozen-project','client_id','client-existing','purchase_id','payment-'||p_id,
   'currency','USD','total_minor_units','100','lines',jsonb_build_array(
     jsonb_build_object('id',p_id||'-line','line_position',0,'source_kind','item','source_id',p_id||'-occurrence',
       'item_id','frozen-item','source_revision','2','category_id','furnishings','signed_amount_minor_units','100',
       'description',E'  Original\n第二行  ','source_snapshot_json','{"item":{"itemId":"frozen-item","occurrenceId":"'||p_id||'-occurrence"}}')))
$$;
select ledger_private.import_client_payment('payment-stored-record','account-primary','frozen-project','client-existing',
  101,'USD','synthetic-frozen','stored-record','\x02'::bytea);
select lives_ok($$select ledger_private.store_collected_invoice(pg_temp.frozen_record('stored-record'))$$,
  'Private store assembles and validates immutable contents without deciding payment equality');
create temporary table frozen_record_versions as
 select 'header' as kind,ctid::text as version from ledger_private.collected_invoices where id='stored-record'
 union all select 'line',ctid::text from ledger_private.collected_invoice_lines where invoice_id='stored-record';
select is(ledger_private.store_collected_invoice(pg_temp.frozen_record('stored-record')),
  ledger_private.read_collected_invoice('account-primary','stored-record'),'Exact replay reloads identical normalized records');
select ok((select ctid::text=(select version from frozen_record_versions where kind='header')
  from ledger_private.collected_invoices where id='stored-record') and
  (select ctid::text=(select version from frozen_record_versions where kind='line')
  from ledger_private.collected_invoice_lines where invoice_id='stored-record'),'Exact replay performs no header or line update');
select is(ledger_private.read_collected_invoice('account-primary','stored-record')#>>'{lines,0,description}',
  E'  Original\n第二行  ','Reload preserves exact description bytes');
select is(ledger_private.read_collected_invoice('account-primary','stored-record')#>>'{total_minor_units}',
  '100','Reload keeps amount as exact decimal text');
select lives_ok($$select ledger_private.store_collected_invoice(jsonb_set(pg_temp.frozen_record('stored-record'),
  '{lines,0,source_snapshot_json}',to_jsonb('{ "item" : {"occurrenceId":"stored-record-occurrence", "itemId":"frozen-item"} }'::text)))$$,
  'Source JSON formatting changes retain semantic replay identity');
select throws_ok($$select ledger_private.store_collected_invoice(jsonb_set(pg_temp.frozen_record('stored-record'),
  '{lines,0,description}','"Changed"'))$$,'22000',null,'Changed frozen description conflicts');
select throws_ok($$select ledger_private.store_collected_invoice(jsonb_set(pg_temp.frozen_record('stored-record'),
  '{lines,0,source_snapshot_json}','"{}"'))$$,'22000',null,'Changed source JSON conflicts');
select throws_ok($$select ledger_private.store_collected_invoice(jsonb_set(pg_temp.frozen_record('stored-record'),
  '{lines,0,line_position}','1'))$$,'22023',null,'A reordered or gapped input cannot silently normalize order');
select throws_ok($$select ledger_private.store_collected_invoice(jsonb_set(pg_temp.frozen_record('stored-record'),
  '{account_id}','"account-other"'))$$,'23503',null,'Store checks exact Purchase scope');
select throws_ok($$select ledger_private.read_collected_invoice('account-other','stored-record')$$,
  '23503',null,'Read rejects cross-Account scope instead of exposing contents');
select throws_ok($$select ledger_private.read_collected_invoice('account-primary','missing')$$,
  '23503',null,'Read rejects missing Invoice');
select ledger_private.import_client_payment('payment-failed-record','account-primary','frozen-project','client-existing',
  100,'USD','synthetic-frozen','failed-record','\x03'::bytea);
select throws_ok($$select ledger_private.store_collected_invoice(jsonb_set(pg_temp.frozen_record('failed-record'),
  '{total_minor_units}','"101"'))$$,'23514',null,'Store immediately rejects mismatched line sum before returning success');
select is((select count(*) from ledger_private.collected_invoices where id='failed-record'),0::bigint,
  'Failed store rolls back assembled header');
select is((select count(*) from ledger_private.collected_invoice_lines where invoice_id='failed-record'),0::bigint,
  'Failed store rolls back assembled lines');
select throws_ok($$select ledger_private.store_collected_invoice(jsonb_set(pg_temp.frozen_record('failed-record'),
  '{lines,0,signed_amount_minor_units}','"-0"'))$$,'22023',null,'Noncanonical signed amount rejected');
select throws_ok($$select ledger_private.store_collected_invoice(jsonb_set(pg_temp.frozen_record('failed-record'),
  '{lines,0,source_revision}','2'))$$,'22023',null,'Numeric source revision cannot replace required decimal string');
select ok((select bool_and(not has_function_privilege(r,'ledger_private.store_collected_invoice(jsonb)','EXECUTE')
  and not has_function_privilege(r,'ledger_private.read_collected_invoice(text,text)','EXECUTE'))
  from unnest(array['anon','authenticated','service_role']) r),'All API roles denied store/read functions');
select ok((select bool_and(not prosecdef and proconfig @> array['search_path=""']) from pg_proc
  where oid in ('ledger_private.store_collected_invoice(jsonb)'::regprocedure,
    'ledger_private.read_collected_invoice(text,text)'::regprocedure)),'Private store/read use invoker rights and empty search path');
set local role authenticated;
select throws_ok($$select ledger_private.store_collected_invoice('{}'::jsonb)$$,'42501',null,'Authenticated API cannot store');
select throws_ok($$select ledger_private.read_collected_invoice('account-primary','stored-record')$$,'42501',null,'Authenticated API cannot read');
reset role;
select * from finish();
rollback;
