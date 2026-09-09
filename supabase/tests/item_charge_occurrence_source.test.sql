begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_projects(id,account_id,client_id,display_name,created_at,updated_at,created_at_ms,updated_at_ms,created_by_principal_id)
values ('charge-project','account-primary','client-existing','Charge',now(),now(),1,1,'principal-owner');
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values ('charge-item','account-primary','Chair','principal-owner');
insert into public.spike_item_placements(id,account_id,item_id,scope_kind,project_id,started_at,started_by_principal_id)
values ('charge-placement','account-primary','charge-item','project','charge-project','2026-01-01','principal-owner');
insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,
 amount_minor_units,currency,created_at,created_by_principal_id)
values ('charge-one','account-primary','charge-project','charge-item','charge-placement','category-furnishings',
 12345,'USD','2026-01-01','principal-owner');
select throws_ok($$update ledger_private.item_charge_occurrences set amount_minor_units=0,revision=2 where id='charge-one'$$,
 '23514',null,'Charge demand must be positive');
select throws_ok($$update ledger_private.item_charge_occurrences set revision=3 where id='charge-one'$$,
 '55000',null,'Corrections require exactly the next revision');
select throws_ok($$update ledger_private.item_charge_occurrences set item_id='missing',revision=2 where id='charge-one'$$,
 '55000',null,'Physical identity cannot be rewritten');
select throws_ok($$update ledger_private.item_charge_occurrences set amount_minor_units=12346,revision=2,
 withdrawn_at='2026-02-01',withdrawn_by_principal_id='principal-owner' where id='charge-one'$$,
 '55000',null,'Withdrawal cannot rewrite the final amount');
select throws_ok($$update ledger_private.item_charge_occurrences set category_id='category-design-fee',revision=2,
 withdrawn_at='2026-02-01',withdrawn_by_principal_id='principal-owner' where id='charge-one'$$,
 '55000',null,'Withdrawal cannot rewrite the final category');
select throws_ok($$update ledger_private.item_charge_occurrences set currency='CAD',revision=2,
 withdrawn_at='2026-02-01',withdrawn_by_principal_id='principal-owner' where id='charge-one'$$,
 '55000',null,'Withdrawal cannot relabel the final currency');
update ledger_private.item_charge_occurrences set revision=2,
 withdrawn_at='2026-02-01',withdrawn_by_principal_id='principal-owner' where id='charge-one';
select is((select amount_minor_units from ledger_private.item_charge_occurrences where id='charge-one'),12345::bigint,
 'Withdrawal preserves exact original demand');
select throws_ok($$update ledger_private.item_charge_occurrences set withdrawn_at=null,withdrawn_by_principal_id=null,
 revision=3 where id='charge-one'$$,'55000',null,'Withdrawn charge cannot reopen as a new sale');
select throws_ok('delete from ledger_private.item_charge_occurrences','55000',null,'Charge history is retained');
select throws_ok('truncate ledger_private.item_charge_occurrences','55000',null,'Charge history cannot be truncated');
set local role authenticated;
select throws_ok('select * from ledger_private.item_charge_occurrences','42501',null,'Narrow read grant excludes private charge metadata');
select throws_ok('delete from ledger_private.item_charge_occurrences','42501',null,'Draft source grants no write authority');
reset role;
insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,
 amount_minor_units,currency,created_at,created_by_principal_id)
values ('charge-two','account-primary','charge-project','charge-item','charge-placement','category-furnishings',
 12345,'USD','2026-02-02','principal-owner');
