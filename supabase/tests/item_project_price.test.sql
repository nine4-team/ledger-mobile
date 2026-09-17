begin;
set local search_path=public,extensions;
select no_plan();
insert into public.spike_items(id,account_id,description,created_by_principal_id)
values ('sale-price-item','account-primary','Price test','principal-owner');
insert into ledger_private.item_project_prices(account_id,item_id,amount_minor_units,currency,updated_at,updated_by_principal_id)
values ('account-primary','sale-price-item',100,'USD',now(),'principal-owner');
select throws_ok($$update ledger_private.item_project_prices set amount_minor_units=200 where item_id='sale-price-item'$$,
 '40001',null,'Stale revision cannot change price');
select lives_ok($$update ledger_private.item_project_prices set amount_minor_units=200,revision=2 where item_id='sale-price-item'$$,
 'Next revision changes only current project price');
select is((select amount_minor_units from ledger_private.item_project_prices where item_id='sale-price-item'),200::bigint,'Exact cents retained');
select throws_ok($$update ledger_private.item_project_prices set currency='EUR',revision=3 where item_id='sale-price-item'$$,
 '40001',null,'Currency cannot silently change');
select lives_ok($$update ledger_private.item_project_prices set amount_minor_units=0,revision=3 where item_id='sale-price-item'$$,
 'Current price may explicitly be zero; sale command still requires positive amount');
select lives_ok($$update ledger_private.item_project_prices set amount_minor_units=null,revision=4 where item_id='sale-price-item'$$,
 'Clear retains revision identity');
select is((select revision from ledger_private.item_project_prices where item_id='sale-price-item'),4::bigint,'Clear does not reset revision');
select is((select amount_minor_units from ledger_private.item_project_prices where item_id='sale-price-item'),null::bigint,'Clear differs from zero');
select throws_ok($$update ledger_private.item_project_prices set amount_minor_units=-1,revision=5 where item_id='sale-price-item'$$,
 '23514',null,'Negative current price remains forbidden');
select throws_ok($$delete from ledger_private.item_project_prices where item_id='sale-price-item'$$,
 '55000',null,'No silent deletion of price revision');
select throws_ok($$truncate ledger_private.item_project_prices$$,'55000',null,'No truncate bypass');
select ok(not has_table_privilege('authenticated','ledger_private.item_project_prices','UPDATE'),'No direct client writer');
select ok(not has_table_privilege('anon','ledger_private.item_project_prices','SELECT'),'No anonymous read');
select ok(not has_table_privilege('service_role','ledger_private.item_project_prices','UPDATE'),'No default service writer');
select * from finish();
rollback;