create function pg_temp.collect_charge(p_source text,p_amount bigint default 12345,p_revision bigint default 1)
returns void language plpgsql as $$
begin
  perform ledger_private.import_client_payment('payment-'||p_source,'account-primary','charge-project','client-existing',
    p_amount,'USD','synthetic-charge',p_source,'\x01'::bytea);
  insert into ledger_private.collected_invoices(id,account_id,project_id,client_id,purchase_id,invoice_revision,currency,total_minor_units)
  values('invoice-'||p_source,'account-primary','charge-project','client-existing','payment-'||p_source,1,'USD',p_amount);
  insert into ledger_private.collected_invoice_lines(id,account_id,invoice_id,line_position,currency,source_kind,source_id,item_id,
    source_revision,category_id,signed_amount_minor_units,description,source_snapshot)
  values('line-'||p_source,'account-primary','invoice-'||p_source,0,'USD','item',p_source,'charge-item',
    p_revision,'category-furnishings',p_amount,'Chair','{}');
  update ledger_private.collected_invoices set sealed=true where id='invoice-'||p_source;
  set constraints all immediate;
  set constraints all deferred;
end;
$$;
select throws_ok($$select pg_temp.collect_charge('charge-one')$$,'23514',null,'Withdrawn charge cannot be collected');
select throws_ok($$select pg_temp.collect_charge('charge-two',12344)$$,'23514',null,'Frozen amount must match exact current charge');
select throws_ok($$select pg_temp.collect_charge('charge-two',12345,2)$$,'23514',null,'Frozen revision must match exact current charge');
select lives_ok($$select pg_temp.collect_charge('charge-two')$$,'Exact existing charge can be frozen');
select throws_ok($$update ledger_private.item_charge_occurrences set amount_minor_units=12346,revision=2
 where id='charge-two'$$,'55000',null,'Frozen charge amount cannot be corrected in place');
select throws_ok($$update ledger_private.item_charge_occurrences set withdrawn_at='2026-03-01',withdrawn_by_principal_id='principal-owner',revision=2
 where id='charge-two'$$,'55000',null,'Paid removal cannot erase demand instead of creating a separate credit');
select lives_ok($$select pg_temp.collect_charge('legacy-source')$$,'Generic legacy frozen evidence remains retained without inventing a charge');
select throws_ok($$insert into ledger_private.item_charge_occurrences(id,account_id,project_id,item_id,placement_id,category_id,
 amount_minor_units,currency,created_by_principal_id) values('legacy-source','account-primary','charge-project','charge-item',
 'charge-placement','category-furnishings',12345,'USD','principal-owner')$$,
 '55000','Import charge source before its frozen membership','Cannot introduce mutable charge behind already frozen legacy evidence');
set local role authenticated;
select set_config('request.jwt.claims','{"sub":"10000000-0000-0000-0000-000000000001","role":"authenticated"}',true);
select is((select accounting#>>'{evidence,billableOccurrences,0,phase,kind}'
 from ledger_private.project_item_accounting_evidence('account-primary','charge-project')),
 'frozenPaid','Full member report derives paid phase from exact immutable membership');
select is((select accounting#>>'{evidence,billableOccurrences,0,phase,invoiceId}'
 from ledger_private.project_item_accounting_evidence('account-primary','charge-project')),
 'invoice-charge-two','Exact Invoice identity is retained in report provenance');
select is((select count(*) from ledger_private.project_item_accounting_evidence('account-other','charge-project')),
 0::bigint,'Foreign Account cannot expose charge eligibility or membership');
select throws_ok('select source_snapshot from ledger_private.collected_invoice_lines','42501',null,
 'Physical report read grant excludes raw frozen source JSON');
select throws_ok('select total_minor_units from ledger_private.collected_invoices','42501',null,
 'Physical report read grant excludes private Invoice totals');
reset role;
update spike_account_memberships set financial_access='limited' where account_id='account-primary' and principal_id='principal-owner';
set local role authenticated;
select is((select count(*) from ledger_private.project_item_accounting_evidence('account-primary','charge-project')),
 0::bigint,'Same JWT downgrade removes business-paid report evidence');
select is((select count(id) from ledger_private.item_charge_occurrences),0::bigint,'RLS denies direct restricted charge reads');
select is((select count(id) from ledger_private.collected_invoice_lines),0::bigint,'RLS denies direct restricted frozen membership reads');
reset role;
select * from finish();
rollback;
